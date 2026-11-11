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
end
