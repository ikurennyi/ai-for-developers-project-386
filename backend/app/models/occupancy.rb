# The single owner's shared occupied instants. No guest information belongs here.
# A future booking must create/delete its occupancy in the same DB transaction.
# PostgreSQL, not the advisory calendar query, atomically excludes overlaps.
class Occupancy < ApplicationRecord
  validates :starts_at, :ends_at, presence: true
end
