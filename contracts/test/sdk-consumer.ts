import { getHealth, loginAdmin, getAdminSession, logoutAdmin, type Health } from './sdk';

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

// Authentication is a real SDK consumer as well, not handwritten fetch shapes.
async function authenticate() {
  const login = await loginAdmin({
    headers: { 'X-Calendar-Request': '1' },
    body: { username: 'operator-example', password: 'not-a-default-password' },
    throwOnError: true,
  });
  const expiry: string = login.data.expiresAt;
  const current = await getAdminSession({ throwOnError: true });
  const username: string = current.data.username;
  await logoutAdmin({ headers: { 'X-Calendar-Request': '1' }, throwOnError: true });
  return { expiry, username };
}
void authenticate;
