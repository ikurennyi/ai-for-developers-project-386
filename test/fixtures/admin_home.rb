# Loaded only by the isolated smoke runner, never by application initialization.
type = MeetingType.create!(name: "Changed Home fixture", slug: "home-browser-fixture", duration_minutes: 30)
now = Time.current.change(usec: 0)
notes = "<img src=x onerror=alert(1)>\n" + "full notes " * 190
[
  [ now - 60.minutes, now - 30.minutes, "Completed Home fixture" ],
  [ now - 15.minutes, now + 60.minutes, "Ongoing saved meeting" ],
  [ now + 90.minutes, now + 120.minutes, "Later saved meeting" ],
  [ now.in_time_zone("Europe/Berlin").beginning_of_day + 32.days + 9.hours,
    now.in_time_zone("Europe/Berlin").beginning_of_day + 32.days + 9.hours + 30.minutes, "Distant saved meeting" ]
].each do |starts_at, ends_at, name|
  occupancy = Occupancy.create!(starts_at: starts_at, ends_at: ends_at)
  Booking.create!(meeting_type: type, occupancy: occupancy, starts_at: starts_at, ends_at: ends_at,
    meeting_name: name, meeting_description: "Saved description", duration_minutes: 30,
    guest_name: "<b>Home browser guest</b>", guest_email: "home-browser@example.com", notes: notes)
end
