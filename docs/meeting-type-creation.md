# Hidden meeting-type creation (#25)

After signing in with the existing [administrator access](admin-authentication.md),
open **Links**. It lists all published and hidden meeting types, publication
state, duration and their public addresses. **Create meeting type** opens a
separate form. Save creates a hidden draft and returns to Links; it never
publishes, chooses a replacement address or accepts a user-assigned identifier.
Publication and editing belong to separate tickets.

Name and address are trimmed only at their edges. Name is 1–100 characters;
description is optional, at most 2000 characters, with whitespace-only input
treated as empty. Duration is a whole number from 1 to 540 minutes. Address is
1–80 lowercase Latin letters/digits with single hyphens between nonempty parts.
Uppercase or malformed addresses are rejected, not normalized. The existing
PostgreSQL unique index covers hidden and published addresses; a concurrent
index collision becomes the same address-field error as an ordinary collision.

Save is disabled until its response arrives. Failures retain fields. Leaving a
dirty form asks before discarding it. Lost administrator access stores only this
form's draft in the current tab's sessionStorage, returns through login, and
requires another explicit Save. Confirmed departure or successful Save clears
the stored draft. No login operation replays a mutation.

## Local verification

`mise run check` passes locally with frozen dependencies and isolated PostgreSQL
18.3 resources. This is not evidence of external GitHub Actions.

- HTTP request/response contract tests cover authorization, CSRF, hidden-only
  creation, server-assigned IDs, normalization, inclusive limits, malformed JSON
  field types, arbitrary integer durations and collisions with both states.
- The race test uses distinct PostgreSQL backend PIDs. An uncommitted unique-index
  entry blocks both HTTP inserts after their validation SELECTs; rolling it back
  releases both writers. Exactly one receives 201 and the other 422 with a slug
  error, and authenticated listing contains exactly one hidden offer.
- The real Chromium application tests client validation before any HTTP mutation,
  server collision errors, offline failure/retry, latency-delayed disabled Save,
  persisted Links, public-list exclusion, Unicode boundaries, plain-text
  description rendering, discard/cancel, tab-local authentication recovery without
  replay, and a 375px form without horizontal overflow. No mock API is used.
- TypeSpec is authoritative; OpenAPI/SDK are regenerated and checked for drift,
  and the strict SDK consumer compiles both administrative operations.

Health, public-list, authentication, restart persistence and the pre-existing
gates remain enabled. No external secrets, push, PR or ticket closing is involved.
