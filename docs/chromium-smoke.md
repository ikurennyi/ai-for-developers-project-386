# Chromium infrastructure smoke (T7 / #9)

Install the pinned [toolchain](toolchain.md), start Docker Engine, install the
backend bundle and run `npm ci` in `frontend/`. Install this lockfile's browser:

```sh
cd frontend
mise exec -- npx playwright install chromium
# Linux/CI provisioners use: npx playwright install --with-deps chromium
cd ..
mise run smoke
```

No development configuration, PostgreSQL service, Rails daemon or Vite daemon is
needed. This command does not implement the later aggregate `check` or `install`.
`npm test` still runs the fast jsdom tests; browser tests are separate and are
included by `smoke`. The underlying `frontend` command `npm run test:browser`
requires a real Rails server supplied through `BACKEND_PORT`; prefer the isolated
root command rather than pointing tests at development services.

## What is proved

Vitest **4.1.12 Browser Mode**, `@vitest/browser-playwright` **4.1.12**, and
Playwright **1.61.1** launch headless Chromium. There is no separate Playwright
Test runner. The browser mounts `App.vue` with the production Router, CSS and
real Element Plus components. The root route uses the committed generated Fetch
SDK; Vitest's Vite server inherits the production development proxy configuration
and forwards `/api/v1/health` to this run's real Rails process. The test waits for
the actual alert DOM text `API healthy: ok`. Nothing intercepts or mocks HTTP.
This is an infrastructure smoke, not a production-build end-to-end test.

Before starting Rails, a separate Rails runner connects over TCP to the temporary
PostgreSQL and checks `current_database()`, PostgreSQL 18.3 and `SELECT 1`.
The health endpoint itself intentionally does not need a database query; its
success is **not** used as evidence of a working database connection.

## Isolation, readiness and cleanup

Each invocation creates a cryptographically random container/database identity
and password. Docker publishes PostgreSQL to an OS-assigned loopback port. Its
image is the same pinned PostgreSQL 18.3 digest as development; its data is tmpfs,
not a development volume. No caller-provided database URL is used or dropped.
Only the container ID recorded by this invocation is removed, including its
ephemeral anonymous volumes. Development Compose and mise daemons are untouched.

Rails and the browser Vite server each get an available loopback port with strict
binding and **no fallback** if another process wins the bind race. Rails PID and
logs, Vite cache and Vitest attachments belong to a private temporary directory.
Bootsnap is disabled and a per-run `SECRET_KEY_BASE` avoids Rails' shared local
secret file. Test-mode Rails logs go to captured stdout.

PostgreSQL readiness uses TCP `pg_isready` (45-second deadline, each probe
bounded), avoiding the image's temporary init-only Unix-socket server.
Rails readiness uses `/up` (45 seconds, one-second connect/read timeouts).
Vitest's own Vite/browser startup waits for its listening server and page load;
the entire Chromium command has a 120-second outer deadline, in addition to the
15-second test and 10-second DOM polling deadlines. Setup subprocesses have
90-second deadlines. There are no fixed startup sleeps: polling sleeps only
between failed readiness checks. Failures print bounded log tails with the
random database password redacted, and propagate a nonzero status.

On success, exceptions, timeout, SIGINT or SIGTERM, the runner terminates only its
active child process groups (TERM, then KILL after at most five seconds), removes
its own PostgreSQL container, and removes its private directory. Docker cleanup
is itself bounded at 30 seconds; cleanup errors fail the command. As with any
process, SIGKILL or a crashed Docker Engine cannot guarantee cleanup. The final
`SMOKE_RESOURCES` JSON identifies this run's resources for diagnostics/probes.

## Reproducible lifecycle probes

```sh
mise run smoke:test
```

This real integration test runs two simultaneous successful smoke commands,
checks distinct database/container identities, and verifies disappearance of
every recorded process **group**, container and temporary directory. It then
checks three failures with the same cleanup assertions:

- `--fail-after-ready`: deliberate exception after real Rails readiness;
- `--probe-browser-failure`: stop this run's Rails, then require Chromium to fail
  its unchanged DOM assertion (`API unavailable`, not `API healthy: ok`);
- `--probe-readiness-timeout`: require a nonexistent Rails route to hit a short
  two-second readiness deadline with the URL in diagnostics.

An unrelated child listener remains alive and responds after all these runs.
These opt-in flags are runner probes, not application behavior or HTTP mocks.

## Actual local verification, 2026-11-11

On macOS arm64 / Docker Engine 29.9.3 with the pinned Ruby/Node and lockfiles:

- Red first: Chromium without Rails failed with `API unavailable`; the lifecycle
  integration test failed before the runner existed.
- Green: `mise run smoke` passed the Chromium DOM test and independent DB probe.
- `mise run smoke:test` passed concurrent isolation plus exception, real browser
  failure and readiness-timeout cleanup probes. Example successful databases:
  `smoke_dd163e34a0ed5c779406` and `smoke_1c3b9b56c75cb9b68bc6`.
- Frontend type check, ESLint/oxlint, Prettier check, three jsdom tests and
  production build passed; backend RuboCop passed (35 files).

Linux/CI has not been executed. No push, PR, GitHub Actions success or aggregate
check is claimed. The protected Hexlet workflow and toolchain pins are unchanged.
