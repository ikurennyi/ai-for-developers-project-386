# Booking confirmation (#28)

The guest form shows the reviewed meeting, host Alex Morgan, date, start/end,
duration and Europe/Berlin. Only **Confirm booking** writes data. Pending
confirmation disables inputs and submission. Name, email and optional notes
have adjacent English errors and retain input after rejection. Guest content
is rendered through Vue text interpolation, never HTML.

`POST /api/v1/meeting-types/:slug/bookings` is owned by TypeSpec and consumed
through the generated SDK. It accepts the exact start instant, reviewed name,
description and duration, and guest details:

- Name: ECMAScript whitespace trim; 1–100 Unicode code points.
- Email: required, at most 254 Unicode code points, ASCII email local-part
  characters and dot-separated domain labels; no surrounding whitespace normalization.
- Notes: optional, at most 2000 Unicode code points, preserved verbatim.

Both client and server enforce the same rules. Server errors are `422 validation`,
`404 Meeting type unavailable` (hidden/nonexistent/old addresses), or `409` with
`details_changed`, `invalid_interval`, or `occupied`. Responses are `no-store`.
Malformed guest field types are validation errors, not server exceptions.

The transaction locks the current published meeting-type row `FOR SHARE`:
confirmations can run together, while editing/hiding cannot change the reviewed
terms during creation. It rechecks the current Berlin schedule/window, grid,
strictly future start and shared availability. Booking and occupancy commit
together, retaining the type association, exact instants and name/description/
duration snapshots. The existing PostgreSQL half-open GiST exclusion constraint
is the final concurrency authority. Exclusion violations return `occupied`;
known-rolled-back exclusion deadlocks receive bounded transaction retries.
Server time is checked again after potentially waiting inserts, before commit.

Success displays saved data, “This meeting is scheduled”, “No confirmation email
will be sent.” and Book another meeting. There is **no public booking GET** or
guest-information lookup. The creation response is retained only in the confirming
tab's session history; refresh does not POST again or expose a booking by identifier.
See [guest navigation and privacy](guest-navigation.md).

## Boundaries and verification

Tab-local draft/success refresh persistence is implemented in #29; stable logical
attempt identity and uncertain-result recovery belong to #30; advanced conflict/changed-detail
recovery to #31. This slice reports distinguishable failures without automatically
selecting a replacement time or accepting changed terms. Future authenticated
deletion must delete booking and occupancy together; deleting neither is the
only public behavior.

`mise run backend:test` uses real PostgreSQL and HTTP request/response contracts.
Concurrent requests use independent database connections, held at their INSERTs
by an external PostgreSQL table lock until both reach the write boundary.
Tests cover exactly one overlapping success, partial/nested/containing/identical
overlaps, hidden-type occupancy, the explicit 10:00–10:20 / 10:15 / 10:30 examples,
exact adjacency after 10:00–10:30, validation limits, snapshots, stale terms and
time advancing while an INSERT waits. `mise run smoke` exercises validation,
pending submission, plaintext success and shared occupancy through real Chromium,
Rails and the SDK, including a fresh Rails process with the same database.
Full local gate: `mise run check`; no external Actions result is implied.

### Overlap-test sensitivity evidence (#49)

Rule: bookings for different meeting types share one half-open occupancy calendar;
the API must reject partial, nested, containing and identical overlaps with `409`,
while allowing adjacency. The protecting request example is
`Booking confirmation shares 10:00–10:20 occupancy across types, rejects every
overlap shape and allows 10:30` in `backend/spec/requests/bookings_spec.rb:109`.

Command: `mise run backend:test` (real PostgreSQL and HTTP request specs).

- **Red, intentional local mutation only:** 103 examples, 26 failures. The named
  example failed: after removing application overlap detection and the PostgreSQL
  exclusion constraint from the test schema, a second type's partially
  overlapping booking was created with HTTP `201` instead of the expected `409`.
- **Green, after restoring the implementation, migration and schema:** 103
  examples, 0 failures.

An initial mutation run was not valid red evidence: it removed the constraint
from the migration but not `backend/db/schema.rb`, which supplies the test
database schema. The target remained protected by PostgreSQL. The successful red
run removed both defenses in the isolated `test/overlap-sensitivity` worktree;
the intentionally broken files were restored before the green run and are not
part of this change.
