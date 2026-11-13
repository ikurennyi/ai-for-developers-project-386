require "rails_helper"
require_relative "../support/openapi_contract"

RSpec.describe "Public calendar availability", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:meeting_type) do
    MeetingType.create!(name: "Discussion", description: "Discuss a topic", duration_minutes: 20,
      slug: "discussion", published: true)
  end

  after { travel_back }

  it "opens a published calendar with Berlin dates, working days and strictly future grid starts" do
    travel_to Time.iso8601("2026-11-13T13:07:00Z")
    get "/api/v1/meeting-types/discussion/availability"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("hostName" => "Alex Morgan", "timeZone" => "Europe/Berlin",
      "today" => "2026-11-13", "windowEnd" => "2026-11-26",
      "meetingType" => hash_including("name" => "Discussion", "durationMinutes" => 20))
    expect(body.fetch("days").length).to eq(14)
    friday, saturday = body.fetch("days").first(2)
    expect(saturday).to include("date" => "2026-11-14", "workingDay" => false, "intervals" => [])
    expect(friday.fetch("intervals")).to include(
      hash_including("startsAt" => "2026-11-13T13:00:00Z", "available" => false),
      hash_including("startsAt" => "2026-11-13T13:15:00Z", "available" => true))
    expect(friday.fetch("intervals").last).to include(
      "startsAt" => "2026-11-13T16:30:00Z", "endsAt" => "2026-11-13T16:50:00Z")
    OpenapiContract.validate!(request, response)
  end

  it "shares persistent half-open occupancy across offers without disclosing its source or reserving time" do
    travel_to Time.iso8601("2026-11-13T07:00:00Z")
    Occupancy.create!(starts_at: "2026-11-13T09:00:00Z", ends_at: "2026-11-13T09:20:00Z")
    other = MeetingType.create!(name: "Other offer", duration_minutes: 30, slug: "other", published: true)
    [ meeting_type, other ].each do |type|
      get "/api/v1/meeting-types/#{type.slug}/availability"
      intervals = JSON.parse(response.body).fetch("days").first.fetch("intervals")
      expect(intervals).to include(
        hash_including("startsAt" => "2026-11-13T08:30:00Z", "available" => true),
        hash_including("startsAt" => "2026-11-13T08:45:00Z", "available" => false),
        hash_including("startsAt" => "2026-11-13T09:00:00Z", "available" => false),
        hash_including("startsAt" => "2026-11-13T09:15:00Z", "available" => false),
        hash_including("startsAt" => "2026-11-13T09:30:00Z", "available" => true))
      expect(intervals.first.keys).to contain_exactly("startsAt", "endsAt", "available")
      OpenapiContract.validate!(request, response)
    end
    meeting_type.update!(published: false)
    get "/api/v1/meeting-types/other/availability"
    expect(JSON.parse(response.body).fetch("days").first.fetch("intervals"))
      .to include(hash_including("startsAt" => "2026-11-13T09:00:00Z", "available" => false))
    expect(Occupancy.count).to eq(1)
  end

  it "makes hidden, nonexistent and old public addresses identically unavailable" do
    meeting_type.update!(published: false)
    bodies = [ "discussion", "missing" ].map do |slug|
      get "/api/v1/meeting-types/#{slug}/availability"
      expect(response).to have_http_status(:not_found)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      OpenapiContract.validate!(request, response)
      JSON.parse(response.body)
    end
    expect(bodies).to eq([ { "message" => "Meeting type unavailable" } ] * 2)
    meeting_type.update!(published: true, slug: "new-address")
    get "/api/v1/meeting-types/discussion/availability"
    expect(response).to have_http_status(:not_found)
    get "/api/v1/meeting-types/new-address/availability"
    expect(response).to have_http_status(:ok)
  end

  { 1 => [ "16:45:00", "16:46:00", 36 ], 20 => [ "16:30:00", "16:50:00", 35 ],
    45 => [ "16:15:00", "17:00:00", 34 ], 90 => [ "15:30:00", "17:00:00", 31 ],
    540 => [ "08:00:00", "17:00:00", 1 ] }.each do |duration, (last_start, last_end, count)|
    it "fits #{duration}-minute intervals completely inside the working day on a 15-minute start grid" do
      travel_to Time.iso8601("2026-11-13T07:00:00Z")
      meeting_type.update!(duration_minutes: duration)
      get "/api/v1/meeting-types/discussion/availability"
      intervals = JSON.parse(response.body).fetch("days").first.fetch("intervals")
      expect(intervals.size).to eq(count)
      expect(intervals.first).to include("startsAt" => "2026-11-13T08:00:00Z", "available" => true)
      expect(intervals.last).to include(
        "startsAt" => "2026-11-13T#{last_start}Z", "endsAt" => "2026-11-13T#{last_end}Z")
      expect(intervals).to all(include("available" => true))
      OpenapiContract.validate!(request, response)
    end
  end

  [ "13:00:00", "13:07:00" ].each do |now|
    it "disables 14:00 Berlin at #{now} UTC but permits 14:15 without added lead time" do
      travel_to Time.iso8601("2026-11-13T#{now}Z")
      get "/api/v1/meeting-types/discussion/availability", headers: { "Time-Zone" => "Pacific/Honolulu" }
      expect(JSON.parse(response.body).fetch("days").first.fetch("intervals")).to include(
        hash_including("startsAt" => "2026-11-13T13:00:00Z", "available" => false),
        hash_including("startsAt" => "2026-11-13T13:15:00Z", "available" => true))
    end
  end

  it "recomputes calendar dates at Berlin midnight rather than after 336 hours" do
    travel_to Time.iso8601("2026-11-30T22:59:59Z")
    get "/api/v1/meeting-types/discussion/availability"
    expect(JSON.parse(response.body)).to include("today" => "2026-11-30", "windowEnd" => "2026-12-13")
    travel_to Time.iso8601("2026-11-30T23:00:00Z")
    get "/api/v1/meeting-types/discussion/availability"
    expect(JSON.parse(response.body)).to include("today" => "2026-12-01", "windowEnd" => "2026-12-14")
    expect(JSON.parse(response.body).fetch("days").map { |day| day.fetch("date") })
      .not_to include("2026-11-30", "2026-12-15")
  end

  [
    [ "2026-03-27T06:00:00Z", "2026-03-27", "08:00:00", "2026-03-30", "07:00:00", "2026-04-09" ],
    [ "2026-10-23T06:00:00Z", "2026-10-23", "07:00:00", "2026-10-26", "08:00:00", "2026-11-05" ]
  ].each do |now, before_date, before_time, after_date, after_time, window_end|
    it "preserves Berlin working hours and stored instants across DST at #{after_date}" do
      travel_to Time.iso8601(now)
      meeting_type.update!(duration_minutes: 540)
      Occupancy.create!(starts_at: "#{before_date}T#{before_time}Z",
        ends_at: Time.iso8601("#{before_date}T#{before_time}Z") + 9.hours)
      2.times do
        get "/api/v1/meeting-types/discussion/availability"
        body = JSON.parse(response.body)
        expect(body.fetch("windowEnd")).to eq(window_end)
        days = body.fetch("days")
        expect(days.find { |day| day.fetch("date") == before_date }.fetch("intervals").first)
          .to include("startsAt" => "#{before_date}T#{before_time}Z", "available" => false)
        expect(days.find { |day| day.fetch("date") == after_date }.fetch("intervals").first)
          .to include("startsAt" => "#{after_date}T#{after_time}Z", "available" => true)
      end
    end
  end

  it "reports fully occupied days and the whole window without exposing occupancy records" do
    travel_to Time.iso8601("2026-11-13T07:00:00Z")
    Occupancy.create!(starts_at: "2026-11-13T08:00:00Z", ends_at: "2026-11-27T00:00:00Z")
    get "/api/v1/meeting-types/discussion/availability"
    days = JSON.parse(response.body).fetch("days")
    expect(days.flat_map { |day| day.fetch("intervals") }).to all(include("available" => false))
    expect(response.body).not_to include("occupanc", "guest", "email")
    OpenapiContract.validate!(request, response)
  end
end
