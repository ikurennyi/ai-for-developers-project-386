# Hooks and application CI (T9 / #11)

After the [pinned toolchain](toolchain.md) and `mise run install`:

```sh
mise run hooks:install
mise run hooks:test
mise run commits:test
mise run ci:validate
```

`hooks:install` invokes **repository-local** `hk install --mise`; never use
`--global`. Git configuration/hooks in a linked worktree may be shared with its
repository, so installation is explicit, not a dependency-install side effect.
It does not overwrite another hook manager (`--force` is not used).

`hk.pkl` explicitly disables fix, stage and stash for both hooks:

- `pre-commit`: `git diff --cached --check`, plus the same root backend lint and
  frontend lint/format commands when that module has staged changes. No database,
  browser, build, generation or full typecheck runs in this fast path. Module
  linters read the working tree, including unstaged edits; they never hide or
  stage those edits. A partial-stage commit may therefore be blocked by an
  unstaged violation. Use `mise run check` for the full acceptance gates.
- `commit-msg`: the independent `tooling/` npm project's locked commitlint CLI
  and Conventional Commits config. The message is checked, not rewritten.

Tooling has its own manifest and lockfile, exact commitlint **21.2.4** pins and
`npm@11.19.1`; it shares no npm workspace, lockfile or dependencies with the app.

## Workflow contract

`.github/workflows/application-check.yml` runs on push and pull request, with
only `contents: read`, SHA-pinned checkout/mise actions, credentials persistence
disabled, and mise **2026.11.6** installing exact project tool versions. Native
Ruby/libpq build dependencies are explicit. Bundler **4.0.22**, frozen Bundler
dependencies and each independent `npm ci` are installed by the local interface.
The frontend lockfile's Playwright installs Chromium **and system dependencies**.
The final command is exactly the local `mise run check`.

The PostgreSQL service uses the exact version/digest in Compose and receives a
real SQL/version preflight through the locked pg gem. The aggregate receives
`CI=true` and the service's `DATABASE_URL`; both RSpec and Chromium gates create
unique per-run databases on that actual service. Each independently checks SQL,
database identity and version, then drops only its database. Gates do not start
extra Docker containers in CI. Local mode retains isolated per-gate containers.
`mise run ci:database-test` simulates this service locally, including concurrent
gates, real failures and the unchanged aggregate command; it is not an Actions run.

`ci:validate` runs pinned **actionlint 1.7.12** against only our application and
release workflows, then checks their security/environment/configuration policy.
It does not validate, edit or regenerate the protected Hexlet workflow.
The separate [release workflow](releases.md) requires provisioned credentials;
local validation does not prove that release PR checks or external releases work.

## Commit ranges

`mise run commits:check` reads `GITHUB_EVENT_NAME` and `GITHUB_EVENT_PATH` without
shell interpolation. Full history (`fetch-depth: 0`) is required:

- PR: actual head commits not reachable from the event's base SHA; never the
  synthetic checkout merge message.
- Existing push, including force pushes: after commits not reachable from before.
  Before validation, CI fetches the exact push `before` SHA when it is absent
  from the full checkout (for example, after release-please rebases its branch).
- New branch/tag: exclude the fetched default branch when present. First
  publication of the default branch falls back to the adoption boundary.
- Deleted ref: no new messages. Unsupported events, invalid/missing SHAs or
  missing history fail closed instead of silently validating an empty range.

All ranges additionally exclude the immutable pre-hooks scaffold boundary
`e3a8384ba908b4419e1ef6a349707645bebc01ae` and its ancestors, recorded in
`tooling/commitlint-baseline`. Do not move it forward to bypass a bad new message.
If fetching a force-push before object fails, CI intentionally fails rather than
guessing; repair repository access/history and rerun. Each selected message goes
through the real commitlint CLI; its normal merge/revert ignores remain enabled.

## Local readiness versus external acceptance

Local verification on macOS arm64 (2026-11-11):

- Red/green tests for actual installed hooks: valid/invalid messages, staged
  whitespace, real frontend formatting/lint and backend syntax violations.
  Index entries, source bytes, message bytes and isolated global Git config are
  unchanged by success and failure; partially staged work is preserved.
- Git fixture tests cover push/PR, new/default branch publication, published
  default history exclusion, deletion, missing objects and rewritten history.
- actionlint and workflow-policy tests pass. actionlint first caught a numeric
  service-port expression; the corrected string-key expression passes.
- `mise run install` and the full `mise run check` pass (9 RSpec examples,
  3 jsdom tests, 1 real Chromium test, all static gates and production build).
  The inherited frontend dependency audit still reports 13 moderate advisories;
  tooling reports none. No audit fix or unrelated lockfile update was performed.

**External criterion remains unchecked:** no authorized push or GitHub Actions
run has occurred, so green Linux/GitHub Actions execution is **unconfirmed**.
Local readiness is not full specification completion. #11 was subsequently
integrated and closed; current acceptance and pending review/CI are recorded in
[acceptance](acceptance.md). No PR or push was created by this documentation task.
