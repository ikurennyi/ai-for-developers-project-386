# T4 verification (2026-11-11, macOS arm64)

Base: integration `4467dae`. Node 24.22.2, npm 11.19.1 via `mise exec`.
Native blocker #3 was closed before claiming #6. Only `frontend/` is owned here.

## Behavioral seam

The root route is mounted through the real router and real Element Plus
components in jsdom; no HTTP success mocks or API status substitutes.

- First red: expected technical heading; received create-vue's `You did it!`,
  with no matching `/` route. Added the route/view; test passed.
- Second red: missing `[role="alert"]`. Added the informational Element Plus
  alert stating `API connection not checked`; both tests passed.

These tests cover rendered route behavior, not real browser/backend connectivity.
Live integration and smoke remain T6/T7 responsibilities.

## Controlled gate failures

Temporary probes were added individually under `src/`, executed, then removed:

| Gate                 | Probe                                       | Observed result                                                  |
| -------------------- | ------------------------------------------- | ---------------------------------------------------------------- |
| `npm run type-check` | `export const probe: string = 42`           | Exit 2, TS2322                                                   |
| `npm run lint`       | Vue template with duplicate `id` attributes | Exit 1, `vue/no-duplicate-attributes` and `vue/no-parsing-error` |
| `npm run format`     | `export const probe={value:"unformatted"};` | Exit 1, only probe named after formatting baseline               |

The baseline formatting check passed before the isolated formatting probe.
The lint and formatting commands contain no fix/write flags.

## Reproducibility and remaining caveats

`npm ci` succeeded from the module lockfile. Lint, Prettier check, strict vue-tsc,
Vitest (2 tests) and production build passed independently of a backend.

Initial generator versions reported 16 npm audit findings, including high Vite
advisories. Patched exact Vite/Vitest pins remove the high findings. `npm ci`
still reports 13 moderate development-tool dependency findings (ESLint,
typescript-eslint, test-utils chains); no forced major downgrade or unsafe
transitive override was applied. npm also warns about the optional macOS
`fsevents@2.3.3` install script. No `--force`/`--legacy-peer-deps` was used.

No root task aliases, lifecycle port validation, generated SDK or live API proxy
are supplied here. Shared root configuration and Hexlet workflow are unchanged.
