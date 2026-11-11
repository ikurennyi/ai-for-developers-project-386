require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "json"

class CommitRangesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ZERO = "0" * 40

  def setup
    @tmp = Dir.mktmpdir("commit-ranges-")
    system("git", "init", "--quiet", @tmp, exception: true)
    FileUtils.cp_r(File.join(ROOT, "tooling"), @tmp)
    @env = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_AUTHOR_NAME" => "Test", "GIT_AUTHOR_EMAIL" => "test@example.test",
      "GIT_COMMITTER_NAME" => "Test", "GIT_COMMITTER_EMAIL" => "test@example.test" }
    @baseline = commit("historical scaffold, intentionally invalid")
    File.write(File.join(@tmp, "tooling/commitlint-baseline"), @baseline + "\n")
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def git(*args)
    out, err, status = Open3.capture3(@env, "git", *args, chdir: @tmp)
    assert status.success?, out + err
    out.strip
  end

  def commit(message)
    git("-c", "core.hooksPath=/dev/null", "commit", "--quiet", "--allow-empty", "-m", message)
    git("rev-parse", "HEAD")
  end

  def check(name, event)
    path = File.join(@tmp, "event.json")
    File.write(path, JSON.generate(event))
    Open3.capture3(@env.merge("GITHUB_EVENT_NAME" => name, "GITHUB_EVENT_PATH" => path),
      "node", "tooling/check-commits.mjs", chdir: @tmp)
  end

  def test_push_checks_only_new_commits_and_rejects_bad_message
    prior = commit("old invalid message outside event range")
    head = commit("ci: add checks")
    out, err, status = check("push", {before: prior, after: head})
    assert status.success?, out + err
    assert_includes out, head
    refute_includes out, prior
    bad = commit("invalid new message")
    out, err, status = check("push", {before: head, after: bad})
    refute status.success?, out + err
  end

  def test_pr_uses_head_and_base_not_synthetic_merge
    head = commit("ci: branch commit")
    git("checkout", "--quiet", "--detach", @baseline)
    base = commit("unrelated invalid base commit")
    out, err, status = check("pull_request", {pull_request: {base: {sha: base}, head: {sha: head}}})
    assert status.success?, out + err
    assert_includes out, head
    refute_includes out, base
  end

  def test_new_branch_and_initial_default_push_exclude_historical_scaffold
    head = commit("ci: publish scaffold checks")
    %w[main feature].each do |branch|
      out, err, status = check("push", {before: ZERO, after: head, ref: "refs/heads/#{branch}", repository: {default_branch: "main"}})
      assert status.success?, out + err
      assert_includes out, head
      refute_includes out, @baseline
    end
  end

  def test_new_branch_excludes_already_published_default_branch_commits
    published = commit("already published invalid message")
    git("update-ref", "refs/remotes/origin/main", published)
    head = commit("ci: new feature branch")
    out, err, status = check("push", {before: ZERO, after: head, ref: "refs/heads/feature", repository: {default_branch: "main"}})
    assert status.success?, out + err
    assert_includes out, head
    refute_includes out, published
  end

  def test_deletion_is_empty_and_missing_range_fails_closed
    out, err, status = check("push", {before: @baseline, after: ZERO})
    assert status.success?, out + err
    out, err, status = check("push", {before: "f" * 40, after: @baseline})
    refute status.success?, out + err
  end

  def test_force_push_checks_new_head_without_requiring_old_head_ancestry
    before = commit("old rewritten invalid commit")
    git("checkout", "--quiet", "--detach", @baseline)
    head = commit("ci: rewritten branch")
    out, err, status = check("push", {before: before, after: head})
    assert status.success?, out + err
    assert_includes out, head
    refute_includes out, before
  end
end
