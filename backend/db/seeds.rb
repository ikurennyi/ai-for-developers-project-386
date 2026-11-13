# Stable keys are independent of editable public addresses. Never restore an offer
# by its original slug: the administrator may deliberately have changed it.
[ 15, 30 ].each do |minutes|
  MeetingType.find_or_create_by!(initial_key: "initial-#{minutes}") do |type|
    type.name = "#{minutes}-minute meeting"
    type.description = minutes == 15 ? "A short conversation to connect." : "More time for a focused discussion."
    type.duration_minutes = minutes
    type.slug = "#{minutes}-minute-meeting"
    type.published = true
  end
end
