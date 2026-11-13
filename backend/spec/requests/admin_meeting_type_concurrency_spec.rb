require "rails_helper"
require "timeout"
require_relative "../support/openapi_contract"

RSpec.describe "Concurrent meeting-type creation", type: :request do
  self.use_transactional_tests = false

  it "returns one hidden type and one address error when independent PostgreSQL writers race" do
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "concurrent-types-owner"
    ENV["ADMIN_PASSWORD"] = "concurrent-types-password!"
    clients = 2.times.map do
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.post "/api/v1/admin/session",
        params: { username: ENV.fetch("ADMIN_USERNAME"), password: ENV.fetch("ADMIN_PASSWORD") },
        headers: { "X-Calendar-Request" => "1" }, as: :json
      expect(client.response).to have_http_status(:ok)
      client
    end
    ready = Queue.new
    start = Queue.new
    workers = clients.map do |client|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << connection.select_value("SELECT pg_backend_pid()")
          start.pop
          client.post "/api/v1/admin/meeting-types",
            params: { name: "Racing offer", durationMinutes: 20, slug: "concurrent-address" },
            headers: { "X-Calendar-Request" => "1" }, as: :json
          OpenapiContract.validate!(client.request, client.response)
          [ client.response.status, client.response.parsed_body ]
        end
      end
    end
    pids = 2.times.map { ready.pop }
    expect(pids.uniq.size).to eq(2)
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      # An uncommitted index entry lets both requests pass the preliminary
      # uniqueness SELECT, then blocks both INSERTs at the real database seam.
      connection.transaction do
        MeetingType.create!(name: "Uncommitted blocker", duration_minutes: 1, slug: "concurrent-address")
        2.times { start << true }
        Timeout.timeout(10) do
          loop do
            waiting = connection.select_value(
              "SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{pids.join(',')}) AND wait_event = 'transactionid'"
            )
            break if waiting == 2
            sleep 0.01
          end
        end
        raise ActiveRecord::Rollback
      end
    end
    results = workers.map(&:value)
    expect(results.map(&:first).sort).to eq([ 201, 422 ])
    expect(results.find { |status, _| status == 422 }.last.dig("errors", "slug")).to include("has already been taken")
    clients.first.get "/api/v1/admin/meeting-types"
    types = clients.first.response.parsed_body.fetch("meetingTypes")
    expect(types.map { |type| type.fetch("slug") }).to eq([ "concurrent-address" ])
    expect(types.first.fetch("published")).to be(false)
  ensure
    workers&.each(&:join)
    MeetingType.delete_all
    AdminSession.delete_all
    Administrator.delete_all
    AdminLoginLimit.delete_all
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end
end
