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
commands in `contracts/` and `frontend/` (and `tooling/` when present), then
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
6. `backend:test`: RSpec against a fresh, real PostgreSQL 18.3 container.
7. `frontend:test`: Vitest jsdom tests.
8. `smoke`: real Rails, proxy, SDK and Chromium DOM test in Vitest Browser Mode.
9. `frontend:build`: Vite production build (types were already checked above).

No `mise.local.toml`, running development database, daemon, or user-provided
database URL is required. RSpec reuses the [smoke runner's](chromium-smoke.md)
per-invocation random PostgreSQL identity, pinned image, tmpfs, independent SQL
connection probe, timeouts, redacted diagnostics and targeted cleanup. It does
not start application servers. The later Chromium gate gets another fresh
database and temporary servers. Caller database URLs are ignored, never dropped.
Cleanup removes only recorded containers and child process groups, on success
and failure. There is no Compose down/prune or development-daemon cleanup.

Checks never fix or stage sources. They may create ignored build/type caches or
`frontend/dist/`; these are not source edits and do not need manual deletion for
another check. Contract artifacts are regenerated only in temporary directories.

## Actual verification, 2026-11-11

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
workflow is unchanged; CI and hooks belong to T9.
