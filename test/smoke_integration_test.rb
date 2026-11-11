# Run with the pinned Ruby; intentionally exercises real Docker, Rails and Chromium.
require "json"
require "open3"
require "socket"

ROOT = File.expand_path("..", __dir__)

def assert(condition, message)
  raise message unless condition
end

def run_probe(*args)
  output, status = Open3.capture2e("ruby", "scripts/smoke.rb", *args, chdir: ROOT)
  puts output
  event = output.lines.find { |line| line.start_with?("SMOKE_RESOURCES ") }
  assert(event, "missing resource evidence")
  resources = JSON.parse(event.delete_prefix("SMOKE_RESOURCES "))
  [output, status, resources]
end

def assert_clean(resources)
  _, status = Open3.capture2e("docker", "inspect", resources.fetch("container"))
  assert(!status.success?, "temporary PostgreSQL survived")
  resources.fetch("pids").each do |pid|
    begin
      Process.kill(0, pid)
      raise "temporary process #{pid} survived"
    rescue Errno::ESRCH
      # Expected: only this run's children were stopped.
    end
    begin
      Process.kill(0, -pid)
      raise "temporary process group #{pid} survived"
    rescue Errno::ESRCH
      # Includes subprocesses such as Chromium and its driver.
    end
  end
  assert(!File.exist?(resources.fetch("directory")), "temporary directory survived")
end

# An unrelated listener must survive both successful and failed smoke runs.
sentinel = TCPServer.new("127.0.0.1", 0)
sentinel_port = sentinel.addr[1]
sentinel_pid = fork do
  loop do
    client = sentinel.accept
    client.write("untouched")
    client.close
  end
end
sentinel.close
begin
  runs = 2.times.map { Thread.new { run_probe } }.map(&:value)
  runs.each do |output, status, resources|
    assert(status.success?, output)
    assert(output.include?("PostgreSQL connection verified"), "missing independent DB probe")
    assert_clean(resources)
  end
  assert(runs.map { |run| run[2].fetch("database") }.uniq.size == 2, "shared database")
  assert(runs.map { |run| run[2].fetch("container") }.uniq.size == 2, "shared container")
  output, status, resources = run_probe("--fail-after-ready")
  assert(!status.success? && output.include?("intentional failure"), "failure was swallowed")
  assert_clean(resources)
  output, status, resources = run_probe("--probe-browser-failure")
  assert(!status.success? && output.include?("API unavailable"), "Chromium failed to detect missing Rails")
  assert_clean(resources)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  output, status, resources = run_probe("--probe-readiness-timeout")
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  assert(!status.success? && output.include?("readiness timed out"), "timeout was swallowed")
  assert(elapsed < 40, "short readiness probe exceeded its bounded startup/cleanup budget")
  assert_clean(resources)
  Process.kill(0, sentinel_pid)
  TCPSocket.open("127.0.0.1", sentinel_port) do |client|
    assert(client.read == "untouched", "unrelated listener stopped")
  end
  puts "Smoke isolation, parallelism, success/failure/timeout cleanup verified"
ensure
  Process.kill("TERM", sentinel_pid)
  Process.wait(sentinel_pid)
end
