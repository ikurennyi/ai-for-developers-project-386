# Application releases (#37)

## Version policy

Calendar is **one application**, released from `main` using SemVer and Release
Please's `simple` strategy. `version.txt` records its version; `CHANGELOG.md`
and `.release-please-manifest.json` are updated in the release PR. Tags are
`v<version>` (for example `v0.1.0`), without a component prefix.

The first proposed release is **0.1.0** (`initial-version`). The initial manifest
is deliberately empty: no previous release is claimed. The initial version file
is a bootstrap value, not evidence of an existing tag or release. With no
bootstrap cutoff, the first changelog considers existing Conventional Commits
in `main` history. Review those notes before releasing.

After that first release, the largest relevant change determines the bump:

| Commit | From 0.1.0 | From 1.2.3 |
| --- | --- | --- |
| `fix: ...` | 0.1.1 | 1.2.4 |
| `feat: ...` | 0.2.0 | 1.3.0 |
| `feat!: ...`, any type with `!`, or `BREAKING CHANGE:` footer | 0.2.0 | 2.0.0 |

`bump-minor-pre-major: true` keeps breaking changes below 1.0 as minor bumps;
`bump-patch-for-minor-pre-major: false` keeps features as minor bumps too.
0.x is explicitly unstable: a minor release may break compatibility.
Ordinary docs/chore/ci/test/refactor commits do not independently open a release
PR. Breaking changes must still be marked, regardless of commit type.
Use Conventional Commit PR titles when squash-merging, and preserve meaningful
breaking-change footers in the resulting commit.

Moving to stable 1.0.0 is a deliberate maintainer decision, not an automatic
consequence of a 0.x breaking change. Use an approved empty Conventional Commit
with a `Release-As: 1.0.0` body footer, review the resulting release PR, and merge
only after compatibility review and green checks. Do not leave a persistent
`release-as` override in configuration.

This does **not** introduce an npm workspace or publish npm packages.
`frontend/`, `contracts/` and `tooling/` retain their independent manifests,
versions and lockfiles. There are no workspace plugins or extra version files.
No automatic deployment, Docker build/publication or registry credentials are
added by the release workflow.

## Maintainer-only provisioning (not performed)

The workflow intentionally fails with a clear error when
`RELEASE_PLEASE_TOKEN` is missing. It never falls back to `GITHUB_TOKEN`:
PRs/updates made with that built-in token normally do **not** trigger other
Actions workflows. Calling release-please successfully is not enough if the
release PR has no real application checks.

An authorized maintainer must:

1. Create a **fine-grained personal access token**, preferably for a dedicated
   automation account. Select only `ikurennyi/ai-for-developers-project-386`,
   set a short practical expiration, and grant repository **Contents: read/write**,
   **Pull requests: read/write**, and **Issues: read/write** (release lifecycle
   labels). Metadata read is implicit. Do not grant Actions, Workflows,
   administration, organization-wide or all-repositories access. No classic
   broad `repo` token is needed. Obtain organization approval if required.
2. Store its value as the repository Actions secret `RELEASE_PLEASE_TOKEN`
   through Settings → Secrets and variables → Actions → New repository secret.
   Never paste a token into an issue, command argument, log, source file,
   `mise.local.toml`, or committed `.env`. Rotate the secret before expiry;
   revoke the old token after the replacement is verified.
3. Check repository/organization Actions policy permits the SHA-pinned
   `googleapis/release-please-action` and PR creation. Where required, enable
   “Allow GitHub Actions to create and approve pull requests”. This does not
   authorize the bot to approve or merge releases; keep human review.
4. Require `Application checks / check` on `main`, with normal human review.
   Verify the actual check name after the first authorized run. Do not give
   the token/account branch-protection bypass or relax checks to merge a release.
   Ensure tag rules permit that account to create new `v*` release tags without
   granting force-update/deletion rights.

The workflow's own `GITHUB_TOKEN` has `permissions: {}`: all release API writes
use the separately scoped token. There is no checkout, shell interpolation of
secrets, `pull_request_target`, untrusted PR code execution, or credential
persistence. Only pushes to `main` invoke it; serialized, non-cancelling runs
avoid racing PR/tag updates. No manual dispatch or feature-branch release path
is exposed. A scoped GitHub App could replace the PAT in a separate approved
change; do not substitute the built-in token.

## Prepare, review and release

1. After separately authorized publication/merge to `main` and provisioning,
   a push with releasable Conventional Commits creates or updates the release
   PR. New commits to `main` update the same pending PR.
