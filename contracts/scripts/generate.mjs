import { createClient } from '@hey-api/openapi-ts';
import { spawnSync } from 'node:child_process';
import { copyFile, cp, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const { values } = parseArgs({ options: { output: { type: 'string' } } });
const temporary = await mkdtemp(join(tmpdir(), 'calendar-contract-generate-'));
try {
  const output = values.output ? resolve(values.output) : temporary;
  await mkdir(output, { recursive: true });
  const compilation = spawnSync(process.execPath, [
    join(root, 'node_modules/@typespec/compiler/cmd/tsp.js'),
    'compile', join(root, 'main.tsp'), '--output-dir', output,
    '--warn-as-error',
  ], { cwd: root, stdio: 'inherit' });
  if (compilation.error) throw compilation.error;
  if (compilation.status !== 0) throw new Error(`TypeSpec failed (${compilation.status})`);
  const clients = await createClient({
    input: join(output, 'openapi.json'),
    output: { path: join(output, 'sdk') },
    plugins: ['@hey-api/typescript', '@hey-api/client-fetch', '@hey-api/sdk'],
  });
  if (clients.length !== 1) throw new Error('Hey API did not generate the SDK');
  if (!values.output) {
    const target = join(root, 'generated/openapi.json');
    await mkdir(dirname(target), { recursive: true });
    await copyFile(join(output, 'openapi.json'), target);
    const sdk = join(root, '../frontend/src/generated/sdk');
    await rm(sdk, { recursive: true, force: true });
    await cp(join(output, 'sdk'), sdk, { recursive: true });
  }
} finally {
  await rm(temporary, { recursive: true, force: true });
}
