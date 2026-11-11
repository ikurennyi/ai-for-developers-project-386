# Scaffold local acceptance — T10 / #12

## Status

| Criterion | Result |
| --- | --- |
| Reproduce documented installation and dev lifecycle | Passed locally |
| Full local aggregate and repeated clean runs | Passed locally |
| Agent initialization intent / trimmed instructions | Performed manually; literal `/init` not invoked |
| Final independent standards/spec review | **Pending orchestrator review after integration** |
| Review fixes and post-review repeated `check` | **Pending**; current repeats are pre-review evidence only |
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

## Commands actually reproduced

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

## Agent initialization and verification approach

The implementer invoked the TDD, writing-for-agents and OpenCode skills, explored
the actual task definitions, module manifests, Rails health implementation and
request contract tests, Vue root/router/view, proxy, TypeSpec and lifecycle/check
scripts, then replaced the obsolete empty-scaffold `AGENTS.md` with a short
working guide and condition-specific documentation pointers.

This performs the initialization intent against the implemented scaffold. The
available tools expose no slash-command invocation, and `opencode --help` lists
no `init` CLI subcommand. A literal interactive `/init` was **not** invoked and
is not claimed; if literal invocation is required, it remains an interactive
follow-up rather than fabricated evidence.

This task changes documentation only, so no new executable behavior or test seam
was introduced and no new red/green implementation cycle is claimed. Verification
uses the already-agreed public lifecycle/check commands and Chromium DOM seam.
The previous README placeholders and incorrect “no application sources” agent
instruction were corrected, then the documented full cycle was exercised.

## Handoff requirements

The orchestrator must integrate sequentially, run independent standards/spec
review, arrange fresh-agent fixes if necessary, and record a subsequent full
`mise run check` before closing #12. Current local repeats do not satisfy that
post-review condition. External GitHub Actions remains a separate, unconfirmed
criterion until an independently authorized push/run is observed. Leave #1 open
and unchanged.
