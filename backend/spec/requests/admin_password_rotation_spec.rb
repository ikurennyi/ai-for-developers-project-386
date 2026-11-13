require "rails_helper"
require "open3"
require_relative "../support/openapi_contract"

RSpec.describe "Administrator operational security", type: :request do
  # The command is a separate Rails process connected to the same disposable DB.
  self.use_transactional_tests = false

  around do |example|
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "command-owner"
    ENV["ADMIN_PASSWORD"] = "initial-command-password!"
    AdminSession.delete_all
    Administrator.delete_all
    AdminLoginLimit.delete_all
    example.run
  ensure
    AdminSession.delete_all
    Administrator.delete_all
    AdminLoginLimit.delete_all
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  it "revokes every session, rejects the old password, and persists the new password across processes" do
    clients = 2.times.map do
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.post "/api/v1/admin/session", params: { username: "command-owner", password: ENV.fetch("ADMIN_PASSWORD") },
        headers: { "X-Calendar-Request" => "1" }, as: :json
      expect(client.response).to have_http_status(:ok)
      client
    end
    output, status = Open3.capture2e({ "ADMIN_NEW_PASSWORD" => "rotated-command-password!" },
      "bundle", "exec", "rails", "admin:change_password", chdir: Rails.root)
    expect(status.success?).to be(true), output
    expect(output).to include("all sessions revoked")
    expect(output).not_to include("rotated-command-password!")
    clients.each do |client|
      client.get "/api/v1/admin/session"
      expect(client.response).to have_http_status(:unauthorized)
      OpenapiContract.validate!(client.request, client.response)
    end
    post "/api/v1/admin/session", params: { username: "command-owner", password: ENV.fetch("ADMIN_PASSWORD") },
      headers: { "X-Calendar-Request" => "1" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/admin/session", params: { username: "command-owner", password: "rotated-command-password!" },
      headers: { "X-Calendar-Request" => "1" }, as: :json
    expect(response).to have_http_status(:ok)
    OpenapiContract.validate!(request, response)
  end

  it "enforces the same ten-attempt limit under concurrent requests on independent connections" do
    ready = Queue.new
    start = Queue.new
    workers = 3.times.map do
      Thread.new do
        ready << true
        start.pop
        ActiveRecord::Base.connection_pool.with_connection do
          4.times.map do
            client = ActionDispatch::Integration::Session.new(Rails.application)
            client.post "/api/v1/admin/session",
              params: { username: "command-owner", password: ENV.fetch("ADMIN_PASSWORD") },
              headers: { "X-Calendar-Request" => "1" }, as: :json
            OpenapiContract.validate!(client.request, client.response)
            client.response.status
          end
        end
      end
    end
    3.times { ready.pop }
    3.times { start << true }
    statuses = workers.flat_map(&:value)
    expect(statuses.count(200)).to eq(10)
    expect(statuses.count(429)).to eq(2)
  ensure
    workers&.each(&:join)
  end
end
