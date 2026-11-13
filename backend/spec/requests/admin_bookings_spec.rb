require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Administrator booking history", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "history-owner"
    ENV["ADMIN_PASSWORD"] = "history-test-password!"
    example.run
  ensure
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  def login
    post "/api/v1/admin/session", params: { username: ENV.fetch("ADMIN_USERNAME"), password: ENV.fetch("ADMIN_PASSWORD") },
      headers: { "X-Calendar-Request" => "1" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  def saved_booking(start, finish, name)
    type = MeetingType.find_or_create_by!(slug: "history") { |record| record.assign_attributes(name: "Current", duration_minutes: 15) }
    occupancy = Occupancy.create!(starts_at: start, ends_at: finish)
    Booking.create!(meeting_type: type, occupancy: occupancy, starts_at: start, ends_at: finish,
      meeting_name: name, meeting_description: "Saved description", duration_minutes: 15,
      guest_name: "<b>Guest</b>", guest_email: "history@example.com", notes: "<script>plain text</script>\n" + "é" * 1900)
  end

  it "protects guest details and classifies exact completion, ongoing and distant bookings by server time" do
    travel_to Time.utc(2026, 11, 13, 12) do
      finished = saved_booking(2.hours.ago, Time.current, "Exactly completed")
      ongoing = saved_booking(Time.current, 15.minutes.from_now, "Ongoing snapshot")
      distant = saved_booking(60.days.from_now, 60.days.from_now + 15.minutes, "Distant snapshot")
      get "/api/v1/admin/bookings"
      expect(response).to have_http_status(:unauthorized)
      OpenapiContract.validate!(request, response)
      login
      get "/api/v1/admin/bookings"
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.parsed_body.fetch("bookings").map { |booking| booking["id"] }).to eq([ ongoing.id, distant.id ])
      expect(response.parsed_body.fetch("bookings").first).to include("meetingName" => "Ongoing snapshot",
        "meetingDescription" => "Saved description", "guestName" => "<b>Guest</b>",
        "guestEmail" => "history@example.com", "notes" => ongoing.notes, "timeZone" => "Europe/Berlin")
      OpenapiContract.validate!(request, response)
      get "/api/v1/admin/bookings", params: { period: "past" }
      expect(response.parsed_body.fetch("bookings").map { |booking| booking["id"] }).to eq([ finished.id ])
      OpenapiContract.validate!(request, response)
      travel 5.minutes
      get "/api/v1/admin/bookings"
      expect(response.parsed_body.fetch("bookings").map { |booking| booking["id"] }).to eq([ ongoing.id, distant.id ])
      OpenapiContract.validate!(request, response)
    end
  end

  it "paginates all retained history in reverse start order and validates query parameters" do
    travel_to Time.utc(2026, 11, 13, 12) do
      records = 23.times.map { |index| saved_booking((index + 1).days.ago, (index + 1).days.ago + 15.minutes, "History #{index}") }
      login
      [ [ 1, records.first(20) ], [ 2, records.last(3) ], [ 3, [] ] ].each do |page, expected|
        get "/api/v1/admin/bookings", params: { period: "past", page: page }
        expect(response.parsed_body).to include("page" => page, "pageSize" => 20, "total" => 23)
        expect(response.parsed_body.fetch("bookings").map { |booking| booking["id"] }).to eq(expected.map(&:id))
        OpenapiContract.validate!(request, response)
      end
      get "/api/v1/admin/bookings"
      expect(response.parsed_body).to include("bookings" => [], "total" => 0)
      OpenapiContract.validate!(request, response)
      [ { period: "other" }, { page: "0" }, { page: "-1" }, { page: "1.5" }, { page: "abc" } ].each do |query|
        get "/api/v1/admin/bookings", params: query
        expect(response).to have_http_status(:bad_request)
        OpenapiContract.validate!(request, response, validate_request: false)
      end
    end
  end
end
