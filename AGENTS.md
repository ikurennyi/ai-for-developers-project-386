# Repository guidance

- Before exploring, read `docs/agents/domain.md`. Before tracker operations, read
  `docs/agents/issue-tracker.md`; before triaging, read `docs/agents/triage-labels.md`.
- Rails API is in `backend/`; Vue is in `frontend/`; `contracts/` owns TypeSpec;
  `tooling/` owns commitlint. Keep their lockfiles and npm projects independent.
- For install, DB/start/status/stop and hooks, follow `README.md`; for individual
  tests/lint and acceptance gates, read `docs/checks.md`. Run `mise run check`
  before handoff; checks never fix or stage sources.
- For service changes or another worktree, read `docs/dev-services.md` first.
  Use separate local credentials/ports/resources; stop preserves data.
- Test gates ignore caller DB URLs locally. `CI=true` requires `DATABASE_URL`
  for a disposable PostgreSQL service with CREATE/DROP DATABASE privileges;
  gates create/drop only random per-run databases, never the URL's database.
- Edit TypeSpec, then run `mise run contracts:generate`; OpenAPI and SDK are
  committed generated artifacts, not hand-edited sources.
- Use Conventional Commits (`feat: add ...`), `<type>/<kebab-case>` branches and
  Conventional Commit PR titles. Preserve existing history; merge integration
  before handoff. Push/PR require separate permission.
- Preserve `.github/workflows/hexlet-check.yml` unchanged: no edit, rename or
  deletion. Hexlet checks run on pushes with `HEXLET_ID`; availability depends
  on completing project steps, not local test discovery.
- Report local checks separately from unconfirmed external Actions. Final
  standards/spec review and repeated check precede closing #12; leave #1 untouched.
