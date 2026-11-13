class CalendarAvailability
  ZONE = ActiveSupport::TimeZone["Europe/Berlin"]
  Interval = Data.define(:starts_at, :ends_at, :available)

  def initialize(meeting_type, now: Time.current)
    @meeting_type = meeting_type
    @now = now
    @today = now.in_time_zone(ZONE).to_date
    @occupied = Occupancy.where("starts_at < ? AND ends_at > ?",
      ZONE.local((@today + 14).year, (@today + 14).month, (@today + 14).day),
      ZONE.local(@today.year, @today.month, @today.day)).pluck(:starts_at, :ends_at)
  end

  def as_json
    {
      meetingType: {
        id: @meeting_type.id, name: @meeting_type.name, description: @meeting_type.description,
        durationMinutes: @meeting_type.duration_minutes, slug: @meeting_type.slug
      },
      hostName: "Alex Morgan", timeZone: "Europe/Berlin", serverNow: @now.utc.iso8601,
      today: @today.iso8601, windowEnd: (@today + 13).iso8601,
      days: (@today..@today + 13).map { |date| day(date) }
    }
  end

  def interval_at(starts_at)
    return unless starts_at
    date = starts_at.in_time_zone(ZONE).to_date
    return unless (@today..@today + 13).cover?(date) && !date.saturday? && !date.sunday?
    opening = ZONE.local(date.year, date.month, date.day, 9)
    offset = starts_at - opening
    return unless offset >= 0 && offset <= (540 - @meeting_type.duration_minutes).minutes && (offset % 15.minutes).zero?
    interval(starts_at)
  end

  private

  def day(date)
    working = !date.saturday? && !date.sunday?
    {
      date: date.iso8601, workingDay: working,
      intervals: working ? intervals(date).map { |entry|
        { startsAt: entry.starts_at.utc.iso8601, endsAt: entry.ends_at.utc.iso8601, available: entry.available }
      } : []
    }
  end

  def intervals(date)
    opening = ZONE.local(date.year, date.month, date.day, 9)
    (0..(540 - @meeting_type.duration_minutes)).step(15).map do |minutes|
      interval(opening + minutes.minutes)
    end
  end

  def interval(starts_at)
    ends_at = starts_at + @meeting_type.duration_minutes.minutes
    free = @occupied.none? { |first, last| first < ends_at && starts_at < last }
    Interval.new(starts_at, ends_at, starts_at > @now && free)
  end
end
