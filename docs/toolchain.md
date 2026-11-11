# Toolchain and command interfaces

Pins and isolation agreement originating in #3, under
[the scaffold specification](../SPECIFICATION.md). For the implemented full
workflow, follow [README](../README.md); historical verification below is T1-only.

## Pinned tools

Use mise **2026.11.6** (bootstrap installer/release version); `min_version` in
`mise.toml` is a compatibility floor, not an exact self-version installer.
Install that exact release from <https://github.com/jdx/mise/releases/tag/v2026.11.6>.
The project tools are pinned in `mise.toml`: Ruby 3.4.12, Node 24.22.2 (LTS),
hk 2.12.0, Pkl 0.33.0 (hk configuration), pitchfork 2.34.0, vacuum 0.39.3,
Docker CLI 29.9.3, and standalone Docker Compose 5.7.0.
Experimental mise features are explicitly enabled for daemons.

Additional pins, to be preserved by their implementing owners:

| Component | Pin | Owner |
| --- | --- | --- |
| Rails generator and backend gem | 8.1.4.1 | T3: backend Gemfile and lockfile |
| Bundler | 4.0.22 | T3: `BUNDLED WITH` in backend lockfile |
| npm (ships with this Node) | 11.19.1 | T2/T4/T9: each package's `packageManager` |
| Official create-vue generator | 3.24.0 | T4: explicit `npm exec --package=create-vue@3.24.0` |
| PostgreSQL (dev and CI) | 18.3 | T5/T9: same image below |

Use `postgres:18.3-alpine@sha256:54451ecb8ab38c24c3ec123f2fd501303a3a1856a5c66e98cecf2460d5e1e9d7`
for Compose and the CI service. Docker Engine 29.9.3 was verified locally;
provision a compatible engine separately (mise installs the client, not a VM/daemon).
The pinned standalone command is `docker-compose`; `docker compose` may resolve
an unpinned Desktop plugin and is not the project interface.

TypeSpec, its emitter, Hey API and application/test dependencies are pinned with
their actual compatibility checks and lockfiles by T2/T3/T4/T7/T9. Do not choose
floating generator versions when implementing those tasks.

## Toolchain bootstrap

From the task worktree, with the pinned mise on PATH:

```sh
mise --version
mise trust mise.toml
mise install
mise exec -- gem install bundler -v 4.0.22 --no-document
mise exec -- gem install rails -v 8.1.4.1 --no-document
mise exec -- rails _8.1.4.1_ --version
mise exec -- npm exec --yes --package=create-vue@3.24.0 -- create-vue --version
```

`mise install` installs tools only, not application dependencies. It may also
install tools from the user's global mise configuration; these are not project
requirements. Use `mise exec -- ...` without assuming shell activation.
Application dependency installation is now `mise run install`: frozen Bundler
and independent `npm ci` in `contracts/`, `frontend/`, `tooling/`, plus Chromium.
Generator version checks above are optional provenance checks, not app setup.
Never run npm install at the repository root.

## Implemented command contracts

These interfaces are implemented by their listed owners; lifecycle commands
are documented in [development services](dev-services.md), and aggregate
installation/checks in [checks](checks.md). Calling a missing
task must fail; do not add successful echo/no-op placeholders. Install/lifecycle
tasks may mutate dependencies or runtime state, but checks must not fix or stage
source files. Every failure must propagate a nonzero exit status.

| Root interface | Contract | Implementing owner |
| --- | --- | --- |
| `mise run install` | Reproducibly install all module dependencies from lockfiles | T8 |
| `mise run db:up` | Start this worktree's Compose PostgreSQL; bounded readiness | T5 |
| `mise run db:prepare` | Prepare development/test databases via Rails | T5 |
| `mise run dev:start` | Start Rails/Vite with `mise daemons` and pitchfork; fail on occupied ports | T5 |
| `mise run dev:status` | Show this worktree's database and daemon status, ports, logs on failure | T5 |
| `mise run dev:stop` | Stop only this worktree's daemons/Compose services; retain data | T5 |
| `mise run contracts:generate` | Compile TypeSpec to OpenAPI 3.0 and generate Fetch SDK | T2/T6 |
| `mise run contracts:check` | Compile/lint and compare temporary regenerated artifacts, without rewriting tracked files | T2/T6 |
| `mise run backend:lint` / `backend:test` | RuboCop without fixes / RSpec with real PostgreSQL | T3 |
| `mise run frontend:lint` / `frontend:format` | ESLint / Prettier check, no writes | T4 |
| `mise run frontend:typecheck` / `frontend:build` | Strict vue-tsc / production build | T4 |
| `mise run frontend:test` | Vitest tests (no mocks pretending API success) | T4/T7 |
| `mise run smoke` | Temporary isolated PostgreSQL/Rails/Vite + Chromium, readiness/timeout and cleanup on success/failure | T7 |
| `mise run check` | All specification gates, no dependence on running dev daemons | T8 |

