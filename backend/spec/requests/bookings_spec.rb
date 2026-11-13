require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Booking confirmation", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:meeting_type) do
    MeetingType.create!(name: "Discussion", description: "Discuss a topic", duration_minutes: 20,
      slug: "discussion", published: true)
  end
  let(:payload) do
    { startsAt: "2026-11-13T09:00:00Z",
      meetingType: { name: "Discussion", description: "Discuss a topic", durationMinutes: 20 },
      guestName: "  Guest  ", guestEmail: "guest@example.com", notes: "<b>Plain text</b>" }
  end

  before { travel_to Time.iso8601("2026-11-13T07:00:00Z") }
  after { travel_back }

  it "confirms explicitly with exact instants, trimmed guest name and immutable meeting details" do
    post "/api/v1/meeting-types/discussion/bookings", params: payload, as: :json
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body).to include("startsAt" => "2026-11-13T09:00:00Z", "endsAt" => "2026-11-13T09:20:00Z",
      "guestName" => "Guest", "guestEmail" => "guest@example.com", "notes" => "<b>Plain text</b>",
      "meetingName" => "Discussion", "meetingDescription" => "Discuss a topic", "durationMinutes" => 20,
      "hostName" => "Alex Morgan", "timeZone" => "Europe/Berlin")
    OpenapiContract.validate!(request, response)
    meeting_type.update!(name: "Changed", description: "New", duration_minutes: 30, slug: "new", published: false)
    booking = Booking.find(body.fetch("id"))
    expect(booking).to have_attributes(meeting_name: "Discussion", meeting_description: "Discuss a topic",
      duration_minutes: 20, starts_at: Time.iso8601("2026-11-13T09:00:00Z"),
      ends_at: Time.iso8601("2026-11-13T09:20:00Z"), meeting_type_id: meeting_type.id)
    expect(booking.occupancy).to have_attributes(starts_at: booking.starts_at, ends_at: booking.ends_at)
    get "/api/v1/meeting-types/discussion/bookings/#{body.fetch('id')}"
    expect(response).to have_http_status(:not_found)
  end

  it "validates guest data without creating a booking or occupancy and returns English field errors" do
    [
      [ { guestName: " \t " }, "guestName", "Enter your name (1–100 characters)." ],
      [ { guestName: "é" * 101 }, "guestName", "Enter your name (1–100 characters)." ],
      [ { guestEmail: "" }, "guestEmail", "Enter a valid email address (up to 254 characters)." ],
      [ { guestEmail: "guest@example" }, "guestEmail", "Enter a valid email address (up to 254 characters)." ],
      [ { guestEmail: ".guest@example.com" }, "guestEmail", "Enter a valid email address (up to 254 characters)." ],
      [ { guestEmail: "guest..name@example.com" }, "guestEmail", "Enter a valid email address (up to 254 characters)." ],
      [ { guestEmail: "a" * 243 + "@example.com" }, "guestEmail", "Enter a valid email address (up to 254 characters)." ],
      [ { notes: "🙂" * 2001 }, "notes", "Use at most 2000 characters." ],
      [ { guestName: [ "Guest" ] }, "guestName", "Enter your name (1–100 characters)." ]
    ].each do |changes, field, message|
      expect do
        post "/api/v1/meeting-types/discussion/bookings", params: payload.merge(changes), as: :json
      end.not_to change(Occupancy, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("code" => "validation", "errors" => { field => message })
      # Array input is intentionally malformed beyond the request schema.
      OpenapiContract.validate!(request, response) unless changes[:guestName].is_a?(Array)
    end
    expect(Booking.count).to eq(0)
    post "/api/v1/meeting-types/discussion/bookings", params: payload.merge(
      guestName: "  " + "é" * 100 + "  ", guestEmail: "a" * 242 + "@example.com", notes: "🙂" * 2000), as: :json
    expect(response).to have_http_status(:created)
    OpenapiContract.validate!(request, response)
  end

  it "rejects changed reviewed details, hidden offers and old addresses without booking" do
    [ { name: "Changed" }, { description: "Changed" }, { duration_minutes: 30 } ].each do |changes|
      original = meeting_type.attributes.slice(*changes.keys.map(&:to_s))
      meeting_type.update!(changes)
      post "/api/v1/meeting-types/discussion/bookings", params: payload, as: :json
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to include("code" => "details_changed")
      OpenapiContract.validate!(request, response)
      meeting_type.update!(original)
    end
    meeting_type.update!(published: false)
    post "/api/v1/meeting-types/discussion/bookings", params: payload, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JSON.parse(response.body)).to eq("message" => "Meeting type unavailable")
    OpenapiContract.validate!(request, response)
    meeting_type.update!(published: true, slug: "new-address")
    post "/api/v1/meeting-types/discussion/bookings", params: payload, as: :json
    expect(response).to have_http_status(:not_found)
    expect(Booking.count).to eq(0)
    expect(Occupancy.count).to eq(0)
  end

  it "rechecks the current Berlin window, future start, grid, weekends and complete working day" do
    [
      "2026-11-12T09:00:00Z", "2026-11-27T09:00:00Z", "2026-11-14T09:00:00Z",
      "2026-11-13T07:45:00Z", "2026-11-13T17:00:00Z", "2026-11-13T16:45:00Z",
      "2026-11-13T09:07:00Z", "2026-11-13T09:00:00.001Z"
    ].each do |starts_at|
      post "/api/v1/meeting-types/discussion/bookings", params: payload.merge(startsAt: starts_at), as: :json
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to include("code" => "invalid_interval")
      OpenapiContract.validate!(request, response)
    end
    [ "2026-11-13T09:00:00Z", "2026-11-13T09:07:00Z", "2026-11-26T23:00:00Z" ].each do |now|
      travel_to Time.iso8601(now)
      post "/api/v1/meeting-types/discussion/bookings", params: payload, as: :json
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to include("code" => "invalid_interval")
    end
    expect(Booking.count).to eq(0)
    expect(Occupancy.count).to eq(0)
  end

  it "shares 10:00–10:20 occupancy across types, rejects every overlap shape and allows 10:30" do
    post "/api/v1/meeting-types/discussion/bookings", params: payload, as: :json
    expect(response).to have_http_status(:created)
    meeting_type.update!(published: false)
    [
      [ 30, "08:45" ], # partial overlap from the left
      [ 30, "09:15" ], # partial overlap from the right: 10:15 Berlin
      [ 1, "09:00" ],  # nested
      [ 45, "08:45" ], # containing
      [ 20, "09:00" ]  # identical
    ].each_with_index do |(duration, time), index|
      type = MeetingType.create!(name: "Other #{index}", duration_minutes: duration,
        slug: "other-#{index}", published: true)
      post "/api/v1/meeting-types/#{type.slug}/bookings", params: payload.merge(
        startsAt: "2026-11-13T#{time}:00Z",
        meetingType: { name: type.name, description: "", durationMinutes: duration }), as: :json
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to include("code" => "occupied")
      OpenapiContract.validate!(request, response)
    end
    meeting_type.update!(published: true)
    post "/api/v1/meeting-types/discussion/bookings",
      params: payload.merge(startsAt: "2026-11-13T09:30:00Z"), as: :json
    expect(response).to have_http_status(:created)
    expect(Booking.count).to eq(2)
    expect(Occupancy.count).to eq(2)
  end

  it "allows exact 10:30 adjacency after 10:00–10:30" do
    meeting_type.update!(duration_minutes: 30)
    params = payload.except(:notes).merge(meetingType: payload[:meetingType].merge(durationMinutes: 30))
    [ "09:00", "09:30" ].each do |time|
      post "/api/v1/meeting-types/discussion/bookings",
        params: params.merge(startsAt: "2026-11-13T#{time}:00Z"), as: :json
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to include("notes" => "")
      OpenapiContract.validate!(request, response)
    end
    expect(Occupancy.count).to eq(2)
  end

  { 1 => [ "16:45", "16:46" ], 20 => [ "16:30", "16:50" ], 45 => [ "16:15", "17:00" ],
    90 => [ "15:30", "17:00" ], 540 => [ "08:00", "17:00" ] }.each do |duration, (starts, ends)|
    it "confirms the last #{duration}-minute interval that fits the working day" do
      meeting_type.update!(duration_minutes: duration)
      post "/api/v1/meeting-types/discussion/bookings", params: payload.merge(
        startsAt: "2026-11-13T#{starts}:00Z",
        meetingType: payload[:meetingType].merge(durationMinutes: duration)), as: :json
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to include("endsAt" => "2026-11-13T#{ends}:00Z",
        "durationMinutes" => duration)
      OpenapiContract.validate!(request, response)
    end
  end

  [
    [ "2026-03-27T06:00:00Z", "2026-03-27T08:00:00Z", "2026-03-30T07:00:00Z" ],
    [ "2026-10-23T06:00:00Z", "2026-10-23T07:00:00Z", "2026-10-26T08:00:00Z" ]
  ].each do |now, before_dst, after_dst|
    it "confirms Berlin 09:00 with exact instants across DST at #{after_dst}" do
      travel_to Time.iso8601(now)
      [ before_dst, after_dst ].each do |starts|
        post "/api/v1/meeting-types/discussion/bookings", params: payload.merge(startsAt: starts), as: :json
        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)).to include("startsAt" => starts,
          "endsAt" => (Time.iso8601(starts) + 20.minutes).iso8601)
        OpenapiContract.validate!(request, response)
      end
      expect(Booking.order(:starts_at).pluck(:starts_at)).to eq(
        [ Time.iso8601(before_dst), Time.iso8601(after_dst) ])
    end
  end
end
