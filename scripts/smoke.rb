require "fileutils"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "tmpdir"
require "uri"

# Local mode ignores development URLs; explicit CI mode borrows only the service.
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
    if ENV["CI"] == "true"
      @service_url = ENV.fetch("DATABASE_URL")
      begin
        url = URI.parse(@service_url)
      rescue URI::InvalidURIError
        raise "CI DATABASE_URL must be a valid PostgreSQL URL"
      end
      raise "CI DATABASE_URL must be a PostgreSQL URL without query or fragment" unless %w[postgres postgresql].include?(url.scheme) && url.host && !url.query && !url.fragment
      @password = URI.decode_www_form_component(url.password.to_s)
      command("database-create", "bundle", "exec", "ruby", File.join(ROOT, "scripts/test_database.rb"), "create", @database,
        directory: File.join(ROOT, "backend"), env: { "SMOKE_SERVICE_URL" => @service_url })
      @service_database_created = true
      url.path = "/#{@database}"
      @env["DATABASE_URL"] = url.to_s
    else
      start_postgres
    end
    @env["TEST_DATABASE_URL"] = @env.fetch("DATABASE_URL")
    run_tests
  ensure
    cleanup
  end

  def start_postgres
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
  end

  def run_tests
    backend = File.join(ROOT, "backend")
    puts command("database-migrate", "bundle", "exec", "rails", "db:migrate", directory: backend,
      env: { "SCHEMA" => File.join(@directory, "schema.rb") })
    probe = 'connection = ActiveRecord::Base.connection; raise "wrong database" unless connection.select_value("SELECT current_database()") == ENV.fetch("SMOKE_DATABASE"); raise "unexpected PostgreSQL version" unless connection.select_value("SHOW server_version").start_with?("18.3"); raise "connection failed" unless connection.select_value("SELECT 1") == 1; puts "PostgreSQL connection verified"'
    puts command("database-probe", "bundle", "exec", "rails", "runner", probe,
      directory: backend, env: { "SMOKE_DATABASE" => @database })
    if @mode == "--backend-test"
      puts command("rspec", "ruby", "bin/test", directory: backend,
        env: { "DATABASE_URL" => nil })
      return
    end
    puts command("database-seed", "bundle", "exec", "rails", "db:seed", directory: backend)
    fixtures = 'MeetingType.create!(name: "Extended discussion", description: "An additional published offer.", duration_minutes: 45, slug: "extended", published: true); MeetingType.create!(name: "Private offer", duration_minutes: 20, slug: "private")'
    puts command("meeting-type-fixtures", "bundle", "exec", "rails", "runner", fixtures, directory: backend)
    backend_port = free_port
    @env["ADMIN_USERNAME"] = "owner-browser"
    @env["ADMIN_PASSWORD"] = "browser-only-password-24!"
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
    app_port = free_port
    start("vite-application", "node", "node_modules/vite/bin/vite.js", "--host", "127.0.0.1", "--port", app_port.to_s, "--strictPort",
      directory: File.join(ROOT, "frontend"),
      env: { "BACKEND_PORT" => backend_port.to_s, "SMOKE_RUNTIME_DIR" => @directory })
    ready("Vite application") { http_ready(app_port, "/") }
    puts command("admin-navigation", "node", "e2e/admin-navigation.mjs",
      directory: File.join(ROOT, "frontend"), env: { "APP_ORIGIN" => "http://127.0.0.1:#{app_port}" })
    puts command("create-meeting-type", "node", "e2e/create-meeting-type.mjs",
      directory: File.join(ROOT, "frontend"), env: { "APP_ORIGIN" => "http://127.0.0.1:#{app_port}" })
    puts command("home-fixtures", "bundle", "exec", "rails", "runner", File.join(ROOT, "test/fixtures/admin_home.rb"),
      directory: backend)
    puts command("manage-meeting-types", "node", "e2e/manage-meeting-types.mjs",
      directory: File.join(ROOT, "frontend"), env: { "APP_ORIGIN" => "http://127.0.0.1:#{app_port}" })
    puts command("calendar-navigation", "node", "e2e/calendar-navigation.mjs",
      directory: File.join(ROOT, "frontend"), env: { "APP_ORIGIN" => "http://127.0.0.1:#{app_port}" })
    # A fresh application process must read the same persisted offers.
    offers_url = URI("http://127.0.0.1:#{backend_port}/api/v1/meeting-types")
    persisted_offers = Net::HTTP.get(offers_url)
    stop(rails_pid)
    start("rails-restarted", "bundle", "exec", "rails", "server", "-b", "127.0.0.1", "-p", backend_port.to_s,
      "-P", File.join(@directory, "rails-restarted.pid"), "--log-to-stdout", directory: backend)
    ready("restarted Rails") { http_ready(backend_port, "/up") }
    raise "meeting types changed across application restart" unless Net::HTTP.get(offers_url) == persisted_offers
    puts command("chromium-restarted", "node", "node_modules/vitest/vitest.mjs", "run", "--config", "vitest.browser.config.ts",
      timeout: 120, directory: File.join(ROOT, "frontend"),
      env: { "BACKEND_PORT" => backend_port.to_s, "SMOKE_BROWSER_PORT" => free_port.to_s,
        "SMOKE_RUNTIME_DIR" => @directory })
    puts command("occupy-calendar", "bundle", "exec", "rails", "runner",
      "Booking.transaction { Booking.delete_all; Occupancy.delete_all; Occupancy.create!(starts_at: Time.current - 1.day, ends_at: Time.current + 15.days) }", directory: backend)
    puts command("chromium-occupied", "node", "node_modules/vitest/vitest.mjs", "run", "--config", "vitest.browser.config.ts",
      timeout: 120, directory: File.join(ROOT, "frontend"),
      env: { "BACKEND_PORT" => backend_port.to_s, "SMOKE_BROWSER_PORT" => free_port.to_s,
        "SMOKE_RUNTIME_DIR" => @directory, "SMOKE_OCCUPIED_CALENDAR" => "1" })
    puts command("hide-meeting-types", "bundle", "exec", "rails", "runner",
      "MeetingType.update_all(published: false)", directory: backend)
    puts command("chromium-empty", "node", "node_modules/vitest/vitest.mjs", "run", "--config", "vitest.browser.config.ts",
      timeout: 120, directory: File.join(ROOT, "frontend"),
      env: { "BACKEND_PORT" => backend_port.to_s, "SMOKE_BROWSER_PORT" => free_port.to_s,
        "SMOKE_RUNTIME_DIR" => @directory, "SMOKE_EMPTY_MEETING_TYPES" => "1" })
  end

  def cleanup
    failed = $!
    @active.reverse_each.to_a.each { |pid| stop(pid) }
    if @service_database_created
      command("database-drop", "bundle", "exec", "ruby", File.join(ROOT, "scripts/test_database.rb"), "drop", @database,
        directory: File.join(ROOT, "backend"), env: { "SMOKE_SERVICE_URL" => @service_url })
    end
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
        text = text.gsub(@service_url, "[REDACTED]") if @service_url
        text = text.gsub(@password, "[REDACTED]") if @password && !@password.empty?
        warn "--- #{File.basename(path)} ---\n#{text}"
      end
    end
    puts "SMOKE_RESOURCES #{JSON.generate(container: @service_url ? nil : @id, database: @database, pids: @children, directory: @directory)}"
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
