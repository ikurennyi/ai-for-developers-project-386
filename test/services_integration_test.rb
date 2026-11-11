# Opt-in real service probes. Supply two prepared, dedicated worktree paths.
# This starts/stops their dev services and writes a retention-probe table.
require "minitest/autorun"
require "open3"
require "json"
require "net/http"
require "securerandom"

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

  def test_two_worktrees_are_independent_and_stop_preserves_data
    a, b = WORKTREES
    WORKTREES.each { |root| task(root, "dev:start") }
    a_env, b_env = WORKTREES.map { |root| env(root) }
    %w[WORKTREE_ID COMPOSE_PROJECT_NAME POSTGRES_DB BACKEND_PORT FRONTEND_PORT POSTGRES_PORT].each do |key|
      refute_equal a_env.fetch(key), b_env.fetch(key), "shared #{key}"
    end
    pids = WORKTREES.map { |root| File.read(File.join(root, ".services/rails.pid")).strip }
    refute_equal(*pids)
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
end
