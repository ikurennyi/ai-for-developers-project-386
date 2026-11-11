# Simulate the Actions PostgreSQL service locally; exercise the real public gates.
require "open3"
require "json"
require "securerandom"
require_relative "../scripts/smoke"
require_relative "resource_assertions"
require_relative "source_snapshot"

ROOT = File.expand_path("..", __dir__)

def assert(condition, message)
  raise message unless condition
end

def capture(*command, env: {})
  output, status = Open3.capture2e(env, *command, chdir: ROOT)
  assert(status.success?, output)
  output.strip
end

service = "ci-service-probe-#{SecureRandom.hex(10)}"
password = SecureRandom.hex(24)
begin
  capture("docker", "run", "-d", "--rm", "--name", service, "--publish", "127.0.0.1::5432",
    "--tmpfs", "/var/lib/postgresql", "-e", "POSTGRES_USER=ci", "-e", "POSTGRES_PASSWORD=#{password}",
    "-e", "POSTGRES_DB=scaffold_ci", Smoke::IMAGE)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
  loop do
    _, status = Open3.capture2e("docker", "exec", service, "pg_isready", "-h", "127.0.0.1", "-U", "ci", "-d", "scaffold_ci")
    break if status.success?
    raise "fixture readiness timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.2
  end
  port = capture("docker", "port", service, "5432/tcp").split(":").last
  url = "postgresql://ci:#{password}@127.0.0.1:#{port}/scaffold_ci"
  env = { "CI" => "true", "DATABASE_URL" => url }
  # Ambiguous URLs must fail before any application/test preparation.
  output, status = Open3.capture2e(env.merge("DATABASE_URL" => "#{url}?dbname=scaffold_ci"), "mise", "run", "backend:test", chdir: ROOT)
  assert(!status.success? && output.include?("without query or fragment"), "ambiguous service URL was not rejected safely")
  assert(!output.include?(password), "service credential leaked")
  def probe(env, *command, failure: nil)
    before = snapshot
    output, status = Open3.capture2e(env, *command, chdir: ROOT)
    puts output
    assert(snapshot == before, "CI gate changed sources or index")
    assert(failure ? !status.success? && output.include?(failure) : status.success?, output)
    resources = output.lines.grep(/^SMOKE_RESOURCES /).map do |line|
      resource = JSON.parse(line.delete_prefix("SMOKE_RESOURCES "))
      assert(resource.fetch("container").nil?, "CI gate bypassed the service with a new container")
      assert_clean(resource, service_url: env.fetch("DATABASE_URL"))
      resource
    end
    assert(!resources.empty?, "missing cleanup evidence")
    assert(output.include?("PostgreSQL connection verified"), "missing SQL probe")
    resources
  end

  # Both public gates run concurrently on one borrowed service, without sharing DBs.
  resources = %w[backend:test smoke].map do |task|
    Thread.new { probe(env, "mise", "run", task) }
  end.flat_map(&:value)
  %w[--fail-after-ready --probe-browser-failure --probe-readiness-timeout].each do |mode|
    diagnostic = { "--fail-after-ready" => "intentional failure", "--probe-browser-failure" => "API unavailable",
      "--probe-readiness-timeout" => "readiness timed out" }.fetch(mode)
    resources.concat(probe(env, "ruby", "scripts/smoke.rb", mode, failure: diagnostic))
  end
  resources.concat(probe(env, "mise", "run", "check"))
  resources.concat(probe(env, "mise", "run", "check:test")) if ARGV.include?("--failure-probes")
  assert(resources.map { |r| r.fetch("database") }.uniq.size == resources.size, "shared per-run database")
  databases = capture("docker", "exec", service, "psql", "-U", "ci", "-d", "scaffold_ci", "-At", "-c",
    "SELECT datname FROM pg_database WHERE datname LIKE 'smoke_%'")
  assert(databases.empty?, "service retained temporary databases")
  assert(capture("docker", "exec", service, "psql", "-U", "ci", "-d", "scaffold_ci", "-At", "-c", "SELECT 1") == "1", "borrowed service was damaged")
  puts "CI service reuse, parallelism, aggregate and failure cleanup verified"
ensure
  system("docker", "rm", "--force", "--volumes", service, out: File::NULL)
end
