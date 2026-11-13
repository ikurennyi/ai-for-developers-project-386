# Public calendar (#27)

`/book/:slug` opens the calendar; `/book/:slug/details?date=…&start=…`
is currently a summary-only guest-form destination. Booking confirmation belongs
to #28. Neither page creates a booking, reserves time or accepts guest details.
The only URL selection data is the Berlin date and exact start instant.

## Read contract

`GET /api/v1/meeting-types/:slug/availability` returns the current published
meeting type, fixed host name **Alex Morgan** (no host email), server instant,
Berlin today/end dates, and fourteen daily interval lists. TypeSpec owns the
contract; the Vue application uses its generated Fetch SDK. Hidden and
nonexistent types return the same 404 `Meeting type unavailable`, without details.
Responses are `Cache-Control: no-store`.

Dates are today through today + 13 **Berlin calendar dates**, not 336 hours.
Weekends count but have no intervals. Working days use 09:00–18:00 Berlin,
quarter-hour starts, the current duration and strictly future starts. Intervals
ending exactly at 18:00 are valid. The API exposes only interval instants and an
availability boolean, not occupancy identifiers, other meeting types or guests.

The UI initially selects nothing, renders a bounded monthly calendar, uses
24-hour Berlin time regardless of the device zone and stacks its three desktop
columns on phones. Date/time selection and direct form navigation reload the
server snapshot. A stale URL clears the time and returns to the calendar with an
explanation; Back retains valid selection parameters.

## Persistent occupancy and #28 integration

`occupancies` contains UUID, `starts_at`, `ends_at` and timestamps. Rails stores
exact UTC instants. There is deliberately no type/publication filter: occupancy
is shared and survives hiding or editing a meeting type. No public occupancy
write endpoint is introduced in #27.

PostgreSQL enforces positive length and a GiST exclusion constraint on
`tsrange(starts_at, ends_at, '[)') WITH &&`. Adjacent intervals are allowed;
partial, nested, containing and identical overlaps cannot both commit, even on
independent connections. These are UTC Rails timestamps, not civil Berlin times.

For #28, associate each booking with its occupancy and create both in one
transaction **only after explicit successful confirmation**. Catch PostgreSQL
exclusion violations as distinguishable occupied-interval conflicts. Revalidate
the schedule, publication, current details, grid, window and server time at that
boundary; the read snapshot is advisory, not a lock or a reservation.
Booking deletion must remove occupancy in the same transaction. Snapshots, guest
data, confirmation-attempt recovery and authenticated deletion remain #28/later
work, not capabilities of this slice.

## Local verification

`mise run backend:test` exercises the real HTTP contract and PostgreSQL with
controlled server time: durations 1/20/45/90/540, exact working-day ends, strict
14:00/14:07 starts, Berlin midnight, both DST transitions, weekends, shared
occupancy, unavailable links and privacy. Separate persistent-boundary examples
exercise concurrent exclusion and adjacency; concurrent **booking HTTP** requests
must be added with the confirmation operation in #28.

`mise run smoke` runs the real Rails/proxy/SDK application in Chromium, including
selection/Continue without reservation, unavailable direct links, stale form
links, keyboard activation, phone stacking/no horizontal overflow, and occupied
date/window empty states. Chromium's device zone is America/Los_Angeles to verify
that the display remains Europe/Berlin. A separate full-page Chromium run in
Pacific/Honolulu checks real navigation, calendar/form refresh, restored selection,
desktop columns and a 320-pixel phone viewport. The harness repeats normal scenarios
after restarting Rails and uses a separate fully occupied phase before hiding
offers. All resources are per-run isolated.

Run `mise run check` for the complete gate. Local results do not establish
external GitHub Actions success.
