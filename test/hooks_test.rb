require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "digest"

class HooksTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    @tmp = Dir.mktmpdir("scaffold-hooks-")
    @repo = File.join(@tmp, "repo")
    system("git", "clone", "--quiet", "--shared", ROOT, @repo, exception: true)
    %w[hk.pkl tooling].each do |name|
      FileUtils.cp_r(File.join(ROOT, name), @repo) if File.exist?(File.join(ROOT, name))
    end
    FileUtils.ln_s(File.join(ROOT, "frontend/node_modules"), File.join(@repo, "frontend/node_modules"))
    @env = { "GIT_CONFIG_GLOBAL" => File.join(@tmp, "global"), "GIT_CONFIG_NOSYSTEM" => "1", "MISE_TRUSTED_CONFIG_PATHS" => @repo }
    File.write(@env.fetch("GIT_CONFIG_GLOBAL"), "[user]\n\tname = Hook Test\n\temail = hook@example.test\n")
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def command(*args)
    Open3.capture3(@env, *args, chdir: @repo)
  end

  def snapshot
    files, = command("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    [command("git", "ls-files", "--stage").first,
      files.split("\0").uniq.sort.map { |file| [file, File.file?(File.join(@repo, file)) ? Digest::SHA256.file(File.join(@repo, file)).hexdigest : nil] },
      File.binread(@env.fetch("GIT_CONFIG_GLOBAL"))]
  end

  def test_installed_precommit_checks_staged_changes_without_staging_unstaged_work
    before_global = File.binread(@env.fetch("GIT_CONFIG_GLOBAL"))
    out, err, status = command("hk", "install", "--mise")
    assert status.success?, out + err
    assert_equal before_global, File.binread(@env.fetch("GIT_CONFIG_GLOBAL"))
    file = File.join(@repo, "hook-probe.md")
    File.write(file, "valid\n")
    command("git", "add", "hook-probe.md")
    File.write(file, "valid\nunstaged\n")
    before = snapshot
    out, err, status = command("git", "hook", "run", "pre-commit")
    assert status.success?, out + err
    assert_equal before, snapshot
    File.write(file, "invalid trailing space \n")
    command("git", "add", "hook-probe.md")
    before = snapshot
    out, err, status = command("git", "hook", "run", "pre-commit")
    refute status.success?, out + err
    assert_equal before, snapshot
  end

  def test_commit_message_hook_accepts_conventional_and_rejects_invalid_without_mutation
    out, err, status = command("hk", "install", "--mise")
    assert status.success?, out + err
    message = File.join(@tmp, "message")
    File.write(message, "ci: verify hooks\n")
    before = snapshot
    out, err, status = command("git", "hook", "run", "commit-msg", "--", message)
    assert status.success?, out + err
    assert_equal before, snapshot
    File.write(message, "not conventional\n")
    before = File.binread(message)
    state = snapshot
    out, err, status = command("git", "hook", "run", "commit-msg", "--", message)
    refute status.success?, out + err
    assert_equal before, File.binread(message)
    assert_equal state, snapshot
  end

  def test_frontend_and_backend_fast_gates_reject_real_violations_without_mutation
    frontend = File.join(@repo, "frontend/src/hook-probe.ts")
    backend = File.join(@repo, "backend/app/controllers/application_controller.rb")
    File.write(frontend, "export const hookProbe = true\n")
    File.write(backend, "# Hook probe.\n" + File.read(backend))
    command("git", "add", "frontend/src/hook-probe.ts", "backend/app/controllers/application_controller.rb")
    before = snapshot
    out, err, status = command("hk", "run", "pre-commit")
    assert status.success?, out + err
    assert_equal before, snapshot
    [
      [frontend, "export const hookProbe={a:1};\n", "frontend-format"],
      [frontend, "// @ts-ignore\nexport const hookProbe = true\n", "frontend-lint"],
      [backend, "class ApplicationController < ActionController::API\n  (\nend\n", "backend-lint"]
    ].each do |path, violation, gate|
      original = File.binread(path)
      File.write(path, violation)
      # Leave violations unstaged too: no stashing/fixing/staging is allowed.
      before = snapshot
      out, err, status = command("hk", "run", "pre-commit")
      refute status.success?, "#{gate}: #{out}#{err}"
      assert_includes out + err, gate
      assert_equal before, snapshot
      File.binwrite(path, original)
    end
  end
end