Module owners may initially supply module-local commands; the listed root aliases
are added sequentially by the root-config owner. `check` must not become green
before every mandatory gate exists and passes. `dev:stop` must not remove volumes
or invoke global pitchfork/docker cleanup. Destructive database deletion requires
an explicit separate action; it is not part of normal stop/check.

## Environment and isolation agreement

T5 implements validation and loading of these variables from ignored
`mise.local.toml` or the invoking environment. No secrets belong in tracked config.

| Variable | Meaning |
| --- | --- |
| `WORKTREE_ID` | Required unique lowercase Compose-safe identifier per absolute worktree path |
| `COMPOSE_PROJECT_NAME` | `scaffold-${WORKTREE_ID}`; never a shared fixed project name |
| `BACKEND_PORT` | Explicit Rails loopback port; example 3101 |
| `FRONTEND_PORT` | Explicit Vite loopback port; example 5101, strict-port mode |
| `POSTGRES_PORT` | Explicit host loopback PostgreSQL port; example 5501 |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | Worktree-local database credentials |
| `POSTGRES_DB` | Worktree-specific development database name |
| `DATABASE_URL` | Authoritative Rails connection URL; CI supplies its service URL |
| `TEST_DATABASE_URL` | Distinct test connection; runner exports this as `DATABASE_URL` with `RAILS_ENV=test` |

Example ports are not defaults or reservations. Every worktree/run needs its own
ports; check availability and fail with the occupied port in the message, rather
than silently selecting another port. Include a per-run suffix in test database
names and temporary resource IDs so concurrent checks in one worktree also isolate.
Never run tests against development `DATABASE_URL` by fallback.
Vite proxies `/api/v1` to `http://127.0.0.1:${BACKEND_PORT}`; the SDK uses the
relative prefix `/api/v1` exactly once. No CORS setup is needed for this path.

Compose volumes/networks must be project-scoped. Daemon identities/state/logs and
Rails PID/temp paths must be worktree-scoped; using mise/pitchfork does not by itself
prove isolation. A generated path hash may suggest an ID/port, but cannot guarantee
uniqueness or free ports. T5 must demonstrate two worktrees without shared resources.
Checks use their own temporary servers, never dev daemons, and bounded readiness
polling rather than fixed sleeps. Cleanup targets only resources the run created.

## Ownership and independent dependencies

- T1 owns the initial `mise.toml` tool pins and this interface agreement.
- After T1 integration, T2 owns `contracts/`, T3 `backend/`, T4 `frontend/`.
  These tasks may run concurrently **without editing root configuration**.
- T2/T4/T9 create independent npm manifests and `package-lock.json` files in
  `contracts/`, `frontend/`, `tooling/`. No root npm project, workspaces, shared
  lockfile or shared `node_modules`. Each project records exact direct versions.
- T3 owns `backend/Gemfile.lock`; no other task updates it concurrently.
- T5 owns Compose, daemon configuration and root lifecycle aliases. T6 owns SDK
  placement and contract integration; coordinate any shared root edits sequentially.
- T8 integrates root check/install aliases after preceding tasks. T9 owns hooks,
  `tooling/` and the new CI workflow. T10 finalizes user/agent documentation.
- Transfer shared-config ownership explicitly at integration; never regenerate
  another task's lockfile. Merge latest integration before handing off; do not reset.
- The Hexlet workflow remains protected and unchanged. No push/PR without permission.

## Verification record (2026-11-11, macOS arm64)

Verified from a new worktree based on integration commit `d236b05`:

- `mise install` completed, including downloads of hk, pitchfork, vacuum,
  Docker CLI and Compose. Ruby/Node/Pkl were already locally installed and reused.
- `ruby --version`: 3.4.12; `node --version`: v24.22.2; `npm --version`: 11.19.1.
- Rails 8.1.4.1 was actually installed via `gem install` (17 gems); invoking
  `rails _8.1.4.1_ --version` returned `Rails 8.1.4.1`. Bundler reports 4.0.22.
- `hk --version`, `pitchfork --version`, `vacuum version`, and
  `docker-compose version` reported the pinned versions.
- Pinned create-vue was fetched through npm exec and its help/version ran.
- Docker client/server reported 29.9.3; the pinned PostgreSQL image was pulled,
  and `docker run --rm <image> postgres --version` reported PostgreSQL 18.3.
  This is a binary/image check, **not** an application DB connection test.
- `mise daemons --help` confirmed native daemon support in the pinned mise.

Authoritative availability: Ruby archive
<https://cache.ruby-lang.org/pub/ruby/3.4/> contains 3.4.12;
<https://rubygems.org/api/v2/rubygems/rails/versions/8.1.4.1.json>
reports Rails 8.1.4.1, not yanked, with matching component dependencies.

No mandatory version substitution was needed. No application checks or service
lifecycle have been claimed: those belong to later tasks. CI/Linux installation
and full stack compatibility remain unverified until those tasks run. TDD was
consulted; this task adds declarative pins and interface documentation only, no new
executable behavior or test seam. Subsequent behavioral implementations must agree
their public seam before the red/green loop.
