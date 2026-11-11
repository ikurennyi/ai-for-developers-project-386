# Scaffold local acceptance — T10 / #12

## Status

| Criterion | Result |
| --- | --- |
| Reproduce documented installation and dev lifecycle | Passed locally |
| Full local aggregate and repeated clean runs | Passed locally |
| Agent initialization / trimmed instructions | Supported `init` command handler invoked; guided update completed |
| Independent standards/spec review | Findings received at `b2274a8`; resolutions below await orchestrator re-review |
| Review fixes and post-review repeated `check` | CI-service simulation and two clean local repeats passed; evidence below |
| Green Linux / GitHub Actions | **Unconfirmed**; no authorized push or run |
| #12 closure | **Open**, awaiting review/fixes/repeated check |

This is local readiness evidence, not completion of parent #1. Parent issue and
protected Hexlet workflow were not changed. No push or PR was created.

## Environment and provenance

Verified 2026-11-11 on macOS arm64, Docker Engine 29.9.3, mise 2026.11.6,
Ruby 3.4.12, Node 24.22.2, npm 11.19.1, Bundler 4.0.22, pitchfork 2.34.0,
and the pinned PostgreSQL 18.3 image/digest.

Fresh branch `docs/scaffold-acceptance`, worktree
`/private/var/folders/p9/6byhfhnd78sdncx7j259p8hw0000gn/T/opencode/scaffold-acceptance`,
based on integration `48c6825` (ancestry verified). Before claiming #12, native
#11 was confirmed CLOSED and #12's native open-blocker count was zero. #12 was
assigned via the repository's tracker procedure.

## Original T10 commands actually reproduced

Follow [README](../README.md) for the runnable sequence and
[checks](checks.md) for individual gates and opt-in probes.

1. `mise trust mise.toml`, `mise install`, explicit Bundler installation and
   `mise run install` succeeded. Tools/gems/browser already available on this
   machine were reused; each npm project ran `npm ci` in this fresh worktree.
   Frontend npm audit reported **13 moderate advisories**; contracts/tooling
   reported none. No audit fix or lockfile change was made.
2. Generated private `mise.local.toml`, selected distinct ports 3110/5110/5510
   (including both DB URLs), trusted it and ran `dev:validate`, `db:up`,
   `db:prepare`, `dev:start`, `dev:status`: all succeeded. Worktree project was
   `scaffold-wt-72c2576b7468de802d16`.
3. Headless Playwright Chromium opened the actual development root at
   `http://127.0.0.1:5110/` and waited for exact DOM text `API healthy: ok`.
   This supplements, rather than replaces, the Vitest Browser Mode gate.
4. `mise run dev:stop` succeeded. All three ports refused connections afterward;
   the owned PostgreSQL container was exited and its data volume retained.
5. `mise run check` passed without running dev daemons: TypeSpec, vacuum,
   reproducibility/drift and SDK types; RuboCop (35 files); oxlint/ESLint;
   Prettier; strict vue-tsc; **9 RSpec examples**, **3 jsdom tests**,
   **1 Chromium test** with independent real PostgreSQL SQL/version probe;
   production build. vacuum reported zero errors/warnings and two informational
   findings. Every gate uses the documented public command.
6. Explicit `hooks:install` succeeded (repository-local Git hooks; linked
   worktrees may share this configuration). `hooks:test` passed 3 tests / 26
   assertions; `commits:test` 6 / 68; `ci:validate` passed actionlint and workflow
   policy (1 / 19); `services:test` passed 4 / 14.
7. `smoke:test` passed concurrent isolation and success/failure/readiness-timeout
   cleanup probes. `check:test` passed all **13 deliberate failure probes and
   two clean repeated checks**, including source/index preservation assertions.
   The first combined probe invocation hit the harness's 120-second timeout
   after all 13 failure cases but before clean repeats; rerunning `check:test`
   with a 300-second budget completed successfully. No probe edits remain.
   All 23 temporary resource records across these invocations were checked:
   their containers and private directories were absent.
8. All documented `mise run` command names resolve to actual root tasks;
   `git diff --check` passed. Only documentation is changed.

Raw local logs are retained outside Git in the approved temporary directory at
`opencode/scaffold-context/t10-check.log`, `t10-smoke-probes.log`,
`t10-check-probes.log` (interrupted first attempt), and
`t10-check-probes-retry.log`. They are local evidence, not portable CI artifacts.

## Final-review fixes — `fix/scaffold-review`

Fresh implementer worktree:
`/private/var/folders/p9/6byhfhnd78sdncx7j259p8hw0000gn/T/opencode/scaffold-review`.
Base `b2274a8` was verified as integration ancestry. No tracker writes, push, PR,
Actions dispatch or protected Hexlet edits were performed.

### Standards findings and resolutions

