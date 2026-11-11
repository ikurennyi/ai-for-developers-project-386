import { getHealth, type Health } from './sdk';

// Consumer-level checks: generated types preserve the literal health response.
const healthy: Health = { status: 'ok' };
// @ts-expect-error The contract does not permit arbitrary health statuses.
const unhealthy: Health = { status: 'broken' };
void healthy;
void unhealthy;

async function readHealth() {
  const response = await getHealth({ throwOnError: true });
  const status: 'ok' = response.data.status;
  return status;
}
void readHealth;
