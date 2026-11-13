# Reproducible Docker application (#36)

This is a loopback-only, single-origin HTTPS installation, not a public
deployment. Docker Engine, Docker CLI and standalone `docker-compose` are required.
The helper is Ruby standard library only. Use the pinned mise toolchain from
README, or Ruby 3.4.12 and standalone Docker Compose 5.7.0 directly.
The `docker compose` Desktop plugin is not the pinned project interface. Application dependencies
are installed inside the image from the independent backend/frontend lockfiles;
host npm installs, contracts generation and a local development configuration
are **not** needed to build or start it.

## Clean checkout

```sh
git clone https://github.com/ikurennyi/ai-for-developers-project-386.git
cd ai-for-developers-project-386
# Check out the desired implementation commit.
mise trust mise.toml
mise install
# Choose an unused port, different from every other checkout:
HTTPS_PORT=8443 mise exec -- ruby scripts/docker.rb setup
mise exec -- ruby scripts/docker.rb build
mise exec -- ruby scripts/docker.rb up
mise exec -- ruby scripts/docker.rb status
```

Open `https://localhost:8443`. Caddy creates a local CA, so the browser initially
warns about its certificate. For local testing, explicitly accept this local
certificate, or export/trust this project's CA according to your OS policy.
Never disable certificate verification for a public deployment. Production
cookies remain Secure; HTTP is not used as an authentication workaround.

`setup` exclusively creates ignored `.services/docker.env` (0600), with random
database, Rails signing and initial administrator secrets, username `owner`,
and the chosen port. It refuses to overwrite an existing file and checks the
port before creating it. Read that private file locally to obtain the initial
password; do not paste it into logs or issues. Keep it private and backed up.
No shared/public password is supplied in the image or configuration.
`POSTGRES_PASSWORD` must remain URL-safe (the generated hexadecimal value is).
`SECRET_KEY_BASE`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `POSTGRES_PASSWORD` and
`HTTPS_PORT` are required; there are no secret defaults.
The helper treats that private file as authoritative, overriding inherited
variables from other worktrees instead of accidentally reusing their credentials.

The app runs as a non-root user. Its entrypoint runs `rails db:prepare` and
`rails db:seed` before Puma, failing startup if migrations/initialization fail.
Seeds identify the two initial offers by stable internal keys, not editable
addresses. Repeated startup never restores edited names, durations, addresses,
descriptions or publication state. The configured administrator is provisioned
at first login; subsequent initial credentials do not overwrite the database.

The image contains built Vue assets and Rails, not host `node_modules`, `.git`,
local mise files, `.env` files, Rails encrypted credentials/master keys, runtime
state or database data. Frontend API requests use the same HTTPS origin.
Database and app ports are not published; only the HTTPS proxy binds loopback.
No email, video or external-calendar credentials or services are required.

## Persistence and password rotation

```sh
mise exec -- ruby scripts/docker.rb recreate
mise exec -- ruby scripts/docker.rb restart
mise exec -- ruby scripts/docker.rb stop
mise exec -- ruby scripts/docker.rb up
```

Both stop and app recreation retain the project's PostgreSQL named volume.
Types, bookings, snapshots, exact instants, occupancy, initialization identity,
administrator password hashes and sessions live in PostgreSQL, not the app
container filesystem. Back up PostgreSQL before upgrades; volume retention is
not a backup. Do not run concurrent migration/start operations on one project.
An existing PostgreSQL volume retains its database user's password. Editing
`POSTGRES_PASSWORD` alone does not rotate it: retain the original value or
perform an intentional database credential migration, never a volume reset.

Change the password without putting it in command arguments or shell history
(Bash; at least 12 characters):

```bash
read -r -s -p "New administrator password: " ADMIN_NEW_PASSWORD
echo
export ADMIN_NEW_PASSWORD
mise exec -- ruby scripts/docker.rb exec -e ADMIN_NEW_PASSWORD app bundle exec rails admin:change_password
unset ADMIN_NEW_PASSWORD
```

The transaction changes the hash and revokes **all** existing sessions, without
restarting the app. Update `ADMIN_PASSWORD` in the private initial configuration
too; changing that file alone does not rotate the persisted password.

## Isolation and diagnostics

The project name is `calendar-` plus a hash of the canonical checkout path,
distinct from development Compose resources. Containers, networks and volumes
carry checkout ownership labels; the helper refuses conflicting ownership before
operations. Another checkout must run its own setup with a different free port
and generated secrets. Never reuse/copy another checkout's private config.
Moving a checkout changes its identity: do not assume its old volume is reused.

```sh
mise exec -- ruby scripts/docker.rb logs
mise exec -- ruby scripts/docker.rb stop
```

Only this project is stopped. There is intentionally no volume deletion, reset,
prune or global cleanup command. Retain the `.services/docker.env` file and named
volumes for restart. A failed start may leave this project's containers for
diagnosis; stop them with the command above.

## Real acceptance

Install host test dependencies with `mise run install` (not required to run the
product), then run against this dedicated stack:

