# API contracts (T2)

`main.tsp` is the editable API source. The official TypeSpec OpenAPI emitter
produces `generated/openapi.json` (OpenAPI 3.0.0). Do not edit generated files.
The health response is HTTP 200, `application/json`, exactly `{ "status": "ok" }`.
Its schema forbids extra properties (`additionalProperties: { not: {} }` is the
emitter's OpenAPI 3.0 representation of an impossible extra-property schema).

## Commands

Use the pinned mise tools; commands below run from the repository root:

```sh
mise exec -- npm --prefix contracts ci
mise exec -- npm --prefix contracts run generate
mise exec -- npm --prefix contracts run check
mise exec -- npm --prefix contracts test
```

- `generate` compiles TypeSpec and generates a Fetch SDK temporarily, then updates
  only the tracked OpenAPI. No Rails or Vue installation is needed.
- `check` regenerates OpenAPI and the entire SDK twice in independent temporary
  directories, compares every file byte-for-byte, checks tracked OpenAPI drift,
  runs vacuum (warnings fail), and strictly typechecks the generated SDK and a
  consumer fixture with TypeScript. It never overwrites tracked artifacts.
- `test` checks the health contract and the check command, including controlled
  failures for invalid TypeSpec, OpenAPI drift, vacuum warnings, invalid SDK
  consumption and nondeterministic SDK output. Probes mutate disposable copies,
  never repository files. Temporary directories are cleaned on success/failure.

To retain both artifacts for inspection or T6 integration, supply a dedicated
output directory (relative paths resolve from `contracts/` with npm's `--prefix`):

```sh
mise exec -- npm --prefix contracts run generate -- --output /absolute/temporary/output
```

The directory contains `openapi.json` and `sdk/` (including bundled Fetch client
and core support). This mode does not update the tracked OpenAPI. T6 owns placing
the SDK in frontend and adding SDK drift comparison there; T2 deliberately does
not write to frontend. Root mise aliases also belong to later integration tasks.
The generated operation is `getHealth`; the client default `baseUrl` is `/api/v1`
and its operation path is `/health`, so the prefix appears exactly once. Consumers
can use `getHealth({ throwOnError: true })` and read `response.data.status`.

## Pins and compatibility

The independent manifest/lockfile pin npm 11.19.1, TypeSpec compiler/http/openapi/
official OpenAPI 3 emitter 1.18.0, Hey API 0.99.0 and TypeScript 6.0.3. Node 24.22.2
and vacuum 0.39.3 come from the root mise toolchain. All were exercised together
on macOS arm64, not merely declared.

Hey API's JSON Schema ref parser pins vulnerable `js-yaml` 4.1.1 upstream. The
narrow package override pins its compatible 4.x patch to 4.3.2, addressing
GHSA-52cp-r559-cp3m, GHSA-5p4m-2wfm-xmqj and GHSA-2883-xcg3-v3hh. Installation,
generation, strict compilation and failure probes pass with this override;
`npm audit` reports zero known vulnerabilities. Remove/reassess the override when
the upstream parser updates. No floating generator or root npm workspace is used.