- **P2 premature Compose health:** the healthcheck and lifecycle status now use
  `pg_isready -h 127.0.0.1`, excluding the temporary init-only Unix-socket server.
  Red: workflow policy test failed on the previous healthcheck. Green: policy
  passed; `services:fresh-test` created a new volume, immediately made 25 real TCP
  SQL connections without retry, prepared development/test DBs and stopped while
  retaining data. The probe also exposed `dev:stop` failing before daemons had
  ever started; stop now skips inactive daemons. Fresh probe and repeated stops
  passed afterward. Only this probe's explicitly identified initial fixture was
  removed before the successful fresh-volume rerun; successful-run data remains.
- **Nonblocking duplicated cleanup assertions:** `test/resource_assertions.rb`
  now owns process/group, private-directory and container/database disappearance
  checks for smoke, aggregate and service-mode probes. Local `smoke:test` passed
  concurrent success plus exception/browser-failure/timeout cleanup and sentinel
  survival. CI-mode probes use the same helper and assert SQL database absence.
- **Nonblocking transitional installer optionality:** `tooling` is in the same
  mandatory npm-project list as contracts/frontend; there is no directory-exists
  fallback. Frozen install is retested without changing lockfiles.

### Spec findings and resolutions

- **P2 final TCP readiness:** resolved and independently probed as above.
- **P2 CI service bypass:** the unchanged `mise run check` now receives `CI=true`
  and the workflow PostgreSQL service's `DATABASE_URL`. Both RSpec and Chromium
  create unique random per-run databases on that service, probe actual SQL,
  database identity and version, then drop only their created database. The
  service and original database survive. Gates invoke no Docker in this mode;
  local mode retains isolated Docker containers and ignores ambient URLs.
  Red: the service regression test detected the old gate creating another
  container. Green: `ci:database-test` passed concurrent public gates, three real
  failure modes, the full aggregate, SQL cleanup and source/index snapshots.
  `--failure-probes` additionally passed all **13 real aggregate fault probes**
  (including failing RSpec), followed by **two clean aggregate repeats** on the
  borrowed service. All emitted databases were unique and removed; process groups
  and private directories were absent. An additional red/green URL validation
  test rejects query/fragment overrides before any app/test preparation.
- **P3 agent initialization:** resolved through the supported OpenCode command
  mechanism, not a manually substituted prompt. OpenCode **v2.2.7**, official
  [API reference](https://opencode.ai/docs/api) and
  [TUI commands](https://opencode.ai/docs/cli/tui) were inspected. The worktree's
  `GET /api/command?location[directory]=<worktree>` returned
  `init — guided AGENTS.md setup`. The actual invocation was:

  ```sh
  opencode api post /api/session/ses_e34942735ffeCtrUvz3Ygyu62j/command \
    --data '{"name":"init","text":""}'
  ```

  It succeeded (204), delivering the guided “Create or update AGENTS.md”
  initialization instruction into the existing session without resetting its
  context. The implementer followed it: inspected executable wiring, manifests,
  lockfiles, configs, hooks, workflow and representative app/request/browser code;
  preserved the compact verified guide and added the non-obvious CI DB safety
  rule. OpenCode and writing-for-agents skills were loaded first. This is an
  actual invocation of the registered `init` slash-command handler through its
  documented API; **interactive typing of `/init` is not claimed**. No pending
  manual-init substitute is presented as completion.

TDD used the already-agreed public lifecycle/test/check seams. Local service
simulation is not Linux or GitHub Actions evidence. Raw logs under the approved
`opencode/scaffold-context/` directory: `review-ci-red.log`,
`review-ci-url-red.log`, `review-ci-probes.log`, `review-ci-failure-probes.log`,
`review-smoke-probes.log`, `review-fresh-volume.log` and final local-check logs.

### Post-fix retest evidence

- `mise run install` passed with mandatory tooling installation; lockfiles were
  unchanged. The existing frontend audit still reports 13 moderate advisories.
- Two explicit `mise run check` invocations passed after fixes: contracts,
  RuboCop, frontend lint/format/types, **9 RSpec examples**, **3 jsdom tests**,
  **1 real Chromium test**, and production build each time. SHA-256 source/file
  and Git index snapshots matched before/after each; shared resource assertions
  confirmed container, process/group and private-directory removal.
- Latest `ci:database-test` rerun passed after URL validation, in addition to the
  full 13-failure/two-repeat service-mode run described above.
- Real `dev:start`, `dev:status`, and `dev:stop` passed using this worktree's
  saved isolated configuration; both actual app daemons were stopped. Repeated
  DB-only stops also passed. Evidence: `review-dev-lifecycle.log`.
- `ci:validate`: actionlint plus **2 tests / 23 assertions**;
  `services:test`: **4 / 14**; `hooks:test`: **3 / 26**;
  `commits:test`: **6 / 68**; all passed. `git diff --check` passed.
- `review-install.log` and `review-final-check.log` retain the install/final
  local-repeat evidence alongside the other local logs. No external CI result
  is inferred from them.

## Handoff requirements

The orchestrator must integrate sequentially, re-review standards/spec fixes and
repeat `mise run check` after integration before closing #12. #12 remains open.
External GitHub Actions is still **unconfirmed** and requires separately
authorized execution. Parent #1 remains open and unchanged.
