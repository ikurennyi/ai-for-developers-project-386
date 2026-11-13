# Meeting type management (#26)

Administrator Links lists hidden and published types. Edit opens a separate form
with name, description, whole-minute duration and public address; the system ID
is never editable. Creation and editing share their validation and form.
Successful Save returns to Links; a failed Save retains fields and field errors.
Save does not publish or hide.

Publish, Hide and republish are explicit actions. The button is disabled during
the request and the previous state remains visible until server success. Failure
keeps that state, explains the error and allows another explicit attempt.
Copy link writes the current `/book/:slug` absolute URL to the clipboard; a denied
clipboard permission reports failure rather than claiming success.

## Contract and persistence

TypeSpec owns these authenticated, non-cacheable operations; Vue calls the
generated SDK:

- `GET /admin/meeting-types/:id`: load details, including hidden types.
- `PUT /admin/meeting-types/:id`: save the four editable fields only, with the
  creation rules and English field errors. Missing description becomes empty.
- `PUT /admin/meeting-types/:id/publication`: explicitly set a JSON boolean
  `published`. Repeating the desired state is safe.

Writes require the administrator cookie and `X-Calendar-Request: 1` with the
existing same-origin checks. Invalid input is 422; absent IDs are 404;
unauthenticated requests are 401.

PostgreSQL's unique address index arbitrates concurrent saves, including hidden
offers. A losing save returns a field error without changing its other details.
Changing an address immediately releases the old address: there is no alias or
redirect. It returns the same unavailable response as any nonexistent address
until another type explicitly reuses it.

Details and publication updates only modify the meeting type. They never rewrite
booking snapshots or exact intervals and never delete occupancy. Availability
continues using shared occupancy regardless of publication. Booking creation and
creation-time snapshots belong to #28, not a second implementation here.
Both management mutations lock the meeting-type row, coordinating with the
booking confirmation boundary and returning details read under that lock.

## Local verification

`mise run backend:test` checks real HTTP/OpenAPI/PostgreSQL behavior, including
editing validation, authorization, separate publication, old-address reuse,
hidden/nonexistent equivalence, retained shared occupancy and two independent
concurrent address updates.

`mise run smoke` includes full-page Chromium acceptance for editing, current-link
copying, public visibility, hide/republish, retryable failure and pending states.
Offline and real-network latency exercise errors and pending behavior without
substituting fake API responses. `mise run check` also runs generated-contract
reproducibility, strict SDK consumption and all existing gates.

These are local checks, not confirmed external GitHub Actions.
