# Administrator form recovery boundaries (#35)

The approved seams are browser → real application and HTTP API → PostgreSQL.
`mise run smoke` includes `frontend/e2e/admin-form-recovery.mjs`, using real
Chromium, Rails, PostgreSQL and authentication without API response mocks.

The browser scenario exercises recovery after server-session revocation, login
refresh, original-route/input restoration, no Save/Publish replay, route-warning
cancellation/discard, history navigation, opener-tab isolation and a separately
authenticated browser context. The separate context opens the original recovery
login URL and reaches an empty form; the original tab still recovers all fields.

Native document navigation is tested independently of Vue Router: dismissing a
real Chromium `beforeunload` dialog preserves the form, while accepting reload
discards every field of a previously recovered draft. This regression initially
failed because recovery history survived confirmed reload. Cleanup now happens
on `pagehide`, not `beforeunload`, so canceling departure does not discard data.

## Exact expiry coverage and remaining limitation

The browser scenario invalidates a real session through logout; it does **not**
claim that 24 hours elapsed in Chromium. The existing request specs
`backend/spec/requests/admin_authentication_spec.rb` and
`backend/spec/requests/admin_form_recovery_spec.rb` control server time and prove
absolute 24-hour expiry, expired-cookie replay rejection, unchanged persisted
meeting types, and explicit post-login mutation.

The browser harness starts a separate Rails process with no controllable server
clock. Browser clock changes do not advance Rails time. A combined timed-expiry
browser scenario is therefore still unimplemented: no arbitrary wait, shortened
production lifetime, authentication bypass or remotely writable clock endpoint
was introduced. Delete recovery coverage belongs to #34.

Run `mise run check` for all local acceptance gates. Local results do not
establish external GitHub Actions success.
