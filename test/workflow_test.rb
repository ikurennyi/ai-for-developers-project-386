require "minitest/autorun"
require "yaml"

class WorkflowTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_workflow_security_and_environment_contract
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/application-check.yml"))
    assert_equal %w[pull_request push], workflow.fetch("on").keys.sort
    assert_equal({ "contents" => "read" }, workflow.fetch("permissions"))
    job = workflow.fetch("jobs").fetch("check")
    image = job.fetch("services").fetch("postgres").fetch("image")
    assert_equal YAML.safe_load_file(File.join(ROOT, "compose.yml")).fetch("services").fetch("postgres").fetch("image"), image
    steps = job.fetch("steps")
    steps.select { |step| step.key?("uses") }.each do |step|
      assert_match(/@[a-f0-9]{40}\z/, step.fetch("uses"))
    end
    checkout = steps.find { |step| step.fetch("uses", "").start_with?("actions/checkout@") }
    assert_equal 0, checkout.fetch("with").fetch("fetch-depth")
    assert_equal false, checkout.fetch("with").fetch("persist-credentials")
    mise = steps.find { |step| step.fetch("uses", "").start_with?("jdx/mise-action@") }
    fetch_before = steps.find { |step| step["name"] == "Fetch previous push commit when missing" }
    commit_check = steps.find { |step| step.fetch("run", "").include?("mise run commits:check") }
    assert_equal "github.event_name == 'push'", fetch_before.fetch("if")
    assert_equal "node tooling/fetch-push-before.mjs", fetch_before.fetch("run")
    assert_operator steps.index(mise), :<, steps.index(fetch_before)
    assert_operator steps.index(fetch_before), :<, steps.index(commit_check)
    runs = steps.filter_map { |step| step["run"] }.join("\n")
    assert_includes runs, "mise run check"
    assert_includes runs, "install --with-deps chromium"
    assert_includes runs, "mise run commits:check"
    assert_includes runs, "mise run ci:validate"
    refute_includes runs, "${{"
    aggregate = steps.find { |step| step["run"] == "mise run check" }
    assert_equal "true", aggregate.fetch("env").fetch("CI")
    assert_equal "postgresql://ci:ci-ephemeral@127.0.0.1:${{ job.services.postgres.ports['5432'] }}/scaffold_ci", aggregate.fetch("env").fetch("DATABASE_URL")
  end

  def test_compose_waits_for_final_tcp_server
    health = YAML.safe_load_file(File.join(ROOT, "compose.yml")).fetch("services").fetch("postgres").fetch("healthcheck")
    assert_includes health.fetch("test").last, "pg_isready -h 127.0.0.1"
  end
end
