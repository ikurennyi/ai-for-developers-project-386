# Frontend

Independent Vue 3 + Vue Router + strict TypeScript project. The root technical
page uses real Element Plus components. It does not request the API or claim
backend health; SDK/live integration belongs to T6.

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

Development: `mise exec -- npm run dev -- --port "$FRONTEND_PORT"`.
Vite binds loopback and fails rather than choosing another occupied port. The
lifecycle owner supplies/validates per-worktree ports; the later contract
integration owns the `/api/v1` proxy and generated SDK.

VS Code: use Vue (Official) for `.vue` language support.
