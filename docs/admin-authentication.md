# Administrator access (#24)

There is exactly one administrator; no registration, recovery, password UI or
additional-account API exists. Public pages and `/api/v1/health` remain public.
Home, Links and Bookings currently provide the protected navigation shell;
their business features belong to the separate administration tickets.

## Initial configuration

After the README installation and database preparation, supply `ADMIN_USERNAME`
and a strong, unique `ADMIN_PASSWORD` to the **Rails server's environment**. There
are no default credentials. For local development, put them in the ignored
worktree-local `mise.local.toml` `[env]` section before starting services. Never
commit credentials or reuse another worktree's configuration.

The first login attempt provisions the singleton account atomically from this
configuration, storing only a salted PBKDF2-HMAC-SHA256 hash (600,000 iterations).
Missing or empty configuration fails closed with the same generic credentials
error. Once provisioned, PostgreSQL is authoritative: later restarts, migrations,
seeding or changes to the initial environment do **not** reset the password.
Keep persistent database storage and backups private.

Deploy through HTTPS on one origin for the frontend and `/api/v1` API. Preserve
the original host/protocol through a trusted reverse proxy. Do not enable
cross-origin credentialed CORS. Production cookies are `Secure`; development HTTP
is for loopback use only. See the release ticket for container delivery.

## Password rotation and revocation

Run this server-side command against the same database and Rails environment as
the running application. In Bash, prompt rather than putting the secret in shell
history or process arguments:

```bash
cd backend
read -r -s -p "New administrator password: " ADMIN_NEW_PASSWORD
echo
export ADMIN_NEW_PASSWORD
mise exec -- bundle exec rails admin:change_password
unset ADMIN_NEW_PASSWORD
```

Use `RAILS_ENV=production` in the server environment for production. The new
password must contain at least 12 characters. The command updates the hash and
deletes **all** sessions in one transaction. Login and rotation lock the same
singleton row, preventing an old-password login racing rotation from creating a
surviving session. No server restart is required, and the command never prints the
password. Update the initial secret in your secret manager too; its old value
cannot overwrite the persisted hash. A missing/short new password exits nonzero.

## Session and abuse protections

- A 256-bit random opaque token lives only in an `HttpOnly`, `SameSite=Strict`
  cookie scoped to `/api/v1/admin`, `Secure` in production. Only its SHA-256 digest
  is stored in PostgreSQL. No token/password is returned in JSON or browser storage.
- The browser cookie and server session expire **24 hours after login**, never
  after last activity. The server independently checks expiry, even if an expired
  cookie is manually replayed. Logout deletes its row immediately. Password
  rotation deletes every session.
- Authentication responses use `Cache-Control: no-store`. Unknown usernames,
  wrong passwords and absent initial configuration all return
  `Invalid username or password`; username checks still perform password hashing.
- Login admits **10 attempts per client IP per fixed 15-minute window**, including
  successful attempts. The eleventh returns `429` and `Retry-After` seconds.
  Blocked attempts do not extend the window. PostgreSQL row locks share the limit
  across processes and restarts. Configure trusted proxies correctly; clients
  must not control forwarded IP headers. Operators behind one NAT share a limit.
- Every administrative mutation, including login/logout, requires
  `X-Calendar-Request: 1`. Supplied Origin must match the request origin;
  cross-site Fetch Metadata is rejected. No CORS preflight permission is granted.
  This protects against login/logout and data-mutation CSRF as well as relying on
  the strict cookie.
- There is no automatic action replay after login. Only a validated internal
  `/admin` return target is used; ordinary Admin opens Home, logout opens login.
  Navigation checks the server, and the shell rechecks on focus/every 30 seconds
  to detect access revoked from another tab.

## Extending administrative features

Rails administrative controllers must inherit
`Api::V1::Admin::BaseController`, not `ApplicationController`; this supplies
authentication, no-store and mutation CSRF checks. Declare cookie authorization
and `401`/`403` errors in TypeSpec, then regenerate the SDK.

Frontend children of the `/admin` layout inherit the route guard. Use
`adminRequestHeaders` for mutation SDK calls. On a `401`, preserve an unfinished
form **only in sessionStorage in its current tab**, then call
`requireAdminLogin(router)`; after login restore that draft but require another
explicit Save/Delete/Publish. Never queue or automatically retry mutations.
The authentication ticket does not introduce the meeting-type/booking forms.

## Verification

`mise run backend:test` uses real disposable PostgreSQL and HTTP request/response
contract validation: generic failures, missing configuration, 24-hour absolute
expiry with activity and cookie replay, CSRF/no mutation on forbidden logout,
logout replay rejection, fixed rate threshold/reset, and the real server-side
rotation command across processes revoking multiple sessions.
Concurrent requests on independent database connections must admit exactly ten
attempts and reject the remaining requests.

`mise run smoke` retains the existing health/homepage Chromium test, adds a
generated-SDK navigation test, and starts a temporary real Vite application for
Playwright full-page navigation/reload, invalid login, protected-route return,
Home/Links/Bookings, logout and cross-tab revoked-session recovery. All processes
and databases use the existing isolated runner/cleanup. Schema preparation dumps
only into the runner's private temporary directory, never tracked sources.
`mise run check` also verifies contract reproducibility, lint/types, tests and
production build. Local success is not external Actions evidence.
