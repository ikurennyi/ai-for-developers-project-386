require "rails_helper"
require "timeout"
require_relative "../support/openapi_contract"

RSpec.describe "Concurrent booking HTTP requests", type: :request do
  self.use_transactional_tests = false
  include ActiveSupport::Testing::TimeHelpers

  before do
    travel_to Time.iso8601("2026-11-13T07:00:00Z")
    @types = [ 20, 30 ].map do |duration|
      MeetingType.create!(name: "Discussion #{duration}", description: "", duration_minutes: duration,
        slug: "concurrent-#{duration}", published: true)
    end
  end

  after do
    Booking.delete_all
    Occupancy.delete_all
    MeetingType.where(id: @types.map(&:id)).delete_all
    travel_back
  end

  it "lets exactly one overlapping request commit on independent PostgreSQL connections" do
    pids = Queue.new
    threads = []
    # This external DB lock pauses both real requests at their INSERT, after
    # advisory availability checks. It proves the exclusion constraint, rather
    # than request scheduling or a Ruby lock, decides which request can commit.
    ActiveRecord::Base.connection_pool.with_connection do |blocker|
      blocker.transaction do
        blocker.execute("LOCK TABLE occupancies IN SHARE MODE")
        threads = @types.each_with_index.map do |type, index|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do |connection|
              pids << connection.select_value("SELECT pg_backend_pid()")
              session = ActionDispatch::Integration::Session.new(Rails.application)
              session.post "/api/v1/meeting-types/#{type.slug}/bookings",
                params: confirmation(type, index.zero? ? "09:00" : "09:15"), as: :json
              OpenapiContract.validate!(session.request, session.response)
              [ session.response.status, JSON.parse(session.response.body) ]
            end
          end
        end
        connections = Timeout.timeout(10) { 2.times.map { pids.pop } }
        expect(connections.uniq.length).to eq(2)
        expect(connections).not_to include(blocker.select_value("SELECT pg_backend_pid()"))
        Timeout.timeout(10) do
          loop do
            blocker.execute("SELECT pg_stat_clear_snapshot()")
            waiting = blocker.select_value(<<~SQL)
              SELECT count(*) FROM pg_stat_activity
              WHERE pid IN (#{connections.map { |pid| Integer(pid) }.join(",")})
                AND wait_event_type = 'Lock' AND query LIKE 'INSERT INTO "occupancies"%'
            SQL
            break if waiting == 2
            sleep 0.01
          end
        end
      end
    end
    results = Timeout.timeout(10) { threads.map(&:value) }
    expect(results.map(&:first).sort).to eq([ 201, 409 ])
    expect(results.find { |status, _| status == 409 }.last).to include("code" => "occupied",
      "message" => "This time is no longer available. Please choose another time.")
    expect(Booking.count).to eq(1)
    expect(Occupancy.count).to eq(1)
  ensure
    threads&.each { |thread| thread.join(15) }
  end

  it "rolls back both records if an insert wait reaches the selected start before confirmation commits" do
    thread = nil
    pid = Queue.new
    ActiveRecord::Base.connection_pool.with_connection do |blocker|
      blocker.transaction do
        blocker.execute("LOCK TABLE occupancies IN SHARE MODE")
        thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            pid << connection.select_value("SELECT pg_backend_pid()")
            session = ActionDispatch::Integration::Session.new(Rails.application)
            session.post "/api/v1/meeting-types/#{@types.first.slug}/bookings",
              params: confirmation(@types.first, "09:00"), as: :json
            [ session.response.status, JSON.parse(session.response.body) ]
          end
        end
        connection = Timeout.timeout(10) { pid.pop }
        Timeout.timeout(10) do
          loop do
            blocker.execute("SELECT pg_stat_clear_snapshot()")
            break if blocker.select_value(<<~SQL) == 1
              SELECT count(*) FROM pg_stat_activity WHERE pid = #{Integer(connection)}
                AND wait_event_type = 'Lock' AND query LIKE 'INSERT INTO "occupancies"%'
            SQL
            sleep 0.01
          end
        end
        travel_to Time.iso8601("2026-11-13T09:00:00Z")
      end
    end
    status, body = Timeout.timeout(10) { thread.value }
    expect(status).to eq(409)
    expect(body).to include("code" => "invalid_interval")
    expect(Booking.count).to eq(0)
    expect(Occupancy.count).to eq(0)
  ensure
    thread&.join(15)
  end

  it "rechecks publication and reviewed details after waiting for an offer edit transaction" do
    thread = nil
    type = @types.first
    [ [ { published: false }, 404, nil ],
      [ { name: "Changed terms" }, 409, "details_changed" ],
      [ { description: "Changed description" }, 409, "details_changed" ],
      [ { duration_minutes: 30 }, 409, "details_changed" ] ].each do |changes, expected_status, code|
      type.update!(published: true, name: "Discussion 20", description: "", duration_minutes: 20)
      reviewed = confirmation(type, "09:00")
      pid = Queue.new
      type.with_lock do
        type.update!(changes)
        thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            pid << connection.select_value("SELECT pg_backend_pid()")
            session = ActionDispatch::Integration::Session.new(Rails.application)
            session.post "/api/v1/meeting-types/#{type.slug}/bookings", params: reviewed, as: :json
            OpenapiContract.validate!(session.request, session.response)
            [ session.response.status, JSON.parse(session.response.body) ]
          end
        end
        connection = Timeout.timeout(10) { pid.pop }
        blocker = ActiveRecord::Base.connection
        Timeout.timeout(10) do
          loop do
            blocker.execute("SELECT pg_stat_clear_snapshot()")
            break if blocker.select_value(<<~SQL) == 1
              SELECT count(*) FROM pg_stat_activity WHERE pid = #{Integer(connection)}
                AND wait_event_type = 'Lock' AND query LIKE '%FOR SHARE%'
            SQL
            sleep 0.01
          end
        end
      end
      status, body = Timeout.timeout(10) { thread.value }
      expect(status).to eq(expected_status)
      expect(body).to include("code" => code) if code
      expect(Booking.count).to eq(0)
      expect(Occupancy.count).to eq(0)
    end
  ensure
    thread&.join(15)
  end

  def confirmation(type, time)
    { startsAt: "2026-11-13T#{time}:00Z",
      meetingType: { name: type.name, description: type.description, durationMinutes: type.duration_minutes },
      guestName: "Guest", guestEmail: "guest@example.com", notes: "" }
  end
end
