import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFile, mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const temporary = await mkdtemp(join(tmpdir(), 'calendar-contract-check-'));

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status})`);
}

async function files(directory, prefix = '') {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const name = join(prefix, entry.name);
    if (entry.isDirectory()) result.push(...await files(join(directory, entry.name), name));
    else result.push(name);
  }
  return result.sort();
}

try {
  const first = join(temporary, 'first');
  const second = join(temporary, 'second');
  for (const output of [first, second]) {
    run(process.execPath, [join(root, 'scripts/generate.mjs'), '--output', output]);
  }
  const generatedFiles = await files(first);
  assert.deepEqual(await files(second), generatedFiles, 'Generated file list is not reproducible');
  for (const name of generatedFiles) {
    assert.deepEqual(await readFile(join(first, name)), await readFile(join(second, name)),
      `Generation is not reproducible: ${name}`);
  }
  assert.deepEqual(await readFile(join(first, 'openapi.json')),
    await readFile(join(root, 'generated/openapi.json')),
    'OpenAPI drift: run npm run generate in contracts/');
  run('vacuum', ['lint', '--no-banner', '--fail-severity', 'warn', join(first, 'openapi.json')]);
  await copyFile(join(root, 'test/sdk-consumer.ts'), join(first, 'sdk-consumer.ts'));
  run(process.execPath, [
    join(root, 'node_modules/typescript/bin/tsc'),
    '--strict', '--noEmit', '--target', 'ES2022', '--module', 'ESNext',
    '--moduleResolution', 'Bundler', '--lib', 'ES2022,DOM,DOM.Iterable',
    join(first, 'sdk-consumer.ts'),
  ]);
  console.log('Contracts pass: OpenAPI lint, drift, SDK strict types, byte-identical regeneration.');
} finally {
  await rm(temporary, { recursive: true, force: true });
}
