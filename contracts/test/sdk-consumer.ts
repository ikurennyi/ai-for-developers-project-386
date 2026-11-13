import { confirmBooking, getAvailability, getHealth, loginAdmin, getAdminSession, logoutAdmin, listMeetingTypes, listAdminMeetingTypes, createAdminMeetingType, getAdminMeetingType, updateAdminMeetingType, setAdminMeetingTypePublication, type Availability, type Booking, type Health, type MeetingType } from './sdk';

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

async function readMeetingTypes(): Promise<MeetingType[]> {
  const response = await listMeetingTypes({ throwOnError: true });
  return response.data.meetingTypes;
}
void readMeetingTypes;

async function createHiddenMeetingType() {
  const created = await createAdminMeetingType({
    headers: { 'X-Calendar-Request': '1' },
    body: { name: 'Planning', durationMinutes: 20, slug: 'planning' },
    throwOnError: true,
  });
  const published: boolean = created.data.published;
  const types = await listAdminMeetingTypes({ throwOnError: true });
  return { published, types: types.data.meetingTypes };
}
void createHiddenMeetingType;

async function manageMeetingType(id: string) {
  const current = await getAdminMeetingType({ path: { id }, throwOnError: true });
  const updated = await updateAdminMeetingType({
    path: { id },
    headers: { 'X-Calendar-Request': '1' },
    body: { name: current.data.name, description: '', durationMinutes: 45, slug: 'updated' },
    throwOnError: true,
  });
  const publication = await setAdminMeetingTypePublication({
    path: { id },
    headers: { 'X-Calendar-Request': '1' },
    body: { published: true },
    throwOnError: true,
  });
  const published: boolean = publication.data.published;
  return { slug: updated.data.slug, published };
}
void manageMeetingType;

async function readCalendar(): Promise<Availability> {
  const response = await getAvailability({ path: { slug: 'discussion' }, throwOnError: true });
  const zone: 'Europe/Berlin' = response.data.timeZone;
  const available: boolean | undefined = response.data.days[0]?.intervals[0]?.available;
  void zone;
  void available;
  return response.data;
}
void readCalendar;

async function confirmMeeting(): Promise<Booking> {
  const response = await confirmBooking({
    path: { slug: 'discussion' },
    body: {
      startsAt: '2026-11-13T09:00:00Z',
      meetingType: { name: 'Discussion', description: '', durationMinutes: 20 },
      guestName: 'Guest', guestEmail: 'guest@example.com', notes: '',
    },
    throwOnError: true,
  });
  const zone: 'Europe/Berlin' = response.data.timeZone;
  void zone;
  return response.data;
}
void confirmMeeting;

async function deleteBooking(id: string) {
  const { deleteAdminBooking } = await import('./sdk');
  await deleteAdminBooking({
    path: { id },
    headers: { 'X-Calendar-Request': '1' },
    throwOnError: true,
  });
}
void deleteBooking;

async function readBookingHistory() {
  const { listAdminBookings } = await import('./sdk');
  const response = await listAdminBookings({ query: { period: 'past', page: 2 }, throwOnError: true });
  const bookings: Booking[] = response.data.bookings;
  const pageSize: 20 = response.data.pageSize;
  const total: number = response.data.total;
  return { bookings, pageSize, total };
}
void readBookingHistory;
