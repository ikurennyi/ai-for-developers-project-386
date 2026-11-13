require "minitest/autorun"
require "json"
require "yaml"

class ReleaseConfigTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_release_automation_is_main_only_and_requires_a_separate_token
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/release-please.yml"))
    assert_equal({ "push" => { "branches" => ["main"] } }, workflow.fetch("on"))
    assert_equal({}, workflow.fetch("permissions"))
    assert_equal false, workflow.fetch("concurrency").fetch("cancel-in-progress")
    assert_equal ["release"], workflow.fetch("jobs").keys
    steps = workflow.fetch("jobs").fetch("release").fetch("steps")
    assert_equal 2, steps.length
    preflight, release = steps
    assert_equal "${{ secrets.RELEASE_PLEASE_TOKEN }}", preflight.fetch("env").fetch("RELEASE_PLEASE_TOKEN")
    assert_includes preflight.fetch("run"), 'test -n "$RELEASE_PLEASE_TOKEN"'
    assert_match(/\Agoogleapis\/release-please-action@[a-f0-9]{40}\z/, release.fetch("uses"))
    assert_equal({
      "token" => "${{ secrets.RELEASE_PLEASE_TOKEN }}",
      "target-branch" => "main",
      "config-file" => "release-please-config.json",
      "manifest-file" => ".release-please-manifest.json"
    }, release.fetch("with"))
    checks = YAML.safe_load_file(File.join(ROOT, ".github/workflows/application-check.yml"))
    assert checks.fetch("on").key?("pull_request")
    assert_nil checks.fetch("on").fetch("pull_request")
  end

  def test_single_application_release_does_not_manage_dependency_projects
    config = JSON.parse(File.read(File.join(ROOT, "release-please-config.json")))
    assert_equal ["."], config.fetch("packages").keys
    package = config.fetch("packages").fetch(".")
    assert_equal "simple", package.fetch("release-type")
    assert_equal "0.1.0", package.fetch("initial-version")
    assert_equal "version.txt", package.fetch("version-file")
    assert_equal "CHANGELOG.md", package.fetch("changelog-path")
    assert_equal "default", package.fetch("versioning")
    assert_equal true, package.fetch("bump-minor-pre-major")
    assert_equal false, package.fetch("bump-patch-for-minor-pre-major")
    assert_equal false, package.fetch("include-component-in-tag")
    assert_equal true, package.fetch("include-v-in-tag")
    refute config.key?("plugins")
    refute package.key?("extra-files")
    refute package.key?("release-as")
    manifest = JSON.parse(File.read(File.join(ROOT, ".release-please-manifest.json")))
    version = File.read(File.join(ROOT, "version.txt")).strip
    assert_match(/\A\d+\.\d+\.\d+\z/, version)
    assert_equal manifest.fetch(".", package.fetch("initial-version")), version
  end
end
