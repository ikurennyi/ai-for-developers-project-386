require "rails_helper"
require "timeout"
require_relative "../support/openapi_contract"

RSpec.describe "Meeting type changes and booked commitments", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:headers) { { "X-Calendar-Request" => "1" } }
  let(:original) { { name: "Discussion", description: "Original terms", durationMinutes: 20, slug: "discussion" } }
  let(:snapshot) do
    { "meetingName" => "Discussion", "meetingDescription" => "Original terms", "durationMinutes" => 20,
      "startsAt" => "2026-11-13T09:00:00Z", "endsAt" => "2026-11-13T09:20:00Z" }
  end

  around do |example|
    previous = ENV.to_h.slice("ADMIN_USERNAME", "ADMIN_PASSWORD")
    ENV["ADMIN_USERNAME"] = "invariants-owner"
    ENV["ADMIN_PASSWORD"] = "invariants-test-password!"
    travel_to Time.iso8601("2026-11-13T07:00:00Z")
    example.run
  ensure
    travel_back
    %w[ADMIN_USERNAME ADMIN_PASSWORD].each { |key| ENV[key] = previous[key] }
  end

  before do
    post "/api/v1/admin/session",
      params: { username: ENV.fetch("ADMIN_USERNAME"), password: ENV.fetch("ADMIN_PASSWORD") }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    OpenapiContract.validate!(request, response)
    @offer = create_published(original)
    @other = create_published(name: "Other offer", description: "", durationMinutes: 15, slug: "other")
  end

  {
    name: { name: "Renamed discussion" },
    description: { description: "New terms" },
    duration: { durationMinutes: 45 },
    address: { slug: "new-address" },
    hiding: { published: false }
  }.each do |change, attributes|
    it "preserves the original booking snapshot, exact instants and shared occupancy after #{change}" do
      post "/api/v1/meeting-types/discussion/bookings", params: confirmation(@offer), as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(snapshot)
      OpenapiContract.validate!(request, response)
      booking_id = response.parsed_body.fetch("id")

      change_offer(@offer, attributes)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(attributes.transform_keys(&:to_s))
      OpenapiContract.validate!(request, response)

      expect_saved_commitment(booking_id)
      expect_shared_occupancy
    end
  end

  context "when administration and confirmation overlap on independent PostgreSQL connections" do
    self.use_transactional_tests = false

    before { @threads = [] }

    after do
      Array(@threads).each { |thread| thread.join(15) }
      Booking.delete_all
      Occupancy.delete_all
      MeetingType.delete_all
      AdminSession.delete_all
      Administrator.delete_all
      AdminLoginLimit.delete_all
    end

    {
      name: { name: "Renamed discussion" },
      description: { description: "New terms" },
      duration: { durationMinutes: 45 },
      address: { slug: "new-address" },
      hiding: { published: false }
    }.each do |change, attributes|
      it "rejects stale confirmation when the authenticated #{change} request commits first" do
        booking_thread = nil
        ActiveRecord::Base.connection_pool.with_connection do |admin_connection|
          admin_connection.transaction do
            # Hold the real admin HTTP transaction open after its write. No ORM
            # mutation substitutes for the controller's validation or locking.
            change_offer(@offer, attributes)
            expect(response).to have_http_status(:ok)
            OpenapiContract.validate!(request, response)
            booking_thread, booking_pid = start_request do |session|
              session.post "/api/v1/meeting-types/discussion/bookings", params: confirmation(@offer), as: :json
            end
            await_blocked_by(admin_connection, booking_pid, backend_pid(admin_connection), thread: booking_thread)
          end
        end
        status, body = Timeout.timeout(10) { booking_thread.value }
        if [ :address, :hiding ].include?(change)
          expect(status).to eq(404)
          expect(body).to eq("message" => "Meeting type unavailable")
        else
          expect(status).to eq(409)
          expect(body).to include("code" => "details_changed")
        end
        expect(Booking.count).to eq(0)
        expect(Occupancy.count).to eq(0)
      end

      it "preserves the confirmed commitment when the authenticated #{change} request waits for confirmation" do
        booking_thread = admin_thread = nil
        ActiveRecord::Base.connection_pool.with_connection do |coordinator|
          coordinator.transaction do
            # Pause the real confirmation after its reviewed-details check.
            # The admin must wait for that confirmation, not change its terms
            # while the occupancy INSERT is waiting for this external lock.
            coordinator.execute("LOCK TABLE occupancies IN SHARE MODE")
            booking_thread, booking_pid = start_request do |session|
              session.post "/api/v1/meeting-types/discussion/bookings", params: confirmation(@offer), as: :json
            end
            await_blocked_by(coordinator, booking_pid, backend_pid(coordinator), thread: booking_thread)
            admin_thread, admin_pid = start_request do |session|
              change_offer(@offer, attributes, session: session)
            end
            expect(admin_pid).not_to eq(backend_pid(coordinator))
            await_blocked_by(coordinator, admin_pid, booking_pid, thread: admin_thread)
          end
        end
        booking_status, booking = Timeout.timeout(10) { booking_thread.value }
        admin_status, offer = Timeout.timeout(10) { admin_thread.value }
        expect(booking_status).to eq(201)
        expect(booking).to include(snapshot)
        expect(admin_status).to eq(200)
        expect(offer).to include(attributes.transform_keys(&:to_s))
        expect_saved_commitment(booking.fetch("id"))
        expect_shared_occupancy
      end
    end

    def start_request(&operation)
      pids = Queue.new
      token = cookies["calendar_admin"]
      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.execute("SET statement_timeout = '10s'")
          pids << backend_pid(connection)
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.cookies["calendar_admin"] = token
          operation.call(session)
          OpenapiContract.validate!(session.request, session.response)
          [ session.response.status, session.response.parsed_body ]
        ensure
          connection.execute("RESET statement_timeout")
        end
      end
      @threads << thread
      [ thread, Timeout.timeout(10) { pids.pop } ]
    end

    def backend_pid(connection)
      Integer(connection.select_value("SELECT pg_backend_pid()"))
    end

    def await_blocked_by(observer, waiting_pid, blocking_pid, thread:)
      expect(waiting_pid).not_to eq(blocking_pid)
      Timeout.timeout(10) do
        loop do
          break if observer.select_value(
            "SELECT #{Integer(blocking_pid)} = ANY(pg_blocking_pids(#{Integer(waiting_pid)}))")
          raise "HTTP request finished before the expected database lock wait" unless thread.alive?
          Thread.pass
        end
      end
    end
  end

  def create_published(details)
    post "/api/v1/admin/meeting-types", params: details, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    OpenapiContract.validate!(request, response)
    id = response.parsed_body.fetch("id")
    put "/api/v1/admin/meeting-types/#{id}/publication", params: { published: true }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    OpenapiContract.validate!(request, response)
    response.parsed_body
  end

  def change_offer(offer, attributes, session: self)
    path = "/api/v1/admin/meeting-types/#{offer.fetch('id')}"
    if attributes.key?(:published)
      session.put "#{path}/publication", params: attributes, headers: headers, as: :json
    else
      session.put path, params: original.merge(attributes), headers: headers, as: :json
    end
  end

  def confirmation(offer, starts_at: "2026-11-13T09:00:00Z")
    { startsAt: starts_at, meetingType: offer.slice("name", "description", "durationMinutes"),
      guestName: "Guest", guestEmail: "guest@example.com", notes: "Original guest notes" }
  end

  def expect_saved_commitment(id)
    # No public booking-read endpoint exists. Inspect the persistent result at
    # the agreed HTTP -> PostgreSQL seam, not an in-memory response copy.
    booking = Booking.find(id)
    expect(booking).to have_attributes(meeting_type_id: @offer.fetch("id"),
      meeting_name: "Discussion", meeting_description: "Original terms", duration_minutes: 20,
      starts_at: Time.iso8601("2026-11-13T09:00:00Z"), ends_at: Time.iso8601("2026-11-13T09:20:00Z"),
      guest_name: "Guest", guest_email: "guest@example.com", notes: "Original guest notes")
    expect(booking.occupancy).to have_attributes(
      starts_at: Time.iso8601("2026-11-13T09:00:00Z"), ends_at: Time.iso8601("2026-11-13T09:20:00Z"))
  end

  def expect_shared_occupancy
    get "/api/v1/meeting-types/other/availability"
    expect(response).to have_http_status(:ok)
    OpenapiContract.validate!(request, response)
    intervals = response.parsed_body.fetch("days").flat_map { |day| day.fetch("intervals") }
    expect(intervals).to include(
      include("startsAt" => "2026-11-13T09:00:00Z", "available" => false),
      include("startsAt" => "2026-11-13T09:15:00Z", "available" => false),
      include("startsAt" => "2026-11-13T09:30:00Z", "available" => true))
    post "/api/v1/meeting-types/other/bookings",
      params: confirmation(@other, starts_at: "2026-11-13T09:15:00Z"), as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include("code" => "occupied")
    OpenapiContract.validate!(request, response)
    expect(Booking.count).to eq(1)
    expect(Occupancy.count).to eq(1)
  end
end
