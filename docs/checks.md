# Aggregate checks (T8 / #10)

Install the [pinned toolchain](toolchain.md) and provide Docker Engine. From a
fresh checkout:

```sh
mise trust mise.toml
mise install
mise run install
mise run check
```

`install` runs Bundler **4.0.22** with `BUNDLE_FROZEN=true`, independent `npm ci`
commands in `contracts/`, `frontend/` and `tooling/`, then
installs the frontend lockfile's Playwright Chromium. It does not update pins or
lockfiles. Linux provisioners must also install Chromium system libraries, e.g.
`mise exec -- node frontend/node_modules/playwright/cli.js install --with-deps chromium`.
Installing application dependencies is intentionally separate from checking them.

## Ordered, fail-fast gates

`check` invokes these same public aliases sequentially. Missing commands and every
nonzero subprocess status fail the aggregate; no gate is optional:

1. `contracts:check`: TypeSpec with warnings as errors; generate twice into
   temporary directories; vacuum (warnings fail); compare OpenAPI and SDK bytes
   and file lists for drift/reproducibility; strict SDK-consumer TypeScript.
2. `backend:lint`: RuboCop without auto-correction.
3. `frontend:lint`: oxlint followed by ESLint, without fixes; no ESLint warnings.
4. `frontend:format`: Prettier **check**, never write.
5. `frontend:typecheck`: strict vue-tsc project build with `--force`, so cached
   incremental results cannot hide changed errors.
6. `backend:test`: RSpec against a fresh database on real PostgreSQL 18.3.
7. `frontend:test`: Vitest jsdom tests.
8. `smoke`: real Rails, proxy, SDK and Chromium DOM test in Vitest Browser Mode.
9. `frontend:build`: Vite production build (types were already checked above).

No `mise.local.toml`, running development database, daemon, or user-provided
database URL is required. RSpec reuses the [smoke runner's](chromium-smoke.md)
per-invocation random PostgreSQL identity, pinned image, tmpfs, independent SQL
connection probe, timeouts, redacted diagnostics and targeted cleanup. It does
not start application servers. The later Chromium gate gets another fresh
database and temporary servers. Locally, caller database URLs are ignored.
With explicit `CI=true`, both gates instead require `DATABASE_URL` pointing to
a disposable PostgreSQL 18.3 service with CREATE/DROP DATABASE privileges (URL
without query or fragment, so libpq options cannot override the random DB). Each
gate creates a random `smoke_<20 hex digits>` database there, overrides the URL's
database for Rails/RSpec, and drops only that newly created database in cleanup.
The service and the original URL's database are retained. Missing or unusable CI
configuration fails, without falling back to Docker. This mode needs the locked
pg gem but no Docker commands from the gates. Local isolated Docker behavior and
the aggregate command are unchanged. Child process groups and private directories
are removed in both modes, on success and failure; cleanup failures fail the gate.
There is no Compose down/prune or development-daemon cleanup.

Checks never fix or stage sources. They may create ignored build/type caches or
`frontend/dist/`; these are not source edits and do not need manual deletion for
another check. Contract artifacts are regenerated only in temporary directories.

## Actual verification, 2026-11-11

Current full-cycle evidence and pending review/CI: [acceptance](acceptance.md).
For the booking product, see the [#22 acceptance traceability and review follow-up](spec-22-traceability.md).
The following records the original T8 implementation run.

On macOS arm64, Docker Engine 29.9.3 and the pinned toolchain:

- Red: the public install/check commands were absent; the initial CLI failure
  test failed before implementation.
- `mise run install` installed all current lockfiles and Chromium successfully.
  npm reported **13 moderate frontend advisories**; pins were not changed and no
  audit-fix operation was run. An audit gate is not part of this task's spec.
- `mise run check:test` passed **13 real failure probes**, each returning exit 1:
  TypeSpec unresolved type, vacuum invalid operation ID, OpenAPI drift, SDK
  drift, SDK strict typing, Ruby syntax via RuboCop, ESLint banned suppression,
  Prettier violation, frontend strict typing, failing RSpec expectation, failing
  jsdom expectation, failing Chromium DOM expectation, and missing build entry.
- Every probe restores its file in `ensure`. SHA-256 snapshots of all tracked and
  unignored source files plus index entries remained identical across each check.
  Container/process-group/private-directory disappearance is asserted for every
  emitted resource record, and database/container IDs are unique across runs.
- Two subsequent clean aggregate runs passed: **9 RSpec examples**, **3 jsdom
  tests**, **1 Chromium test**, all static gates and production build.

Reproduce with `mise run check:test` only in a dedicated checkout: it temporarily
introduces deliberate violations. Do not edit files concurrently with these
probes. Docker Engine and installed dependencies are required. The harness runs
the real aggregate, without fake gate executables or HTTP mocks.

No Linux/GitHub Actions execution, push or PR is claimed. The protected Hexlet
workflow is unchanged; current CI/hooks commands are in [hooks-and-ci](hooks-and-ci.md).

## Additional public checks

These are not extra gates in `check`; run them when changing infrastructure:

| Command | Purpose |
| --- | --- |
| `mise run services:test` | Lifecycle configuration/validation CLI tests, no Docker |
| `mise run services:fresh-test` | Fresh dedicated checkout/volume: immediate TCP SQL after `db:up`, preparation, stop retaining data |
| `mise run ci:database-test` | Local Docker fixture simulates CI service: parallel gates, failures, aggregate and SQL cleanup assertions |
| `mise run smoke:test` | Real parallel smoke and failure/timeout cleanup probes |
| `mise run check:test` | Real deliberate failures for every aggregate gate |
| `mise run hooks:test` | Actual isolated Git hook success/failure tests |
| `mise run commits:test` | Commit-event range fixtures |
| `mise run ci:validate` | actionlint and application/release-workflow configuration/policy tests |
| `mise run commits:check` | CI commitlint range; requires real GitHub event env/history |
| `mise run contracts:generate` | Explicitly update committed generated artifacts (writes) |

Run deliberate failure probes only in a dedicated checkout without concurrent
edits. Two-checkout dev lifecycle probes are documented in [dev-services](dev-services.md).
For all 13 deliberate aggregate failures in CI service mode, run
`mise exec -- ruby test/ci_database_integration_test.rb --failure-probes` in a
dedicated checkout. It also performs two clean repeats and checks source/index bytes.
`hooks:install` is explicit setup, not a check. `frontend:format` is check-only;
the module's `format:write` is an explicit, separate source-changing operation.
