require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "securerandom"
require "socket"
require "timeout"
require "uri"

ROOT = File.realpath(File.expand_path("..", __dir__))
WORKTREE_ID = "wt-#{Digest::SHA256.hexdigest(ROOT)[0, 20]}"

class Services
  KEYS = %w[WORKTREE_ID COMPOSE_PROJECT_NAME BACKEND_PORT FRONTEND_PORT POSTGRES_PORT
    POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB DATABASE_URL TEST_DATABASE_URL].freeze
  STATE = File.join(ROOT, ".services")
  CONFIG = File.join(STATE, "environment.json")

  def initialize
    @env = {}
  end

  def configuration
    @env = KEYS.to_h { |key| [key, ENV[key].to_s] }
    KEYS.each { |key| raise "#{key} is required" if @env[key].empty? }
    raise "WORKTREE_ID must be #{WORKTREE_ID} for this absolute worktree path" unless @env["WORKTREE_ID"] == WORKTREE_ID
    raise "COMPOSE_PROJECT_NAME must be scaffold-#{WORKTREE_ID}" unless @env["COMPOSE_PROJECT_NAME"] == "scaffold-#{WORKTREE_ID}"
    %w[BACKEND_PORT FRONTEND_PORT POSTGRES_PORT].each do |key|
      raise "#{key} must be an integer port from 1024 to 65535" unless @env[key].match?(/\A\d+\z/) && (1024..65535).cover?(@env[key].to_i)
    end
    raise "All three service ports must differ" unless @env.values_at("BACKEND_PORT", "FRONTEND_PORT", "POSTGRES_PORT").map(&:to_i).uniq.size == 3
    %w[POSTGRES_USER POSTGRES_DB].each do |key|
      raise "#{key} must be a lowercase PostgreSQL identifier (maximum 63 bytes)" unless @env[key].match?(/\A[a-z][a-z0-9_]{0,62}\z/)
    end
    raise "POSTGRES_DB must contain this worktree's ID (with underscores)" unless @env["POSTGRES_DB"].include?(WORKTREE_ID.tr("-", "_"))
    urls = %w[DATABASE_URL TEST_DATABASE_URL].map do |key|
      begin
        url = URI.parse(@env[key])
      rescue URI::InvalidURIError
        raise "#{key} must be a valid PostgreSQL URL"
      end
      valid = %w[postgres postgresql].include?(url.scheme) && url.host == "127.0.0.1" &&
        url.port == @env["POSTGRES_PORT"].to_i && URI.decode_www_form_component(url.user.to_s) == @env["POSTGRES_USER"] &&
        URI.decode_www_form_component(url.password.to_s) == @env["POSTGRES_PASSWORD"] && !url.query && !url.fragment &&
        url.path.delete_prefix("/").match?(/\A[a-z][a-z0-9_]{0,62}\z/)
      raise "#{key} must target this worktree's loopback PostgreSQL with matching credentials" unless valid
      url
    end
    raise "DATABASE_URL must name POSTGRES_DB" unless urls.first.path == "/#{@env['POSTGRES_DB']}"
    raise "TEST_DATABASE_URL must name a distinct worktree-local test database" unless urls.last.path != urls.first.path && urls.last.path.include?(WORKTREE_ID.tr("-", "_"))
    @env["SERVICE_WORKTREE_PATH"] = ROOT
  end

  def port_free(key)
    TCPServer.open("127.0.0.1", @env.fetch(key).to_i, &:close)
  rescue Errno::EADDRINUSE, Errno::EACCES
    raise "#{key} #{@env[key]} is occupied; choose a free explicit port (no automatic fallback)"
  end

  def saved
    raise "No saved service configuration; run db:up or dev:start first" unless File.exist?(CONFIG)
    @env = JSON.parse(File.read(CONFIG))
    raise "Saved configuration belongs to another worktree" unless @env["SERVICE_WORKTREE_PATH"] == ROOT && @env["WORKTREE_ID"] == WORKTREE_ID
  end

  def persist
    if File.exist?(CONFIG)
      raise "Service configuration changed; dev:stop first, then remove .services/environment.json explicitly (database data is retained)" unless JSON.parse(File.read(CONFIG)) == @env
    else
      File.write(CONFIG, JSON.pretty_generate(@env), mode: "w", perm: 0o600)
    end
  end

  def run(*args, allow_failure: false, seconds: 90, env: {}, directory: ROOT)
    output = +""
    status = nil
    Open3.popen2e(@env.merge(env), *args, chdir: directory, pgroup: true) do |input, stream, wait|
      input.close
      begin
        Timeout.timeout(seconds) do
          output << stream.read
          status = wait.value
        end
      rescue Timeout::Error
        Process.kill("TERM", -wait.pid) rescue nil
        sleep 0.2
        Process.kill("KILL", -wait.pid) rescue nil
        raise "Command timed out after #{seconds}s: #{args.first(3).join(' ')}"
      end
    end
    # Never print credentials from subprocess diagnostics.
    %w[DATABASE_URL TEST_DATABASE_URL POSTGRES_PASSWORD].each do |key|
      value = @env[key]
      output.gsub!(value, "[REDACTED]") if value && !value.empty?
    end
    raise "Command failed: #{args.first(3).join(' ')}\n#{output}" unless status.success? || allow_failure
    [output, status.success?]
  end

  def compose(*args, **options)
    run("docker-compose", "--project-directory", ROOT, "-f", File.join(ROOT, "compose.yml"),
      "-p", @env.fetch("COMPOSE_PROJECT_NAME"), *args, **options)
  end

  def ownership
    project = @env.fetch("COMPOSE_PROJECT_NAME")
    [["volume", "#{project}_postgres-data"], ["network", "#{project}_default"]].each do |kind, name|
      output, exists = run("docker", kind, "inspect", name, allow_failure: true)
      next unless exists
      labels = JSON.parse(output).first.fetch("Labels", {}) || {}
      raise "Refusing foreign #{kind} #{name}: worktree ownership label differs" unless labels["dev.scaffold.worktree"] == ROOT
    end
    output, = compose("ps", "-a", "-q", "postgres")
    output.lines.map(&:strip).reject(&:empty?).each do |id|
      info, = run("docker", "inspect", id)
      labels = JSON.parse(info).first.fetch("Config").fetch("Labels")
      raise "Refusing foreign PostgreSQL container #{id}" unless labels["dev.scaffold.worktree"] == ROOT
    end
  end

  def db_up
    ownership
    output, = compose("ps", "--status", "running", "-q", "postgres")
    new_database = output.strip.empty?
    port_free("POSTGRES_PORT") if new_database
    persist
    attempted_start = true
    puts compose("up", "-d", "--wait", "--wait-timeout", "45", "postgres").first
    new_database
  rescue StandardError
    warn compose("logs", "--no-color", "--tail", "40", "postgres", allow_failure: true).first
    compose("stop", "--timeout", "10", "postgres", allow_failure: true) if attempted_start && new_database
    raise
  end

  def prepare
    puts run("bundle", "exec", "rails", "db:prepare", env: { "RAILS_ENV" => "development" }, directory: "#{ROOT}/backend", seconds: 90).first
    puts run("bundle", "exec", "rails", "db:prepare", env: { "RAILS_ENV" => "test", "DATABASE_URL" => @env.fetch("TEST_DATABASE_URL") }, directory: "#{ROOT}/backend", seconds: 90).first
  end

  def ready(name)
    key, path = name == "backend" ? ["BACKEND_PORT", "/up"] : ["FRONTEND_PORT", "/"]
    response = Net::HTTP.start("127.0.0.1", @env.fetch(key).to_i, nil, nil, nil, nil, open_timeout: 1, read_timeout: 1) { |http| http.get(path) }
    response.is_a?(Net::HTTPSuccess)
  rescue SystemCallError, IOError, Timeout::Error
    false
  end

  def serve(name)
    if name == "backend"
      Dir.chdir(File.join(ROOT, "backend"))
      exec(@env.merge("RAILS_ENV" => "development", "PIDFILE" => "#{STATE}/rails.pid"), "bundle", "exec", "rails", "server", "-b", "127.0.0.1", "-p", @env.fetch("BACKEND_PORT"))
    elsif name == "frontend"
      Dir.chdir(File.join(ROOT, "frontend"))
      exec(@env, "npm", "run", "dev", "--", "--host", "127.0.0.1", "--port", @env.fetch("FRONTEND_PORT"), "--strictPort")
    else
      raise "Unknown service #{name}"
    end
  end

  def diagnostics
    puts "Worktree: #{ROOT}\nProject: #{@env['COMPOSE_PROJECT_NAME']}"
    puts "Ports: Rails=#{@env['BACKEND_PORT']} Vite=#{@env['FRONTEND_PORT']} PostgreSQL=#{@env['POSTGRES_PORT']}"
    output, compose_ok = compose("ps", "-a", allow_failure: true)
    puts output
    output, daemons_ok = run("mise", "daemons", "ls", allow_failure: true)
    puts output
    healthy = compose_ok && daemons_ok
    %w[backend frontend].each do |name|
      next if ready(name)
      healthy = false
      warn "#{name} is not HTTP-ready; recent daemon logs:"
      warn run("mise", "daemons", "logs", name, "-n", "40", allow_failure: true).first
    end
    _, db_ok = compose("exec", "-T", "postgres", "pg_isready", "-U", @env.fetch("POSTGRES_USER"), "-d", @env.fetch("POSTGRES_DB"), allow_failure: true)
    unless db_ok
      healthy = false
      warn compose("logs", "--no-color", "--tail", "20", "postgres", allow_failure: true).first
    end
    healthy
  end

  def execute(command, name = nil)
    if command == "dev:env"
      db = "app_#{WORKTREE_ID.tr('-', '_')}"
      password = SecureRandom.hex(24)
      puts "# Choose three free ports; these are examples, not reservations.\n[env]"
      values = { "WORKTREE_ID" => WORKTREE_ID, "COMPOSE_PROJECT_NAME" => "scaffold-#{WORKTREE_ID}",
        "BACKEND_PORT" => "3101", "FRONTEND_PORT" => "5101", "POSTGRES_PORT" => "5501",
        "POSTGRES_USER" => "developer", "POSTGRES_PASSWORD" => password, "POSTGRES_DB" => db,
        "DATABASE_URL" => "postgresql://developer:#{password}@127.0.0.1:5501/#{db}",
        "TEST_DATABASE_URL" => "postgresql://developer:#{password}@127.0.0.1:5501/#{db}_test" }
      values.each { |key, value| puts "#{key} = #{value.to_json}" }
      return
    end
    if %w[serve ready dev:status dev:stop].include?(command)
      saved
    else
      configuration
    end
    case command
    when "dev:validate"
      %w[BACKEND_PORT FRONTEND_PORT POSTGRES_PORT].each { |key| port_free(key) }
      puts "Configuration valid; explicit ports are currently free"
    when "db:up" then db_up
    when "db:prepare"
      db_up
      prepare
    when "dev:start"
      %w[BACKEND_PORT FRONTEND_PORT].each { |key| port_free(key) }
      begin
        new_database = db_up
        prepare
        puts run("mise", "daemons", "start", "backend", "frontend").first
      rescue StandardError
        begin
          diagnostics if File.exist?(CONFIG)
        rescue StandardError => diagnostic_error
          warn "Diagnostics failed: #{diagnostic_error.message}"
        ensure
          run("mise", "daemons", "stop", "backend", "frontend", allow_failure: true)
          compose("stop", "--timeout", "10", "postgres", allow_failure: true) if new_database
        end
        raise
      end
    when "dev:status"
      raise "One or more worktree services are not ready" unless diagnostics
    when "dev:stop"
      ownership
      # Both commands are attempted, but a failure is never reported as success.
      daemon_output, daemon_ok = run("mise", "daemons", "stop", "backend", "frontend", allow_failure: true)
      puts daemon_output
      puts compose("stop", "--timeout", "10", "postgres").first
      raise "Daemon stop failed; see output above" unless daemon_ok
      puts "Stopped only this worktree; PostgreSQL volume and saved configuration retained"
    when "serve" then serve(name)
    when "ready" then exit(ready(name) ? 0 : 1)
    else raise "Unknown command #{command}"
    end
  end
end

begin
  FileUtils.mkdir_p(Services::STATE, mode: 0o700)
  # Readiness/foreground daemons must not contend with their starting lifecycle task.
  if %w[serve ready dev:env dev:validate].include?(ARGV.first)
    Services.new.execute(*ARGV)
  else
    File.open(File.join(Services::STATE, "lifecycle.lock"), "w", 0o600) do |lock|
      raise "Another lifecycle command is running in this worktree" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      Services.new.execute(*ARGV)
    end
  end
rescue StandardError => e
  warn e.message
  exit 1
end
