# #22 acceptance traceability — final-review follow-up

This is code-review remediation and acceptance-gap preparation, **not execution
or completion of dependency-blocked #38**. #22 remains normative. No parent or
historical issue is closed by this document.

Baseline: merged PR #39, `f44e860d93db56898a645dbba43838ed2909d065`.
The tables map every group in #22's **Testing Decisions**, in their original
order, to executable assertions. File references identify scenarios, not an
assertion of exhaustive input combinations.

## Boundaries and execution

- `scripts/smoke.rb` runs Chromium against real Rails, PostgreSQL and the generated
  SDK, including full-page Playwright scenarios. Transport delay/abort simulates
  failures; successful API data is never fabricated.
- `backend/spec/requests/` and `backend/spec/integration/` run on disposable real
  PostgreSQL 18.3. Request contracts use `backend/spec/support/openapi_contract.rb`
  to validate requests and responses, including negative responses. Deliberately
  schema-invalid requests validate only the response.
- `test/fixtures/calendar_boundary.ru` uses Rails' existing server `--config`
  interface and ActiveSupport's existing time helpers in a dedicated test
  process. It refuses non-test environments; there is no production initializer,
  HTTP test endpoint, public clock setting or authentication bypass.
- Browser fixture absence for Links is created only in the runner's disposable
  database, after earlier scenarios. It is not a meeting-type deletion feature.
