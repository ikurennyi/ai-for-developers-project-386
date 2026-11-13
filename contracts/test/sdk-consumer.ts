import { getHealth, listMeetingTypes, type Health, type MeetingType } from './sdk';

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

async function readMeetingTypes(): Promise<MeetingType[]> {
  const response = await listMeetingTypes({ throwOnError: true });
  return response.data.meetingTypes;
}
void readMeetingTypes;
