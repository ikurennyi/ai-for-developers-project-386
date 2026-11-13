require "rails_helper"

# No public write endpoint exists in #27. Exercise the persistent exclusion
# boundary directly; #28 must add concurrent HTTP booking acceptance on top.
RSpec.describe "Shared PostgreSQL occupancy", type: :request do
  self.use_transactional_tests = false

  after { Occupancy.delete_all }

  it "atomically permits one competing interval on independent connections and allows adjacency" do
    ready = Queue.new
    release = Queue.new
    outcomes = Queue.new
    workers = [ [ "10:00", "10:20" ], [ "10:15", "10:45" ] ].map do |first, last|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          release.pop
          begin
            Occupancy.create!(starts_at: "2040-01-02T#{first}:00Z", ends_at: "2040-01-02T#{last}:00Z")
            outcomes << :created
          rescue ActiveRecord::StatementInvalid => error
            raise unless error.cause.is_a?(PG::ExclusionViolation)
            outcomes << :overlap
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { release << true }
    workers.each(&:value)
    expect(2.times.map { outcomes.pop }).to contain_exactly(:created, :overlap)
    occupied = Occupancy.sole
    expect do
      Occupancy.create!(starts_at: occupied.ends_at, ends_at: occupied.ends_at + 15.minutes)
    end.to change(Occupancy, :count).from(1).to(2)
  end

  [
    [ "09:45", "10:15" ], [ "10:15", "10:45" ], [ "10:05", "10:10" ],
    [ "09:00", "11:00" ], [ "10:00", "10:20" ]
  ].each do |first, last|
    it "rejects overlapping #{first}–#{last} even when application validation is bypassed" do
      Occupancy.create!(starts_at: "2040-01-02T10:00:00Z", ends_at: "2040-01-02T10:20:00Z")
      expect do
        Occupancy.insert_all!([ { starts_at: "2040-01-02T#{first}:00Z", ends_at: "2040-01-02T#{last}:00Z" } ])
      end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::ExclusionViolation) }
      expect(Occupancy.count).to eq(1)
    end
  end

  it "rejects empty and reversed intervals in persistent storage" do
    [ "10:00", "09:00" ].each do |last|
      expect do
        Occupancy.insert_all!([ { starts_at: "2040-01-02T10:00:00Z", ends_at: "2040-01-02T#{last}:00Z" } ])
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
    expect(Occupancy.count).to eq(0)
  end
end