- Full gates: `mise run check`. Additional Compose/delivery checks:
  `mise run services:test`, `mise run ci:validate`,
  `mise run ci:database-test`, `mise run smoke:test`,
  `mise exec -- ruby test/docker_setup_test.rb`, and the clean-export command in
  [Docker acceptance](docker.md#real-acceptance).

## Browser acceptance groups

Paths below are relative to `frontend/`.

| #22 group | Concrete test references and assertions |
| --- | --- |
| Real application, routing, refresh and tabs | `browser/smoke.spec.ts`; `e2e/calendar-navigation.mjs`, `e2e/guest-draft.mjs`, `e2e/admin-navigation.mjs`, `e2e/admin-form-recovery.mjs`: mounted/full-page application, real HTTP, reload, Back and independent tabs. |
| Homepage, all published offers, direct/unavailable links, initial calendar, date/month boundaries, no premature creation | `browser/smoke.spec.ts`, `browser/calendar.spec.ts`; `e2e/calendar-navigation.mjs`; **`e2e/calendar-boundary.mjs`**: deterministic December 2026 → January 2027 → December navigation, bounded previous/next, today, weekend and out-of-window disabled cells. Availability before/after selection/Continue remains unchanged. |
| Form validation, summary, plain text, creation, pending submission, success/no email/another meeting | `browser/booking.spec.ts`, `e2e/guest-draft.mjs`; **`e2e/calendar-boundary.mjs`** completes a real keyboard-only booking with Berlin summary and no-email notice. Existing booking tests assert text-like HTML stays plain text, English field errors retain input and pending submission is disabled. |
| Draft Back/refresh, stale links, conflict, changed details, hidden offer, uncertain result | `browser/booking-recovery.spec.ts`; `e2e/guest-draft.mjs`, `e2e/booking-retry.mjs`: independent name/description/duration changes, occupied/hidden recovery, real committed response loss and interrupted JSON, stable retry after refresh. |
| Personal data absent from URLs/availability; private success and refresh | `e2e/guest-draft.mjs`, `e2e/booking-retry.mjs`: opener/new browser cannot recover private details; no private capability in shared storage; refresh does not create again. `browser/calendar.spec.ts` and HTTP availability tests check public interval shape. |
| All public empty states; phone, keyboard, labels, focus, non-colour statuses | `browser/smoke.spec.ts`, `browser/calendar.spec.ts`: no types/date selection/fully occupied date/window, explicit Available/Unavailable, disabled controls, calendar stacking. `e2e/calendar-navigation.mjs`: 320px calendar overflow. **`e2e/calendar-boundary.mjs`**: Tab/Enter/typing only from calendar through success and Book another meeting; actual `:focus-visible` and nontransparent ≥2px rendered outline; selected `aria-pressed` and thick border; labelled fields; 320px summary/form stacking, success block order and no horizontal overflow. |
| Login/logout, protected return, expiry draft/no replay, admin navigation/privacy | `browser/admin.spec.ts`; `e2e/admin-navigation.mjs`, `e2e/create-meeting-type.mjs`, `e2e/admin-form-recovery.mjs`, `e2e/booking-history.mjs`: real revoked session recovery, original-tab form retention, no Save/Delete/Publish replay, guest text unavailable after logout. Absolute lifetime is controlled at HTTP. |
| Type validation, separate publication/copy/Save/leave, publication failure, all list states, history ordering/pages | `e2e/create-meeting-type.mjs`, `e2e/manage-meeting-types.mjs`, `e2e/admin-form-recovery.mjs`, `e2e/admin-home.mjs`, `e2e/booking-history.mjs`: validation/retained failed fields, native leave warning, real clipboard, pending/server-confirmed publication, offline failure, Home/Bookings states, Upcoming/Past order and pagination. **`e2e/links-states.mjs`** adds real empty Links, held loading transport, aborted error, Retry reaching Rails and ASCII/Unicode description form/server parity. |
| Delete review/cancel/failure/success/page recovery | `e2e/admin-home.mjs`, `e2e/booking-history.mjs`: dialog includes saved meeting/date/time/guest, cancel and failure retain record, server success removes it, final-page fallback and fully empty list; expired login does not replay deletion. |

## HTTP API and real PostgreSQL acceptance groups

Paths below are relative to `backend/spec/`.

| #22 group | Concrete test references and assertions |
| --- | --- |
| Every operation's request/response contract, negative/auth/conflict | All feature `requests/*_spec.rb` use `support/openapi_contract.rb`; `requests/health_spec.rb` includes bad media/body/status validation probes. TypeSpec distinguishes validation, occupied interval, changed details, unavailable type and unauthenticated access. |
| Independent validation, protected operations, generic login, limits, 24h absolute expiry/logout/rotation | `requests/admin_authentication_spec.rb`, `requests/admin_password_rotation_spec.rb`, `requests/admin_meeting_types_spec.rb`, `requests/manage_meeting_types_spec.rb`, `requests/bookings_spec.rb`, `requests/admin_bookings_spec.rb`. Includes intervening activity/cookie replay, concurrent login attempts, separate-process password rotation. **New description regression** POSTs and PUTs the full ECMAScript whitespace set, >2000 ASCII/U+FEFF/mixed whitespace empties, exact nonempty preservation, and U+0085 (not JS trim whitespace). |
| Today +13, weekends, midnight, grid, strictly future, end-at-18:00; 1/20/45/90/540-minute types | `requests/availability_spec.rb`, `requests/bookings_spec.rb`, `requests/admin_meeting_types_spec.rb`, `requests/manage_meeting_types_spec.rb`: window count, inclusive durations/integer/range rejection, current-date transitions and no day overflow. |
| Explicit last starts 17:30/17:15/16:30; 14:00/14:07; adjacency and overlap shapes | `requests/availability_spec.rb`, `requests/bookings_spec.rb`, `integration/occupancy_spec.rb`: literal expected Berlin examples, adjacency succeeds; partial, nested and full overlaps fail via PostgreSQL exclusion constraint. |
| DST working hours, stored instants and device-zone independence | `requests/availability_spec.rb`, `requests/bookings_spec.rb`, `requests/meeting_type_booking_invariants_spec.rb`: spring/fall transitions and unchanged stored instants; browser contexts use Los Angeles/Honolulu. |
| Truly concurrent overlaps across types and duplicate addresses | `requests/concurrent_bookings_spec.rb`, `requests/admin_meeting_type_concurrency_spec.rb`, `requests/meeting_type_edit_concurrency_spec.rb`: separate connections/PIDs blocked at actual DB locks, exactly one winner, 201/409 or 422, persistent unique/exclusion indexes. |
| Committed lost-response retry, concurrent retries, uncommitted attempt once | `requests/booking_retry_spec.rb`, `requests/concurrent_bookings_spec.rb`: same logical attempt returns original booking, concurrent new/committed attempts, no self-conflict/duplicate; consumed deleted attempts cannot recreate or disclose. Browser adds actual response loss. |
| Commit-boundary window/time/publication/details | `requests/concurrent_bookings_spec.rb`, `requests/meeting_type_booking_invariants_spec.rb`: advance time while actual insert waits; start/midnight rollback; independent edit/hide waits around the shared offer lock; no stale terms silently accepted. |
| Snapshots after edits, hidden shared occupancy, deletion eligibility/failure atomicity | `requests/meeting_type_booking_invariants_spec.rb`, `requests/manage_meeting_types_spec.rb`, `requests/admin_bookings_spec.rb`: original snapshots/instants after edits/hide, common occupancy, release only eligible intervals; PostgreSQL-refused deletion preserves booking and occupancy. |
| Upcoming/Past end boundary/order/ongoing/pages/distant bookings | `requests/admin_bookings_spec.rb`, `requests/admin_home_spec.rb`: end == now is Past, ongoing is Upcoming, both sort directions, pagination, dates beyond creation window. |
| Repeat initialization and restart persistence | `requests/meeting_types_spec.rb`: rerun seeds preserves edits/publication and immutable initial identities. `scripts/smoke.rb` restarts Rails and compares offers; `test/docker_acceptance.mjs` additionally compares full booking/snapshot/occupancy persistence across restart/recreation/full stop-up. |

## Contract and Docker acceptance groups

| #22 group | Concrete test references and assertions |
| --- | --- |
| Reproducible generation/drift/strict consumer/full aggregate | `contracts/scripts/check.mjs`, `contracts/test/sdk-consumer.ts`, `mise run check`: two generations, byte/file-list comparisons, strict SDK consumer, existing health and all nine gates. No generated artifacts or dependency pins changed by this follow-up. |
| Clean-checkout documented Docker, real booking/admin | `test/docker_clean_checkout_test.rb` archives **committed HEAD**, rejects host dependency/config presence, runs documented setup/build/up and `test/docker_acceptance.mjs`. `scripts/docker.rb` now uses pinned standalone `docker-compose`, never the Desktop plugin. |
| Same storage recreation preserves edited types/snapshots/occupancy | `test/docker_acceptance.mjs`: compares saved JSON/instants, hidden offer occupancy through another type and actual overlap POST 409 after restart/recreation/full stop-up. Volume/config retained. |
| Server password change revokes sessions | `test/docker_acceptance.mjs` executes the documented server command; old password/session rejected and new login accepted. `requests/admin_password_rotation_spec.rb` independently covers persistent revocation. |
| No live email/video/calendar dependency | `compose.application.yml` needs only app/PostgreSQL/Caddy and local generated secrets; browser checks no-email notice. No integration credentials used. |
| Local and external evidence separated | Local execution record below. External release/Actions status is supplied context, not inferred from local gates and not independently altered here. |

## Review finding dispositions

1. **Compose interface:** use standalone pinned `docker-compose` for restart and
   every helper invocation; documentation no longer requires a Desktop plugin.
2. **Deletion mutation boundary:** `DeleteBooking.vue` imports
   `adminRequestHeaders`, matching other SDK mutations.
3. **Description U+FEFF:** normalize only whitespace-only descriptions before
   length validation using the name/address ECMAScript trim set. Do **not** trim
   nonempty descriptions, lowercase slugs, collapse interior whitespace, or use
   a broader Unicode blank set. HTTP create/edit and real form tests cover parity.
4. **Native interval lookup:** `CalendarAvailability#interval_at` checks one
   native start/date/grid/duration, sharing native occupancy computation with
   serialization. Confirmation no longer builds/flattens fourteen-day JSON or
   reparses timestamps under the offer lock. Existing HTTP/concurrency/DST
   assertions remain the behavioral safety net.
5. **Tab persistence duplication:** `frontend/src/tabHistory.ts` shares only
   generation validation and history persistence. Storage keys, exact invalidation
   generations, serialization, guest retry/confirmation and administrator
   retain/discard/navigation policies remain unchanged. Existing full-page
   refresh/Back/expiry/opener/privacy scenarios exercise those policies.

## Execution record and honest limits

Local macOS arm64 verification on 2026-11-13, with the frozen/pinned toolchain.
Earlier baseline verification is not substituted for a run of these changes.

- The regression was red before the model change: 103 PostgreSQL examples,
  one failure preserving mixed whitespace ending in U+FEFF instead of `""`.
- Frozen installation succeeded; existing frontend pins report 13 moderate npm
  advisories. No dependency upgrade/audit-fix or external/shared secret changes.
- Full local `mise run check` passed, then passed on repeat, and passed again
  after the verification-harness repairs below: **103 real PostgreSQL examples,
  zero failures**, two jsdom tests, all real browser scenarios (including the
  new boundary/keyboard/phone/Links assertions), contract reproducibility/strict
  consumer, lint/format/types and production build. Normal/restarted browser
  fixture passes retain 10 passed / 2 intentionally inapplicable tests skipped;
  occupied/empty fixtures run their applicable scenarios separately.
- `mise run services:test`: 4 runs / 14 assertions, zero failures.
  `mise run ci:validate`: workflow 2 runs / 23 assertions and release policy
  2 runs / 29 assertions, zero failures. Docker setup CLI probes passed.
- `mise run ci:database-test` passed after two pre-existing harness problems were
  exposed and repaired: directory symlinks are now snapshotted as links rather
  than read as files (their tracked destinations are still hashed); the
  intentional stopped-server probe targets the real SDK health assertion, with
  an explicit “API unavailable” diagnostic, instead of burying it under unrelated
  feature failures. Normal smoke still runs all scenarios. The CI-service check
  verified parallel independent gate databases, all intentional failure modes,
  full aggregate success, unchanged source/index snapshots and SQL cleanup
  without damaging the borrowed database service.
- `mise run smoke:test` passed: two successful independent parallel application
  runs, actual stopped-server/after-readiness/timeout failures, bounded cleanup,
  unique database/container identities and an untouched unrelated listener.
- Clean tracked-files-only Docker export of product-fix commit **`cf19069`**
  built and passed the documented complete acceptance using standalone Compose
  5.7.0: real booking/admin edits, restart/recreation/full stop-up, snapshot and
  instant preservation, shared HTTP overlap rejection, seed preservation and
  server password rotation rejecting old credentials/sessions.
  HTTPS **51299**, project **`calendar-a0dc4b350d18b5a75d12`**. All its services
  are stopped; private config and persistent data remain in this worktree at
  `.services/docker-clean-2a521696b8fd`.
- Full logs are retained in the supplied private `calendar-22-context` directory:
  `fixes-red.log`, `fixes-backend-green.log`, `fixes-check.log`,
  `fixes-check-repeat.log`, `fixes-check-final.log`, `fixes-docker.log`,
  `fixes-services.log`, `fixes-ci.log`, `fixes-ci-database-final.log`,
  `fixes-smoke-isolation.log`, and `fixes-browser-failure-probe.log`.
  Initial failing harness/fixture iterations remain separately recorded; their
  ephemeral resources were cleaned, not confused with retained Docker delivery
  data. The first Rack fixture iteration required `extend`, not `include`, in
  Rack::Builder; the corrected real process passed all subsequent runs.
- Browser retry tests deliberately lose a committed response; uncommitted and
  concurrent retry proofs are at HTTP, not a separate browser timing fixture.
- Ordinary opener/new-tab/new-browser privacy is tested. Browser-vendor
  “duplicate tab” cloning of complete session history is not claimed.
- There is no claim of exhaustive malformed JSON/media fuzzing, every assistive
  technology/device, or a public production deployment.
- Supplied external status: main release-please rerun succeeded; release PR #40
  was created and its CI was running. No release/tag exists yet. #37 remains open
  and blocks #38; this follow-up does not start, claim or close #38.
- No push, PR, merge to main, tracker mutation, protected Hexlet workflow change,
  original-checkout edit, subagent or external secret/provisioning action.
