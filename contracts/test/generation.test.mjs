import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cp, mkdtemp, readFile, rename, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);

test('generation publishes the agreed health response as OpenAPI 3.0', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'calendar-contract-test-'));
  try {
    const result = spawnSync(process.execPath, ['scripts/generate.mjs', '--output', directory], {
      cwd: root,
      encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const document = JSON.parse(await readFile(join(directory, 'openapi.json'), 'utf8'));
    assert.equal(document.openapi, '3.0.0');
    assert.deepEqual(document.servers.map(({ url }) => url), ['/api/v1']);
    assert.deepEqual(Object.keys(document.paths), ['/health']);
    const health = document.paths['/health'].get;
    assert.equal(health.operationId, 'getHealth');
    assert.deepEqual(Object.keys(health.responses), ['200']);
    assert.deepEqual(Object.keys(health.responses['200'].content), ['application/json']);
    const schema = document.components.schemas.Health;
    assert.deepEqual(schema.additionalProperties, { not: {} });
    assert.deepEqual(schema.required, ['status']);
    assert.deepEqual(Object.keys(schema.properties), ['status']);
    assert.equal(schema.properties.status.type, 'string');
    assert.deepEqual(schema.properties.status.enum, ['ok']);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

// Each probe owns its copy; tracked sources/artifacts are never deliberately broken.
async function withFixture(probe) {
  const directory = await mkdtemp(join(tmpdir(), 'calendar-contract-probe-'));
  try {
    await cp(root, directory, {
      recursive: true,
      filter: (source) => !source.includes('node_modules'),
    });
    await symlink(fileURLToPath(new URL('node_modules', root)), join(directory, 'node_modules'), 'dir');
    const run = (script) => spawnSync(process.execPath, [`scripts/${script}.mjs`], {
      cwd: directory,
      encoding: 'utf8',
    });
    await probe(directory, run);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

test('check rejects artifact drift without fixing it', () => withFixture(async (directory, run) => {
  const artifact = join(directory, 'generated/openapi.json');
  await writeFile(artifact, '{}\n');
  const result = run('check');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /OpenAPI drift/);
  assert.equal(await readFile(artifact, 'utf8'), '{}\n');
}));

test('invalid TypeSpec fails generation', () => withFixture(async (directory, run) => {
  await writeFile(join(directory, 'main.tsp'), 'this is not valid TypeSpec !');
  const result = run('generate');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /TypeSpec failed/);
}));

test('check propagates vacuum failures on freshly generated OpenAPI', () => withFixture(async (directory, run) => {
  const source = join(directory, 'main.tsp');
  await writeFile(source, (await readFile(source, 'utf8')).replace('@tag("Health")\n', ''));
  const generation = run('generate');
  assert.equal(generation.status, 0, generation.stdout + generation.stderr);
  const result = run('check');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /vacuum failed/);
}));

test('check rejects invalid generated SDK consumption', () => withFixture(async (directory, run) => {
  await writeFile(join(directory, 'test/sdk-consumer.ts'),
    "import type { Health } from './sdk';\nconst response: Health = { status: 'broken' };\nvoid response;\n");
  const result = run('check');
  assert.notEqual(result.status, 0);
  assert.match(result.stdout, /not assignable to type '"ok"'/);
}));

test('check rejects nondeterministic SDK artifacts', () => withFixture(async (directory, run) => {
  await rename(join(directory, 'scripts/generate.mjs'), join(directory, 'scripts/real-generate.mjs'));
  // Fault injection after real generation, restricted to this disposable fixture.
  await writeFile(join(directory, 'scripts/generate.mjs'), `
await import('./real-generate.mjs');
const { writeFile } = await import('node:fs/promises');
const { randomUUID } = await import('node:crypto');
const output = process.argv[process.argv.indexOf('--output') + 1];
await writeFile(output + '/sdk/nondeterministic.txt', randomUUID());
`);
  const result = run('check');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Generation is not reproducible: sdk.*nondeterministic/);
}));

test('check validates reproducible OpenAPI and a strict Fetch SDK without rewriting artifacts', async () => {
  const before = await readFile(new URL('../generated/openapi.json', import.meta.url));
  const result = spawnSync(process.execPath, ['scripts/check.mjs'], {
    cwd: root,
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.deepEqual(await readFile(new URL('../generated/openapi.json', import.meta.url)), before);
});
