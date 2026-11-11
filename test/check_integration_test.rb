# Real failure probes through the public aggregate command; run in a dedicated checkout.
require "open3"
require "digest"
require "json"

ROOT = File.expand_path("..", __dir__)

def assert(condition, message)
  raise message unless condition
end

def snapshot
  paths, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", chdir: ROOT)
  assert(status.success?, "cannot enumerate source files")
  files = paths.split("\0").to_h { |path| [path, Digest::SHA256.file(File.join(ROOT, path)).hexdigest] }
  index, status = Open3.capture2("git", "ls-files", "--stage", "-z", chdir: ROOT)
  assert(status.success?, "cannot inspect index")
  [files, index]
end

RESOURCES = []

def run_check
  before = snapshot
  output, status = Open3.capture2e("mise", "run", "check", chdir: ROOT)
  puts output
  assert(snapshot == before, "check changed sources or the index")
  output.lines.grep(/^SMOKE_RESOURCES /).each do |line|
    resource = JSON.parse(line.delete_prefix("SMOKE_RESOURCES "))
    RESOURCES << resource
    _, inspect_status = Open3.capture2e("docker", "inspect", resource.fetch("container"))
    assert(!inspect_status.success?, "temporary database survived")
    assert(!File.exist?(resource.fetch("directory")), "runtime directory survived")
    resource.fetch("pids").each do |pid|
      [pid, -pid].each do |target|
        begin
          Process.kill(0, target)
          raise "temporary process/group #{target} survived"
        rescue Errno::ESRCH
          # The invocation must remove only its own children.
        end
      end
    end
  end
  [output, status]
end

def probe(path, contents, gate, diagnostic)
  absolute = File.join(ROOT, path)
  original = File.binread(absolute) if File.exist?(absolute)
  File.binwrite(absolute, contents)
  output, status = run_check
  assert(!status.success?, "#{gate} failure was swallowed")
  assert(output.include?("CHECK_GATE #{gate}"), "#{gate} never reached")
  assert(output.include?(diagnostic), "#{gate} missing real diagnostic: #{diagnostic}")
  assert(File.binread(absolute) == contents.b, "check rewrote the probe")
  puts "PROBE_PASS #{gate}: #{diagnostic} (exit #{status.exitstatus})"
ensure
  original ? File.binwrite(absolute, original) : File.delete(absolute)
end

probe("contracts/main.tsp", File.read(File.join(ROOT, "contracts/main.tsp")) + "\nmodel Broken { value: MissingType; }\n", "contracts", "Unknown identifier MissingType")
probe("contracts/main.tsp", File.read(File.join(ROOT, "contracts/main.tsp")).sub('@operationId("getHealth")', '@operationId("get Health")'), "contracts", "vacuum failed")
probe("contracts/generated/openapi.json", File.read(File.join(ROOT, "contracts/generated/openapi.json")) + "\n", "contracts", "OpenAPI drift")
probe("frontend/src/generated/sdk/sdk.gen.ts", File.read(File.join(ROOT, "frontend/src/generated/sdk/sdk.gen.ts")) + "\n", "contracts", "SDK drift")
probe("contracts/test/sdk-consumer.ts", File.read(File.join(ROOT, "contracts/test/sdk-consumer.ts")) + "\nconst checkProbe: string = 123;\n", "contracts", "not assignable to type 'string'")
probe("backend/check_probe.rb", "def (\n", "backend:lint", "Lint/Syntax")
probe("frontend/src/check-probe.ts", "// @ts-ignore\nexport const checkProbe = 1\n", "frontend:lint", "ban-ts-comment")
probe("frontend/check-probe.json", '{"probe":true}', "frontend:format", "Code style issues")
probe("frontend/src/check-probe.ts", "export const checkProbe: string = 123\n", "frontend:typecheck", "not assignable to type 'string'")
probe("backend/spec/check_probe_spec.rb", "require \"rails_helper\"\n\nRSpec.describe \"Aggregate failure\" do\n  it \"propagates failure\" do\n    expect(1).to eq(2)\n  end\nend\n", "backend:test", "1 failure")
probe("frontend/src/__tests__/App.spec.ts", File.read(File.join(ROOT, "frontend/src/__tests__/App.spec.ts")).sub("toBe('Calendar — technical scaffold')", "toBe('Incorrect heading')"), "frontend:test", "Incorrect heading")
probe("frontend/browser/smoke.spec.ts", File.read(File.join(ROOT, "frontend/browser/smoke.spec.ts")).sub("toBe('API healthy: ok')", "toBe('Incorrect API status')"), "smoke", "Incorrect API status")
probe("frontend/index.html", File.read(File.join(ROOT, "frontend/index.html")).sub('/src/main.ts', '/src/missing.ts'), "frontend:build", "missing.ts")

2.times do
  output, status = run_check
  assert(status.success? && output.include?("All mandatory checks passed"), "clean repeated check failed")
end
assert(RESOURCES.map { |resource| resource.fetch("container") }.uniq.size == RESOURCES.size, "shared container identity")
assert(RESOURCES.map { |resource| resource.fetch("database") }.uniq.size == RESOURCES.size, "shared database identity")
puts "All 13 failure probes and two clean repeated checks passed; resources unique and removed"
