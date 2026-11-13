# Worktree-local development services (T5 / #7)

Install the [pinned toolchain](toolchain.md), provide a running Docker Engine,
then run `mise run install` for the frozen module dependencies and Chromium.
These lifecycle tasks do not install application dependencies; see
[README](../README.md) for the complete installation sequence.

## Configure each checkout separately

```sh
mise trust mise.toml
umask 077
mise exec -- ruby scripts/services.rb dev:env > mise.local.toml
# Edit mise.local.toml: choose THREE free, distinct ports for this worktree.
# Update the port in BOTH database URLs when changing POSTGRES_PORT.
mise trust mise.local.toml
mise run dev:validate
mise run dev:start
mise run dev:status
mise run dev:stop
```

Do not overwrite an existing local configuration with the template. It prints
new random database and initial administrator passwords on every invocation.
The template includes `ADMIN_USERNAME=owner` and `ADMIN_PASSWORD`; Rails provisions
the single administrator on first login. It includes no default shared password.
The suggested ports 3101/5101/5501 are examples, not automatic allocations. A
second worktree must use different ports (for example 3102/5102/5502) and its own
generated credentials/configuration.
The same variables may instead be exported in the invoking environment without
a local config. Secrets and runtime state are ignored by Git.

`WORKTREE_ID` is `wt-` plus the first 20 hex digits of SHA-256 of the canonical
absolute checkout path. The lifecycle requires this path-derived ID, the Compose
project `scaffold-${WORKTREE_ID}`, and database names containing the ID with
hyphens replaced by underscores. It validates both connection URLs against the
local Compose host, port, and credentials. `DATABASE_URL` names `POSTGRES_DB`;
`TEST_DATABASE_URL` must name a distinct worktree-local database. There is no
development-to-test fallback. This command prepares a persistent development/test
pair; independent test/smoke runners must add a per-run suffix to their own test
database names rather than sharing this pair across concurrent runs.

A path hash suggests an identity, not a guarantee that a port or existing resource
is safe. Explicit bind checks reject occupied ports without searching for another.
Compose containers, volumes, and networks carry the absolute-path ownership label
`dev.scaffold.worktree`; conflicting existing labels are rejected before mutation.
Compose has no fixed container name or externally shared volume/network.

## Commands and guarantees

| Command | Behavior |
| --- | --- |
| `mise run dev:env` | Print a local TOML template, without starting anything |
| `mise run dev:validate` | Validate configuration and check all three ports are currently free |
| `mise run db:up` | Start/reuse this checkout's PostgreSQL with the pinned standalone Compose; wait for final TCP health, not the init-only Unix socket (45-second deadline) |
| `mise run db:prepare` | Run `db:up`, then Rails `db:prepare` separately for development and the explicit test URL |
| `mise run db:seed` | Create missing initial published meeting types; reruns preserve administrator edits |
| `mise run dev:start` | Reject occupied application ports, prepare DBs, then start native `mise daemons` backend/frontend under pinned pitchfork |
| `mise run dev:status` | Show project, ports, Compose and daemon status; include recent logs for unready services; exit nonzero unless all three are ready |
| `mise run dev:stop` | Stop only the two named daemons in this project and its owned Compose PostgreSQL, retaining containers, networks and volumes |

Application readiness is HTTP (`/up` for Rails, `/` for Vite), not a fixed sleep;
native pitchfork checks have 45-second deadlines, with no automatic retries or
proxy activation. Subprocesses have an outer 90-second deadline. Vite receives
`--strictPort`; both servers bind loopback. Vite's `/api/v1` proxy configuration
is owned by T6, not this lifecycle implementation.

Native mise creates per-absolute-path daemon identities and state directories
(visible with `mise daemons ls --json`); pitchfork logs use those identities.
Rails uses `.services/rails.pid`; Rails temp/cache paths remain inside this
worktree's `backend/tmp`. The ignored `.services/environment.json` (mode 0600,
directory 0700) records the exact startup environment, including credentials,
so daemon processes, readiness, status and stop do not depend on a supervisor's
possibly stale environment. Lifecycle mutations take a per-worktree file lock.

Repeated `db:up` and `dev:stop` are safe. `dev:start` deliberately fails if the
application ports are already in use, including by an already-running stack.
A failed start stops its new app processes and stops PostgreSQL only when this
start brought it up; an already-running database is retained. Failed PostgreSQL
readiness similarly stops a newly started DB, without deleting its volume.
If startup races another listener after preflight, strict binding/readiness still
fails; there is no alternate-port fallback.

Stop uses saved settings, even after environment changes. Configuration changes
require stopping first and explicitly removing only `.services/environment.json`
before starting with new settings. Existing volumes retain their original database
credentials: changing a password in config does **not** rotate that database user's
password. Keep the credentials or perform an intentional PostgreSQL migration.
There is intentionally no destructive reset task. Do not use `down -v`, Docker
prune, global pitchfork stop, or shared cleanup as normal lifecycle operations.

## Tests and actual verification

```sh
mise run services:test
# Fresh dedicated checkout only; refuses existing state/volume, retains its data:
mise run services:fresh-test
# Prepare TWO dedicated checkouts at the implementation commit, install each
# checkout's frontend dependencies and create its local configuration as above.
# Both must initially have their dev services stopped; do not use someone else's
# active development worktree. This test starts/stops both and keeps DB data.
mise exec -- ruby test/services_integration_test.rb /absolute/worktree-a /absolute/worktree-b
```

The CLI tests reuse minitest 6.1.0 from the existing backend lockfile (install that
bundle first). They exercise missing configuration, numeric port collisions,
occupied-port errors, and secret-safe
malformed URL errors without Docker. The opt-in real tests check two concurrent
stacks, distinct identities/PIDs/state paths/containers/volumes/networks/databases,
HTTP readiness, healthy/unhealthy status, all three occupied-port failures, safe
stop, and data retention. A temporary **root local daemon override** runs a sleeping
frontend with a two-second readiness deadline; the test observes pitchfork exit
124, bounded failure, and cleanup. It restores the local file in `ensure` and
stops only these dedicated worktrees. It never modifies application configuration
or deletes database volumes. The retention probe uses an operational PostgreSQL
table, not application behavior or a mock backend.

Verified on 2026-11-11, macOS arm64 / Docker Engine 29.9.3, using
`isolated-dev-services` (3101/5101/5501) and `isolated-dev-services-peer`
(3102/5102/5502) beneath the approved OpenCode temporary directory. The native
daemon namespaces were `isolated-dev-services-ab6bd2c1302a049a` and the peer's
distinct path namespace; the Compose projects were independently path-derived.
All probes use the pinned PostgreSQL 18.3 image, mise 2026.11.6 and pitchfork 2.34.0.
Application lint/type/build/smoke and CI are outside this task's verification.
