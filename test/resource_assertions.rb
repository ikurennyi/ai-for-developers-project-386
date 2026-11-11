require "open3"

# Shared evidence contract for both public test gates and aggregate probes.
def assert_clean(resources, service_url: nil)
  if resources.fetch("container")
    _, status = Open3.capture2e("docker", "inspect", resources.fetch("container"))
    assert(!status.success?, "temporary PostgreSQL survived")
  else
    assert(service_url, "missing service connection for cleanup assertion")
    output, status = Open3.capture2e({ "SMOKE_SERVICE_URL" => service_url }, "bundle", "exec", "ruby",
      File.join(ROOT, "scripts/test_database.rb"), "assert-absent", resources.fetch("database"), chdir: File.join(ROOT, "backend"))
    assert(status.success?, output)
  end
  resources.fetch("pids").each do |pid|
    [pid, -pid].each do |target|
      begin
        Process.kill(0, target)
        raise "temporary process/group #{target} survived"
      rescue Errno::ESRCH
        # Includes browser/driver descendants, not unrelated processes.
      end
    end
  end
  assert(!File.exist?(resources.fetch("directory")), "temporary directory survived")
end
