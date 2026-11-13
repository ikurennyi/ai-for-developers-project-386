# Safe booking retry (#30)

The guest application generates a 256-bit random `attemptToken` before sending
Confirm booking through the generated SDK. An uncertain transport or server
failure preserves the immutable request, reviewed calendar snapshot and capability
in the current tab's session history. Retry explicitly resends that same attempt;
it never guesses whether a booking committed from public availability. Guest fields
are retained and locked until the uncertain attempt is resolved.

Like guest drafts and confirmations, the capability is absent from URLs,
`localStorage` and `sessionStorage`. The latter contains only the existing
history-generation marker, not recovery authority. Opening the form address with
`window.open` (including an opener that clones session storage) cannot recover the
booking or guest data. Success clears the attempt with the draft; a deliberately
later booking gets a new capability.

Rails hashes the capability with SHA-256. Inside the booking transaction, a
PostgreSQL transaction advisory lock serializes matching capabilities even before
the first insert. A unique digest index also protects persistent identity. A
committed retry returns the original booking before evaluating mutable publication,
meeting details, time or occupancy, so it cannot conflict with itself. An
uncommitted attempt still undergoes every normal booking check. Transaction rollback
releases both the attempt identity and occupancy. Calls without the optional
capability retain the original one-shot API behavior; malformed capabilities are
rejected rather than silently downgrading retry protection.

There is no public read endpoint, contact-information lookup, cookie-based guest
identity or shared-storage recovery token. Booking responses remain `no-store`,
and the existing token/name/email/notes log filters cover retry requests.

## Verification

- `booking_retry_spec.rb`: original committed response, changed/hidden offer and
  elapsed window, contact/capability privacy, malformed capabilities, OpenAPI.
- `concurrent_bookings_spec.rb`: three simultaneous independent PostgreSQL
  connections for both uncommitted and committed attempts; forced overlap at the
  persistent lock boundary; retry after an actual confirmation rollback.
- `frontend/e2e/booking-retry.mjs`, included in `mise run smoke`: forwards to real
  Rails, waits for a committed response, then drops only the browser response;
  checks the uncertain message, retained form, refresh, opener privacy, recovery
  of the original identifier and a separately intended next booking.

Run `mise run check` for these and the existing acceptance gates. Local results
do not establish external GitHub Actions status.