```sh
mise exec -- node test/docker_acceptance.mjs
mise exec -- ruby test/docker_setup_test.rb
# Export only committed HEAD into a fresh private directory; build without
# host dependencies/config, run the same acceptance, stop and retain its data:
HTTPS_PORT=8444 mise exec -- ruby test/docker_clean_checkout_test.rb
mise run check
```

The acceptance test uses this checkout's private configuration and HTTPS port,
creates a real guest booking, edits an initial type, recreates the app, checks
snapshots/instants/shared occupancy/initialization preservation, rotates the
administrator password and proves the old session is rejected. It leaves data
and the updated private password in this dedicated stack. Do not run against a
shared or valuable installation.

Local execution evidence is recorded separately below; it is not evidence of
external GitHub Actions, a public deployment, or completion of parent #22.

### Local evidence (2026-11-13)

- Red: the documented Compose configuration was absent, and Chromium could not
  connect to the application before delivery.
- macOS arm64, Docker Engine 29.9.3, Compose 5.7.0, pinned Ruby/Node,
  PostgreSQL 18.3; no email/video/calendar services or credentials.
- Worktree project `calendar-690a3057fc782cbdced8`, HTTPS port 8466:
  real Vue booking/confirmation, browser login/edit/hide, authenticated booking
  visibility, app restart, forced recreation and rotation acceptance passed.
- Committed `9b6da13` (including integration tip `beb975f`) was exported using
  `git archive`, without `.git`, host dependencies, ignored files or local
  configuration. Its separate project `calendar-b9d930f465c6c3f9e2b6`, port 8467,
  built/started successfully and passed the same complete acceptance.
  Both projects were stopped, retaining their separate PostgreSQL volumes and
  private configurations. The clean export remains under
  `.services/docker-clean-8d24e7d3b73b` for inspection/restart.
- A further clean export of `f1d2bff`, including integration `811482c`
  (administrator form recovery), passed on port 8468 in project
  `calendar-6413dc5e0c69af7b8c72`. This run also stopped/started **all** services
  while deliberately injecting a different caller `POSTGRES_PASSWORD` on each
  lifecycle command. Private configuration remained authoritative and all
  persistence/rotation checks passed. Its stopped, retained export is
  `.services/docker-clean-ed1b8d8bc043`.
- After integration `40e855c` (booking conflict recovery), clean commit `0e943dd`
  passed the same complete Docker acceptance on port 8469, project
  `calendar-5040a62755f0bfe7e22a`; stopped data/configuration are retained in
  `.services/docker-clean-abd4550c0a84`.
- Final pre-handoff integration baseline:
  `8e095eec02fbca7e007a8e133045f2ea90a6142d`. Clean delivery commit `92af545`
  includes safe booking retry (`booking_attempts` and consumed-attempt
  tombstones), conflict recovery, permanent deletion and administrator form
  recovery boundaries. It built/migrated from empty storage and passed the
  complete acceptance on port 8470, project `calendar-6fb204a9c45ecdea3eb2`.
  This includes actual HTTP overlap rejection after restart/recreation and
  full-stack stop/start, not just an unavailable display. HTTPS readiness is
  health-checked before startup returns. All its services are stopped; its
  private export and persistent storage remain at
  `.services/docker-clean-7856fd688da9`.
- The earliest pre-hardening test stack had inherited a caller database password
  before private-file precedence was added. A later full restart exposed that
  mismatch. Only that dedicated database's role password was reconciled with its
  private file, preserving records; no volumes or other worktrees were modified.
  The clean export above verifies startup/restart without that historical state.
- HTTP assertions compare booking snapshots and exact start/end instants before
  and after restart/recreation, retain edited hidden initial types without
  duplicate seed offers, and verify occupancy through another published type.
  Rotation rejects the old password/session and accepts a new login without
  changing saved data. Chromium runs in Honolulu to exercise Berlin-independent
  device settings, with certificate bypass confined to this local test.
- Setup CLI probes passed: invalid/occupied ports fail before writing secrets,
  generated credentials have mode 0600, and repeated setup cannot overwrite them.
- A separate read-only, network-disabled run of the built image confirmed a
  non-root UID and absence of Git/worktree state, local Bundler configuration,
  host npm dependencies and Rails credential/master-key files.
- Full `mise run check` passed: contract generation/drift/SDK typing, all static
  gates, 90 PostgreSQL RSpec examples, jsdom, real Chromium/application smoke and
  production build; a repeat passed unchanged. After merging `811482c`, the
  aggregate passed again with 91 RSpec examples and administrator form-recovery
  browser acceptance. Final baseline `8e095ee` passed the entire aggregate with
  **102 PostgreSQL RSpec examples, 0 failures**, all Chromium/application scenarios
  (including retry and recovery), and the production build.
  Existing npm pins still report 13 moderate frontend
  advisories; no dependency upgrade or audit-fix was performed.
- External GitHub Actions/Hexlet, public deployment and parent-spec completion
  remain unconfirmed. The protected Hexlet workflow was not changed.
