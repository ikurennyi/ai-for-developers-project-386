# Opt-in real service probes. Supply two prepared, dedicated worktree paths.
# This starts/stops their dev services and writes a retention-probe table.
gem "minitest", "6.1.0" # Already pinned in backend/Gemfile.lock.
require "minitest/autorun"
require "open3"
require "json"
require "net/http"
require "securerandom"
require "socket"

WORKTREES = ARGV.shift(2).map { |path| File.realpath(path) }
abort "Usage: ruby test/services_integration_test.rb WORKTREE_A WORKTREE_B" unless WORKTREES.size == 2 && WORKTREES.uniq.size == 2

class ServicesIntegrationTest < Minitest::Test
  def task(root, task, success: true)
    output, status = Open3.capture2e("mise", "run", task, chdir: root)
    assert_equal success, status.success?, output
    output
  end

  def env(root)
    JSON.parse(File.read(File.join(root, ".services/environment.json")))
  end

  def sql(root, statement)
    config = env(root)
    output, status = Open3.capture2e("mise", "exec", "--", "docker", "exec",
      "#{config.fetch('COMPOSE_PROJECT_NAME')}-postgres-1", "psql", "-U", config.fetch("POSTGRES_USER"),
      "-d", config.fetch("POSTGRES_DB"), "-At", "-v", "ON_ERROR_STOP=1", "-c", statement, chdir: root)
    assert status.success?, output
    output.strip
  end

  def capture(root, *command)
    output, status = Open3.capture2e(*command, chdir: root)
    assert status.success?, output
    output
  end

  def test_two_worktrees_are_independent_and_stop_preserves_data
    a, b = WORKTREES
    WORKTREES.each { |root| task(root, "dev:start") }
    WORKTREES.each { |root| task(root, "dev:status") }
    a_env, b_env = WORKTREES.map { |root| env(root) }
    %w[WORKTREE_ID COMPOSE_PROJECT_NAME POSTGRES_DB BACKEND_PORT FRONTEND_PORT POSTGRES_PORT].each do |key|
      refute_equal a_env.fetch(key), b_env.fetch(key), "shared #{key}"
    end
    pids = WORKTREES.map { |root| File.read(File.join(root, ".services/rails.pid")).strip }
    refute_equal(*pids)
    daemons = WORKTREES.map { |root| JSON.parse(capture(root, "mise", "daemons", "ls", "--json")) }
    assert_empty daemons.first.map { |d| d.fetch("id") } & daemons.last.map { |d| d.fetch("id") }
    assert_empty daemons.first.map { |d| d.fetch("state_dir") } & daemons.last.map { |d| d.fetch("state_dir") }
    assert_equal 4, daemons.flatten.map { |d| d.fetch("pid") }.compact.uniq.size
    containers = WORKTREES.map do |root|
      JSON.parse(capture(root, "mise", "exec", "--", "docker", "inspect", "#{env(root).fetch('COMPOSE_PROJECT_NAME')}-postgres-1")).first
    end
    refute_equal containers.first.fetch("Id"), containers.last.fetch("Id")
    refute_equal containers.first.fetch("Mounts").first.fetch("Name"), containers.last.fetch("Mounts").first.fetch("Name")
    assert_empty containers.first.fetch("NetworkSettings").fetch("Networks").keys & containers.last.fetch("NetworkSettings").fetch("Networks").keys
    token = SecureRandom.hex(10)
    sql(a, "CREATE TABLE IF NOT EXISTS lifecycle_retention_probe (token text PRIMARY KEY); INSERT INTO lifecycle_retention_probe VALUES ('#{token}')")
    assert_equal "", sql(b, "SELECT tablename FROM pg_tables WHERE tablename = 'lifecycle_retention_probe'")
    task(a, "dev:stop")
    task(a, "dev:status", success: false)
    response = Net::HTTP.get_response(URI("http://127.0.0.1:#{b_env.fetch('BACKEND_PORT')}/up"))
    assert_equal "200", response.code
    assert_equal "", sql(b, "SELECT tablename FROM pg_tables WHERE tablename = 'lifecycle_retention_probe'")
    task(a, "db:up")
    assert_equal token, sql(a, "SELECT token FROM lifecycle_retention_probe WHERE token = '#{token}'")
    sql(a, "DELETE FROM lifecycle_retention_probe WHERE token = '#{token}'")
  ensure
    WORKTREES.each { |root| task(root, "dev:stop") if File.exist?(File.join(root, ".services/environment.json")) }
  end

  def test_occupied_explicit_ports_fail_without_starting_services
    root = WORKTREES.first
    task(root, "db:up")
    task(root, "dev:stop")
    config = env(root)
    { "BACKEND_PORT" => "dev:start", "FRONTEND_PORT" => "dev:start", "POSTGRES_PORT" => "db:up" }.each do |key, command|
      TCPServer.open("127.0.0.1", config.fetch(key).to_i) do
        output = task(root, command, success: false)
        assert_includes output, "#{key} #{config.fetch(key)} is occupied"
      end
      daemons = JSON.parse(capture(root, "mise", "daemons", "ls", "--json"))
      assert daemons.all? { |daemon| daemon.fetch("pid").nil? }, daemons.inspect
    end
  end

  def test_readiness_timeout_is_bounded_and_cleans_up_new_processes
    root = WORKTREES.first
    local = File.join(root, "mise.local.toml")
    original = File.read(local)
    File.open(local, "a") do |file|
      file.puts <<~TOML

        [daemons.frontend]
        run = "exec ruby -e 'sleep 120'"
        ready_cmd = { run = "ruby scripts/services.rb ready frontend", timeout = "2s" }
        retry = 0
        proxy = false
        stop_signal = { signal = "SIGTERM", timeout = "2s" }
      TOML
    end
    capture(root, "mise", "trust", "mise.local.toml")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output = task(root, "dev:start", success: false)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 30
    assert_includes output, "exit code 124"
    daemons = JSON.parse(capture(root, "mise", "daemons", "ls", "--json"))
    assert daemons.all? { |daemon| daemon.fetch("pid").nil? }, daemons.inspect
    container = JSON.parse(capture(root, "mise", "exec", "--", "docker", "inspect", "#{env(root).fetch('COMPOSE_PROJECT_NAME')}-postgres-1")).first
    refute container.fetch("State").fetch("Running"), "new PostgreSQL process left running after failed start"
  ensure
    task(root, "dev:stop") if root && File.exist?(File.join(root, ".services/environment.json"))
    if original
      File.write(local, original)
      capture(root, "mise", "trust", "mise.local.toml")
    end
  end
end
