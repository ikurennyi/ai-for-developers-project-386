# Reuse the version installed by backend/Gemfile.lock; no root gem project.
gem "minitest", "6.1.0"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "digest"
require "socket"

class ServicesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def invoke(command, env = {})
    Open3.capture3({ "WORKTREE_ID" => nil }.merge(env), RbConfig.ruby,
      File.join(ROOT, "scripts/services.rb"), command, chdir: ROOT)
  end

  def test_missing_configuration_fails_before_starting_services
    out, err, status = invoke("db:up")
    refute status.success?
    assert_includes out + err, "WORKTREE_ID is required"
  end

  def config
    id = "wt-#{Digest::SHA256.hexdigest(File.realpath(ROOT))[0, 20]}"
    { "WORKTREE_ID" => id, "COMPOSE_PROJECT_NAME" => "scaffold-#{id}",
      "BACKEND_PORT" => "43101", "FRONTEND_PORT" => "45101", "POSTGRES_PORT" => "45501",
      "POSTGRES_USER" => "developer", "POSTGRES_PASSWORD" => "local-secret",
      "ADMIN_USERNAME" => "owner", "ADMIN_PASSWORD" => "local-admin-password-24",
      "POSTGRES_DB" => "app_#{id.tr('-', '_')}",
      "DATABASE_URL" => "postgresql://developer:local-secret@127.0.0.1:45501/app_#{id.tr('-', '_')}",
      "TEST_DATABASE_URL" => "postgresql://developer:local-secret@127.0.0.1:45501/test_#{id.tr('-', '_')}" }
  end

  def test_occupied_port_fails_with_explicit_port_and_does_not_move
    TCPServer.open("127.0.0.1", 0) do |listener|
      port = listener.addr[1].to_s
      out, err, status = invoke("dev:validate", config.merge("BACKEND_PORT" => port))
      refute status.success?
      assert_includes out + err, "BACKEND_PORT #{port} is occupied"
    end
  end

  def test_malformed_url_does_not_disclose_credentials
    secret = "do-not-print-this-password"
    out, err, status = invoke("dev:validate", config.merge("DATABASE_URL" => "postgresql://#{secret} with spaces"))
    refute status.success?
    refute_includes out + err, secret
    assert_includes out + err, "DATABASE_URL must be a valid PostgreSQL URL"
  end

  def test_numerically_duplicate_ports_are_rejected
    out, err, status = invoke("dev:validate", config.merge("FRONTEND_PORT" => "043101"))
    refute status.success?
    assert_includes out + err, "All three service ports must differ"
  end

  def test_dev_env_generates_admin_credentials_with_a_fresh_password
    outputs = 2.times.map do
      out, err, status = invoke("dev:env")
      assert status.success?, err
      out
    end

    usernames = outputs.map { |out| out[/^ADMIN_USERNAME = "([^"]+)"$/, 1] }
    passwords = outputs.map { |out| out[/^ADMIN_PASSWORD = "([^"]+)"$/, 1] }

    assert_equal %w[owner owner], usernames
    assert passwords.all? { |password| password&.match?(/\A[a-f0-9]{48}\z/) }
    refute_equal passwords.first, passwords.last
  end

  def test_dev_validate_requires_admin_credentials
    out, err, status = invoke("dev:validate", config.except("ADMIN_PASSWORD"))

    refute status.success?
    assert_includes out + err, "ADMIN_PASSWORD is required"
  end
end
