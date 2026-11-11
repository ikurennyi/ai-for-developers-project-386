require "fileutils"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "tmpdir"

# Never reads development connection settings or invokes dev:stop.
class Smoke
  ROOT = File.expand_path("..", __dir__)
  IMAGE = "postgres:18.3-alpine@sha256:54451ecb8ab38c24c3ec123f2fd501303a3a1856a5c66e98cecf2460d5e1e9d7"

  def initialize(mode)
    raise "unknown smoke option" unless [nil, "--backend-test", "--fail-after-ready", "--probe-readiness-timeout", "--probe-browser-failure"].include?(mode)
    @mode = mode
    @directory = Dir.mktmpdir("scaffold-smoke-")
    @id = "smoke-#{SecureRandom.hex(10)}"
    @database = @id.tr("-", "_")
    @children, @active, @logs = [], [], []
    @env = { "RAILS_ENV" => "test", "DISABLE_BOOTSNAP" => "1", "TMPDIR" => @directory,
      "RAILS_LOG_TO_STDOUT" => "1", "SECRET_KEY_BASE" => SecureRandom.hex(64) }
  end

  def start(label, *command, directory: ROOT, env: {})
    path = File.join(@directory, "#{label}.log")
    @logs << path
    pid = Process.spawn(@env.merge(env), *command, chdir: directory, out: path, err: [:child, :out], pgroup: true)
    @children << pid
    @active << pid
    pid
  end

  def stop(pid)
    return unless @active.delete(pid)
    terminate(pid)
  end

  def terminate(pid)
    Process.kill("TERM", -pid)
    deadline = clock + 5
    loop do
      break if Process.waitpid(pid, Process::WNOHANG) || clock >= deadline
      sleep 0.1
    end
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  ensure
    begin
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil
    end
    begin
      Process.waitpid(pid)
    rescue Errno::ECHILD
      nil
    end
  end

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def command(label, *args, timeout: 90, **options)
    pid = start(label, *args, **options)
    deadline = clock + timeout
    loop do
      if Process.waitpid(pid, Process::WNOHANG)
        raise "#{label} failed (exit #{$?.exitstatus}); see diagnostics" unless $?.success?
        return File.read(@logs.last)
      end
      raise "#{label} timed out after #{timeout}s" if clock >= deadline
      sleep 0.1
    end
  ensure
    stop(pid) if pid
  end

  def free_port
    socket = TCPServer.new("127.0.0.1", 0)
    socket.addr[1]
  ensure
    socket&.close
  end

  def ready(label, timeout: 45)
    deadline = clock + timeout
    loop do
      return if yield
      raise "#{label} readiness timed out after #{timeout}s" if clock >= deadline
      sleep 0.2
    end
  end

  def http_ready(port, path)
    Net::HTTP.start("127.0.0.1", port, nil, open_timeout: 1, read_timeout: 1) { |http| http.get(path).code == "200" }
  rescue SystemCallError, IOError, Timeout::Error
    false
  end

  def run
    stack = @mode == "--backend-test" ? "PostgreSQL + RSpec" : "PostgreSQL/Rails/Vitest Vite + Chromium"
    puts "Smoke #{@id}: temporary #{stack}"
    @password = password = SecureRandom.hex(24)
    command("postgres-start", "docker", "run", "--detach", "--rm", "--name", @id,
      "--cidfile", File.join(@directory, "container.id"),
      "--publish", "127.0.0.1::5432", "--tmpfs", "/var/lib/postgresql",
      "--env", "POSTGRES_USER=smoke", "--env", "POSTGRES_PASSWORD=#{password}",
      "--env", "POSTGRES_DB=#{@database}", IMAGE)
    ready("PostgreSQL") do
      # TCP avoids mistaking the image's temporary init-only Unix socket for readiness.
      command("postgres-ready", "docker", "exec", @id, "pg_isready", "-h", "127.0.0.1", "-U", "smoke", "-d", @database, timeout: 5)
      true
    rescue RuntimeError
      false
    end
    binding = command("postgres-port", "docker", "port", @id, "5432/tcp").strip
    raise "unexpected PostgreSQL binding" unless binding.match?(/\A127\.0\.0\.1:\d+\z/)
    port = binding.split(":").last
    @env["DATABASE_URL"] = "postgresql://smoke:#{password}@127.0.0.1:#{port}/#{@database}"
    @env["TEST_DATABASE_URL"] = @env.fetch("DATABASE_URL")
    backend = File.join(ROOT, "backend")
    probe = 'connection = ActiveRecord::Base.connection; raise "wrong database" unless connection.select_value("SELECT current_database()") == ENV.fetch("SMOKE_DATABASE"); raise "unexpected PostgreSQL version" unless connection.select_value("SHOW server_version").start_with?("18.3"); raise "connection failed" unless connection.select_value("SELECT 1") == 1; puts "PostgreSQL connection verified"'
    puts command("database-probe", "bundle", "exec", "rails", "runner", probe,
      directory: backend, env: { "SMOKE_DATABASE" => @database })
    if @mode == "--backend-test"
      puts command("rspec", "ruby", "bin/test", directory: backend,
        env: { "DATABASE_URL" => nil })
      return
    end
    backend_port = free_port
    rails_pid = start("rails", "bundle", "exec", "rails", "server", "-b", "127.0.0.1", "-p", backend_port.to_s,
      "-P", File.join(@directory, "rails.pid"), "--log-to-stdout", directory: backend)
    path = @mode == "--probe-readiness-timeout" ? "/deliberately-missing" : "/up"
    ready("Rails at 127.0.0.1:#{backend_port}#{path}", timeout: @mode == "--probe-readiness-timeout" ? 2 : 45) do
      http_ready(backend_port, path)
    end
    raise "intentional failure after real server readiness" if @mode == "--fail-after-ready"
    stop(rails_pid) if @mode == "--probe-browser-failure"
    puts command("chromium", "node", "node_modules/vitest/vitest.mjs", "run", "--config", "vitest.browser.config.ts",
      timeout: 120, directory: File.join(ROOT, "frontend"),
      env: { "BACKEND_PORT" => backend_port.to_s, "SMOKE_BROWSER_PORT" => free_port.to_s,
        "SMOKE_RUNTIME_DIR" => @directory })
  ensure
    cleanup
  end

  def cleanup
    failed = $!
    @active.reverse_each.to_a.each { |pid| stop(pid) }
    cidfile = File.join(@directory, "container.id")
    if File.exist?(cidfile)
      cid = File.read(cidfile).strip
      if failed && !cid.empty?
        begin
          command("postgres-diagnostics", "docker", "logs", "--tail", "35", cid, timeout: 10)
        rescue StandardError => error
          warn "PostgreSQL diagnostics unavailable: #{error.message}"
        end
      end
      command("postgres-remove", "docker", "rm", "--force", "--volumes", cid, timeout: 30) unless cid.empty?
    end
  ensure
    if $!
      @logs.uniq.each do |path|
        next unless File.file?(path)
        text = File.readlines(path).last(35).join
        text = text.gsub(@password, "[REDACTED]") if @password
        warn "--- #{File.basename(path)} ---\n#{text}"
      end
    end
    puts "SMOKE_RESOURCES #{JSON.generate(container: @id, database: @database, pids: @children, directory: @directory)}"
    FileUtils.remove_entry(@directory) if File.directory?(@directory)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    trap("TERM") { raise Interrupt, "smoke terminated" }
    Smoke.new(ARGV.first).run
  rescue StandardError, Interrupt => error
    warn "Smoke failed: #{error.message}"
    exit 1
  end
end
