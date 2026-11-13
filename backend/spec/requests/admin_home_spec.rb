require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Administrator Home", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "home-owner"
    ENV["ADMIN_PASSWORD"] = "home-only-test-password!"
    example.run
  ensure
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  def login
    post "/api/v1/admin/session", params: { username: "home-owner", password: ENV.fetch("ADMIN_PASSWORD") },
      headers: { "X-Calendar-Request" => "1" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  def confirm_at(start, now:)
    travel_to Time.iso8601(now) do
      post "/api/v1/meeting-types/home-meeting/bookings", params: {
        startsAt: start, meetingType: { name: "Saved meeting", description: "Original details", durationMinutes: 30 },
        guestName: "<b>Home guest</b>", guestEmail: "home@example.com", notes: "<script>plain text</script>\n" + "x" * 1900
      }, as: :json
      expect(response).to have_http_status(:created)
      OpenapiContract.validate!(request, response)
      response.parsed_body
    end
  end

  it "protects guest data and returns an explicit empty result to the administrator" do
    get "/api/v1/admin/home"
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("message" => "Authentication required")
    OpenapiContract.validate!(request, response)
    expect(response.headers["Cache-Control"]).to include("no-store")
    login
    get "/api/v1/admin/home"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("days" => [], "timeZone" => "Europe/Berlin")
    OpenapiContract.validate!(request, response)
  end

  it "groups all saved unfinished meetings by Berlin date, including ongoing and dates beyond the creation window" do
    type = MeetingType.create!(name: "Saved meeting", description: "Original details",
      duration_minutes: 30, slug: "home-meeting", published: true)
    completed = confirm_at("2026-11-13T08:00:00Z", now: "2026-11-02T08:00:00Z")
    ongoing = confirm_at("2026-11-13T08:30:00Z", now: "2026-11-02T08:00:00Z")
    later = confirm_at("2026-11-13T09:00:00Z", now: "2026-11-02T08:00:00Z")
    next_day = confirm_at("2026-11-16T08:00:00Z", now: "2026-11-03T08:00:00Z")
    distant = confirm_at("2026-11-30T08:00:00Z", now: "2026-11-20T08:00:00Z")
    travel_to Time.iso8601("2026-11-13T08:45:00Z") do
      login
      put "/api/v1/admin/meeting-types/#{type.id}", params: {
        name: "Changed meeting", description: "Changed", durationMinutes: 45, slug: "changed-home"
      }, headers: { "X-Calendar-Request" => "1" }, as: :json
      expect(response).to have_http_status(:ok)
      put "/api/v1/admin/meeting-types/#{type.id}/publication", params: { published: false },
        headers: { "X-Calendar-Request" => "1" }, as: :json
      expect(response).to have_http_status(:ok)
      get "/api/v1/admin/home"
      expect(response).to have_http_status(:ok)
      OpenapiContract.validate!(request, response)
      expect(response.parsed_body).to eq("timeZone" => "Europe/Berlin", "days" => [
        { "date" => "2026-11-13", "bookings" => [ ongoing, later ] },
        { "date" => "2026-11-16", "bookings" => [ next_day ] },
        { "date" => "2026-11-30", "bookings" => [ distant ] }
      ])
      expect(response.body).not_to include(completed["id"])
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
    travel_to Time.iso8601("2026-11-13T09:00:00Z") do
      get "/api/v1/admin/home"
      OpenapiContract.validate!(request, response)
      expect(response.parsed_body["days"].first["bookings"]).to eq([ later ])
    end
    travel_to Time.iso8601("2026-11-14T08:45:00Z") do
      get "/api/v1/admin/home"
      expect(response).to have_http_status(:unauthorized)
      OpenapiContract.validate!(request, response)
      expect(response.body).not_to include("home@example.com", "Home guest")
    end
  end
end
