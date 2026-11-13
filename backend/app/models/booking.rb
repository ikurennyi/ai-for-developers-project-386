class Booking < ApplicationRecord
  belongs_to :meeting_type
  belongs_to :occupancy

  def confirmation
    {
      id: id, meetingName: meeting_name, meetingDescription: meeting_description,
      durationMinutes: duration_minutes, hostName: "Alex Morgan", timeZone: "Europe/Berlin",
      startsAt: starts_at.utc.iso8601, endsAt: ends_at.utc.iso8601,
      guestName: guest_name, guestEmail: guest_email, notes: notes
    }
  end
end
