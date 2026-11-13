# Used only by the disposable smoke database, after public calendar scenarios.
# Independent browser scenarios must not consume one another's login budget.
AdminLoginLimit.delete_all
Booking.delete_all
Occupancy.delete_all
exit if ENV["HISTORY_EMPTY"] == "1"
type = MeetingType.first!
23.times do |index|
  { "Future" => 60 + index, "Past" => -60 - index }.each do |label, offset|
    start = Time.current.in_time_zone("Europe/Berlin").to_date + offset
    start = ActiveSupport::TimeZone["Europe/Berlin"].local(start.year, start.month, start.day, 13)
    occupancy = Occupancy.create!(starts_at: start, ends_at: start + 15.minutes)
    Booking.create!(meeting_type: type, occupancy: occupancy, starts_at: start, ends_at: start + 15.minutes,
      meeting_name: "#{label} #{format("%02d", index)}", meeting_description: "Saved description", duration_minutes: 15,
      guest_name: "<b>History guest</b>", guest_email: "history@example.com",
      notes: "<script>plain text</script>\n" + "Long note. " * 180 + "END")
  end
end