2. Confirm `Application checks / check` actually runs for the bot-created PR
   **and subsequent updates**, including commitlint, workflow validation and
   `mise run check`. The existing `pull_request` workflow has no path or actor
   exclusions; using the separate token allows its events to trigger normally.
   Never treat a missing, skipped or stale check as passing.
3. Review version, breaking changes, changelog links, and the diff. Expected
   release changes are `version.txt`, `CHANGELOG.md` and the manifest, not npm
   manifests or lockfiles. Preserve the Conventional Commit release title and
   release-please's PR body/`autorelease: pending` label; these identify the
   merged release. Do not manually retag or alter the manifest to force a retry.
4. Human approval and merge of the release PR is the release decision. Its push
   to `main` makes release-please create the matching Git tag and published
   GitHub Release, then mark the PR `autorelease: tagged`. No deployment occurs.
5. Verify the release workflow succeeded, tag/version/changelog agree, the tag
   points at the merged release commit, and the GitHub Release contains the
   expected notes. Record PR, Actions run, tag and Release URLs as external
   evidence. Check the `main` application run independently.

If credentials expire or the API fails after merge, restore/rotate credentials
and re-run that failed `main` workflow run after inspecting existing tags and
Releases. Do not delete or move published tags as a routine retry. Missing PR
checks require fixing identity/policy first, not merging unchecked.

GitHub's release API additionally requires **Workflows: write** when the target
commit changes workflow files relative to the current default branch. Normally
the release commit is at `main` and needs no such permission. If `main` advances
with workflow edits before a delayed release/retry, a historical target may hit
this restriction (403/404). Treat that as a provisioning blocker: an authorized
maintainer must inspect the target and separately approve any narrowly scoped
permission elevation/recovery. Do not silently broaden the token, change the
target SHA, or bypass protection.

## Validation and current evidence

```sh
mise run install
mise run ci:validate
mise run check
```

`ci:validate` runs pinned actionlint on **only** the application and release
workflows, plus Ruby configuration/security-policy tests. It parses the manifest
and verifies version-file agreement, single application ownership, version policy,
main-only events, separate-token wiring and lack of a credential fallback.
These run in existing application CI too. The protected
`.github/workflows/hexlet-check.yml` is not edited or included in this validation.

Local verification on 2026-11-13, macOS arm64:

- Red/green: missing config, then missing release workflow caused the new tests
  to fail; both passed after implementation (2 tests, 29 assertions).
- `mise run ci:validate`: both workflows pass actionlint; existing workflow tests
  pass (2 tests, 23 assertions).
- Configuration and manifest also pass the actual release-please **17.3.0**
  exported JSON schemas using Ajv **8.17.1** / ajv-formats **3.0.1**; an unknown
  top-level option is rejected. The pinned v4.4.1 action bundles release-please
  17.3.0. Dependencies for this probe were installed in a separate temporary
  directory, not any repository npm project. Seven version examples using
  upstream commit parsing/versioning pass: the six table cells above plus a
  `BREAKING CHANGE:` footer at 0.1.0 → 0.2.0. No GitHub API write was involved.
- `mise run check` passes all nine gates: 9 RSpec examples against real isolated
  PostgreSQL, 2 jsdom tests, 1 real Chromium test, contract regeneration/lint/types,
  application lint/format/types and production build.
- Frozen installation succeeds. The existing frontend dependency audit reports
  13 moderate advisories; no audit fix or dependency/lockfile change was made.

**External behavior remains unverified and blocked on maintainer provisioning
and separately authorized push/PR/merge.** No token was provisioned, repository
settings changed, release PR opened, tag created or GitHub Release published.
Local checks do not prove Linux Actions execution, release PR event delivery,
required-check configuration, or a successful tag/Release cycle. Keep #37 open
until the parent integration process records the applicable completion evidence.

## Primary references

- [Release Please action, authentication and other workflows](https://github.com/googleapis/release-please-action/tree/5c625bfb5d1ff62eadeeb3772007f7f66fdcf071#other-actions-on-release-please-prs)
- [Manifest configuration and bootstrapping](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md)
- [Versioning strategies](https://github.com/googleapis/release-please/blob/main/docs/customizing.md#versioning-strategies)
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
- [SemVer 2.0.0: initial development](https://semver.org/spec/v2.0.0.html#spec-item-4)
- [GitHub: triggering a workflow from a workflow](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow#triggering-a-workflow-from-a-workflow)
- [GitHub: creating a fine-grained PAT](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token)
- [GitHub: release creation and conditional workflow permission](https://docs.github.com/en/rest/releases/releases#create-a-release)
