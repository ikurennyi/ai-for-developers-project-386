# Frontend

Independent Vue 3 + Vue Router + strict TypeScript project. The root technical
page uses real Element Plus components and the checked-in generated Fetch SDK.
It shows loading, live API health, or an unavailable state; success is never mocked.

## Provenance

Generated using the official pinned generator, from the repository root:

```sh
mise exec -- npm exec --yes --package=create-vue@3.24.0 -- create-vue frontend --ts --router --vitest --eslint --prettier --bare
```

Direct dependencies are exact and `package-lock.json` is independent of other
modules. TypeScript 6.0.3 resolves the generator's `~6.0.0` range (6.0.0 is not
published); Vite 8.3.8 and Vitest 4.1.12 replace vulnerable generated defaults.

## Commands

Run from `frontend/`, with the repository's pinned mise tools:

```sh
mise exec -- npm ci
mise exec -- npm run lint
mise exec -- npm run format
mise exec -- npm run type-check
mise exec -- npm test
mise exec -- npm run build
```

Checks do not fix or stage files. `npm run format:write` explicitly formats files;
`npm run test:watch` is the optional interactive runner. `build` includes type
checking; `build-only` is the Vite-only primitive.

Development: with `BACKEND_PORT` exported, run
`mise exec -- npm run dev -- --port "$FRONTEND_PORT"`.
Vite binds loopback and fails rather than choosing another occupied port. The
lifecycle owner supplies/validates per-worktree ports. When `BACKEND_PORT` is set,
Vite proxies `/api/v1` unchanged to `http://127.0.0.1:$BACKEND_PORT`. The SDK's
relative base URL is `/api/v1` and operation path is `/health`: do not add the
prefix again. Without the backend port, independent checks/builds still work,
but the page cannot claim live health. The deployment server must provide the
equivalent same-origin API routing; the Vite proxy is development-only.

## Live integration check

Start real Rails and Vite on this run's private ports/database, then run:

```sh
INTEGRATION_FRONTEND_URL="http://127.0.0.1:$FRONTEND_PORT" mise exec -- npm run test:integration
```

This separate, bounded Vitest check mounts the real page in jsdom, uses native
HTTP fetch through the live Vite proxy to Rails, and asserts the request path is
exactly `/api/v1/health`. Its only Node adapter resolves relative Request URLs as
a browser would; no server, response, or successful SDK result is mocked.
Missing configuration, an unreachable API or a bad response fails the check.
It does not start services, replace the later Chromium smoke gate, or depend on
shared dev daemons. Ordinary `npm test` remains backend-independent and tests
loading/network-failure UI only. The root owner can invoke the live command from
an isolated service runner; `frontend:test` should retain `npm test`.

Regenerate the SDK using `npm --prefix contracts run generate` from the repository
root; do not format/edit `src/generated/sdk`. Strict type checks include it, while
ESLint/Prettier leave generator-owned formatting intact. The contracts check
detects missing, modified and extra generated files without rewriting them.

VS Code: use Vue (Official) for `.vue` language support.
