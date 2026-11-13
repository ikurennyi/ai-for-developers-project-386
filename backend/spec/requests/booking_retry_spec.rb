require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Private booking retry", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:type) do
    MeetingType.create!(name: "Retry discussion", description: "", duration_minutes: 20,
      slug: "retry-discussion", published: true)
  end
  let(:payload) do
    { attemptToken: SecureRandom.hex(32), startsAt: "2026-11-13T09:00:00Z",
      meetingType: { name: type.name, description: "", durationMinutes: 20 },
      guestName: "Private Guest", guestEmail: "private@example.com", notes: "Private notes" }
  end

  before { travel_to Time.iso8601("2026-11-13T07:00:00Z") }
  after { travel_back }

  it "returns the original committed booking rather than conflicting with itself, even after offer changes" do
    post "/api/v1/meeting-types/retry-discussion/bookings", params: payload, as: :json
    expect(response).to have_http_status(:created)
    original = JSON.parse(response.body)
    type.update!(published: false, slug: "new-address", name: "New terms")
    travel_to Time.iso8601("2026-11-27T09:00:00Z")
    2.times do
      post "/api/v1/meeting-types/retry-discussion/bookings", params: payload, as: :json
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to eq(original)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      OpenapiContract.validate!(request, response)
    end
    expect(Booking.count).to eq(1)
    expect(Occupancy.count).to eq(1)
  end

  it "does not recover by matching contact details or a guessed capability" do
    post "/api/v1/meeting-types/retry-discussion/bookings", params: payload, as: :json
    original = JSON.parse(response.body)
    [ payload.except(:attemptToken), payload.merge(attemptToken: SecureRandom.hex(32)) ].each do |other|
      post "/api/v1/meeting-types/retry-discussion/bookings", params: other, as: :json
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to include("code" => "occupied")
      expect(response.body).not_to include(original.fetch("id"), "private@example.com", "Private notes")
      OpenapiContract.validate!(request, response)
    end
    get "/api/v1/meeting-types/retry-discussion/bookings/#{original.fetch('id')}"
    expect(response).to have_http_status(:not_found)
  end

  it "rejects malformed retry capabilities rather than silently losing retry protection" do
    [ "", "guest@example.com", "a" * 63, [ "a" * 64 ] ].each do |token|
      post "/api/v1/meeting-types/retry-discussion/bookings",
        params: payload.merge(attemptToken: token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("code" => "validation")
    end
    expect(Booking.count).to eq(0)
    expect(Occupancy.count).to eq(0)
  end

  it "does not recreate or disclose a booking after authenticated permanent deletion and a guest retry" do
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "retry-deletion-owner"
    ENV["ADMIN_PASSWORD"] = "retry-deletion-test-password!"
    post "/api/v1/meeting-types/retry-discussion/bookings", params: payload, as: :json
    expect(response).to have_http_status(:created)
    id = JSON.parse(response.body).fetch("id")
    post "/api/v1/admin/session",
      params: { username: ENV.fetch("ADMIN_USERNAME"), password: ENV.fetch("ADMIN_PASSWORD") },
      headers: { "X-Calendar-Request" => "1" }, as: :json
    expect(response).to have_http_status(:ok)
    delete "/api/v1/admin/bookings/#{id}", headers: { "X-Calendar-Request" => "1" }
    expect(response).to have_http_status(:no_content)
    OpenapiContract.validate!(request, response)
    delete "/api/v1/admin/session", headers: { "X-Calendar-Request" => "1" }
    expect(response).to have_http_status(:no_content)
    post "/api/v1/meeting-types/retry-discussion/bookings", params: payload, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)).to include("code" => "attempt_deleted")
    expect(response.body).not_to include(id, "Private Guest", "private@example.com", "Private notes")
    OpenapiContract.validate!(request, response)
    expect(Booking.count).to eq(0)
    expect(Occupancy.count).to eq(0)
  ensure
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end
end
