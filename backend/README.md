# Rails API

Official Rails 8.1.4.1 API-only scaffold, Ruby 3.4.12, Bundler 4.0.22.
No business models or migrations. `ApplicationRecord` is the generated abstract base.

Run from `backend/` with the repository's pinned mise tools:

```sh
mise exec -- bundle _4.0.22_ install
DATABASE_URL="$DEVELOPMENT_DATABASE_URL" mise exec -- bin/rails db:prepare
DATABASE_URL="$DEVELOPMENT_DATABASE_URL" mise exec -- bin/rails server -b 127.0.0.1 -p "$BACKEND_PORT"
mise exec -- bundle _4.0.22_ exec rubocop
DATABASE_URL="$TEST_DATABASE_URL" RAILS_ENV=test mise exec -- bin/rails db:prepare
mise exec -- bin/test
```

`DATABASE_URL` is mandatory; there is no shared database-name fallback.
Supply your own PostgreSQL 18.3 and worktree/run-specific database URLs until
the root lifecycle tasks are implemented. `TEST_DATABASE_URL` must identify a
distinct disposable test database. `bin/test` requires it, rejects an identical
development `DATABASE_URL`, and exports it as `DATABASE_URL` with `RAILS_ENV=test`.
Root `backend:test` should invoke `bin/test`; root `backend:lint` should invoke
`bundle _4.0.22_ exec rubocop` from this directory (no autofix).
CI dependency installation: `BUNDLE_FROZEN=true bundle _4.0.22_ install`.
The lockfile includes arm64 macOS and arm64/x86_64 Linux platforms and checksums.

`GET /api/v1/health` returns HTTP 200, `application/json`, exactly
`{"status":"ok"}`. It is API liveness, not database readiness.
The generated `/up` boot check is retained. RSpec checks the real request response
and separately executes `SELECT 1` through Active Record against PostgreSQL.
Generated OpenAPI validation is a subsequent contract-integration task (T6),
not implemented here. No HTTP mocks are used.

## T3 verification (2026-11-11)

- Generated with `rails _8.1.4.1_ new backend --api --database=postgresql`,
  omitting unused mail/storage/cable/solid services, Minitest, deployment and CI.
- Real private PostgreSQL 18.3 pinned image; test database prepared successfully.
- Red: health request failed with 404 before route/controller implementation.
- Green: RSpec discovered and passed both request and database examples.
- Wrong response probe (`status: "broken"`): request test exited 1.
- Missing hash spacing probe: RuboCop exited 1 with two offenses.
- Unreachable database probe: RSpec exited 1 with a connection error.
- Probes restored; final checks must pass without modifying sources.

The task's temporary container is removed after verification; no permanent
service orchestration or root aliases are owned by this module. No GitHub Actions
run is claimed without a push.
