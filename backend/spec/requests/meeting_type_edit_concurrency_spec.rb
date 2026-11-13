require "rails_helper"
require "timeout"
require_relative "../support/openapi_contract"

RSpec.describe "Concurrent meeting-type address edits", type: :request do
  self.use_transactional_tests = false

  it "commits one new address and preserves the losing offer when independent updates race" do
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "edit-race-owner"
    ENV["ADMIN_PASSWORD"] = "edit-race-password!"
    types = 2.times.map do |index|
      MeetingType.create!(name: "Original #{index}", duration_minutes: 20, slug: "edit-original-#{index}", published: true)
    end
    headers = { "X-Calendar-Request" => "1" }
    clients = types.map do
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.post "/api/v1/admin/session",
        params: { username: ENV.fetch("ADMIN_USERNAME"), password: ENV.fetch("ADMIN_PASSWORD") }, headers: headers, as: :json
      expect(client.response).to have_http_status(:ok)
      client
    end
    ready = Queue.new
    start = Queue.new
    workers = clients.zip(types).map do |client, type|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << connection.select_value("SELECT pg_backend_pid()")
          start.pop
          client.put "/api/v1/admin/meeting-types/#{type.id}",
            params: { name: "Edited", durationMinutes: 45, slug: "edit-shared-address" }, headers: headers, as: :json
          OpenapiContract.validate!(client.request, client.response)
          [ client.response.status, client.response.parsed_body ]
        end
      end
    end
    pids = 2.times.map { ready.pop }
    expect(pids.uniq.size).to eq(2)
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.transaction do
        MeetingType.create!(name: "Uncommitted blocker", duration_minutes: 1, slug: "edit-shared-address")
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
    expect(results.map(&:first).sort).to eq([ 200, 422 ])
    loser_index = results.index { |status, _| status == 422 }
    expect(results.fetch(loser_index).last.dig("errors", "slug")).to include("has already been taken")
    clients.first.get "/api/v1/admin/meeting-types/#{types.fetch(loser_index).id}"
    expect(clients.first.response.parsed_body).to include("name" => "Original #{loser_index}",
      "slug" => "edit-original-#{loser_index}", "durationMinutes" => 20, "published" => true)
    get "/api/v1/meeting-types/edit-shared-address/availability"
    expect(response).to have_http_status(:ok)
  ensure
    workers&.each(&:join)
    MeetingType.delete_all
    AdminSession.delete_all
    Administrator.delete_all
    AdminLoginLimit.delete_all
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end
end
