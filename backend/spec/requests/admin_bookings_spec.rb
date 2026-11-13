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

  it "permanently deletes a booking and its shared occupancy only for an authenticated protected request" do
    travel_to Time.utc(2026, 11, 13, 8) do
      booking = saved_booking(Time.utc(2026, 11, 13, 10), Time.utc(2026, 11, 13, 10, 15), "Saved name")
      occupancy_id = booking.occupancy_id
      path = "/api/v1/admin/bookings/#{booking.id}"
      delete path, headers: { "X-Calendar-Request" => "1" }
      expect(response).to have_http_status(:unauthorized)
      OpenapiContract.validate!(request, response)
      expect(Booking.exists?(booking.id)).to be(true)
      expect(Occupancy.exists?(occupancy_id)).to be(true)
      login
      delete path, headers: { "X-Calendar-Request" => "1", "Origin" => "https://unrelated.example" }
      expect(response).to have_http_status(:forbidden)
      OpenapiContract.validate!(request, response)
      expect(Booking.exists?(booking.id)).to be(true)
      expect(Occupancy.exists?(occupancy_id)).to be(true)
      delete path
      expect(response).to have_http_status(:forbidden)
      OpenapiContract.validate!(request, response, validate_request: false)
      expect(Booking.exists?(booking.id)).to be(true)
      expect(Occupancy.exists?(occupancy_id)).to be(true)
      delete path, headers: { "X-Calendar-Request" => "1" }
      expect(response).to have_http_status(:no_content)
      OpenapiContract.validate!(request, response)
      expect(Booking.exists?(booking.id)).to be(false)
      expect(Occupancy.exists?(occupancy_id)).to be(false)
      delete path, headers: { "X-Calendar-Request" => "1" }
      expect(response).to have_http_status(:not_found)
      OpenapiContract.validate!(request, response)
    end
  end

  it "deletes completed and distant bookings without making past or out-of-window dates bookable" do
    travel_to Time.utc(2026, 11, 13, 8) do
      past = saved_booking(Time.utc(2026, 11, 12, 10), Time.utc(2026, 11, 12, 10, 15), "Past")
      distant = saved_booking(Time.utc(2026, 12, 15, 10), Time.utc(2026, 12, 15, 10, 15), "Distant")
      offer = MeetingType.create!(name: "Published", slug: "published", duration_minutes: 15, published: true)
      login
      [ past, distant ].each do |booking|
        delete "/api/v1/admin/bookings/#{booking.id}", headers: { "X-Calendar-Request" => "1" }
        expect(response).to have_http_status(:no_content)
        OpenapiContract.validate!(request, response)
        expect(Booking.exists?(booking.id)).to be(false)
        expect(Occupancy.exists?(booking.occupancy_id)).to be(false)
      end
      get "/api/v1/meeting-types/#{offer.slug}/availability"
      dates = response.parsed_body.fetch("days").map { |day| day["date"] }
      expect(dates).not_to include("2026-11-12", "2026-12-15")
      expect(response.parsed_body.fetch("days").find { |day| day["date"] == "2026-11-14" }["intervals"]).to eq([])
    end
  end

  it "releases shared public availability but never bypasses time or remaining occupancy" do
    travel_to Time.utc(2026, 11, 13, 8) do
      booking = saved_booking(Time.utc(2026, 11, 13, 10), Time.utc(2026, 11, 13, 10, 15), "Saved")
      offer = MeetingType.create!(name: "Other offer", slug: "other-offer", duration_minutes: 30, published: true)
      saved_booking(Time.utc(2026, 11, 13, 10, 15), Time.utc(2026, 11, 13, 10, 30), "Adjacent")
      login
      get "/api/v1/meeting-types/#{offer.slug}/availability"
      intervals = response.parsed_body.fetch("days").first.fetch("intervals")
      expect(intervals.find { |slot| slot["startsAt"] == "2026-11-13T09:45:00Z" }["available"]).to be(false)
      delete "/api/v1/admin/bookings/#{booking.id}", headers: { "X-Calendar-Request" => "1" }
      expect(response).to have_http_status(:no_content)
      get "/api/v1/meeting-types/#{offer.slug}/availability"
      OpenapiContract.validate!(request, response)
      intervals = response.parsed_body.fetch("days").first.fetch("intervals")
      expect(intervals.find { |slot| slot["startsAt"] == "2026-11-13T09:45:00Z" }["available"]).to be(true)
      expect(intervals.find { |slot| slot["startsAt"] == "2026-11-13T10:00:00Z" }["available"]).to be(false)
      expect(intervals.find { |slot| slot["startsAt"] == "2026-11-13T08:00:00Z" }["available"]).to be(false)
    end
  end

  it "rolls back the booking removal when PostgreSQL refuses occupancy removal" do
    booking = saved_booking(1.day.from_now, 1.day.from_now + 15.minutes, "Retained")
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      CREATE FUNCTION refuse_occupancy_delete() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'deletion refused'; END $$;
      CREATE TRIGGER refuse_occupancy_delete BEFORE DELETE ON occupancies
      FOR EACH ROW EXECUTE FUNCTION refuse_occupancy_delete();
    SQL
    login
    delete "/api/v1/admin/bookings/#{booking.id}", headers: { "X-Calendar-Request" => "1" }
    expect(response).to have_http_status(:service_unavailable)
    OpenapiContract.validate!(request, response)
    expect(Booking.exists?(booking.id)).to be(true)
    expect(Occupancy.exists?(booking.occupancy_id)).to be(true)
    get "/api/v1/admin/bookings"
    expect(response.parsed_body.fetch("bookings").map { |record| record["id"] }).to include(booking.id)
  ensure
    connection.execute("DROP TRIGGER IF EXISTS refuse_occupancy_delete ON occupancies; DROP FUNCTION IF EXISTS refuse_occupancy_delete()")
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
