import { confirmBooking, type Availability, type CalendarInterval } from '../generated/sdk'
import { pendingBookingAttempt, saveBookingAttempt, type GuestDraft } from './state'

export async function confirmGuestBooking(
  calendar: Availability,
  interval: CalendarInterval,
  guest: GuestDraft,
) {
  const slug = calendar.meetingType.slug
  const attempt = pendingBookingAttempt(slug, interval.startsAt) ?? {
    calendar,
    interval,
    body: {
      ...guest,
      startsAt: interval.startsAt,
      meetingType: calendar.meetingType,
      attemptToken: Array.from(crypto.getRandomValues(new Uint8Array(32)), (byte) =>
        byte.toString(16).padStart(2, '0'),
      ).join(''),
    },
  }
  // Persist before sending: refresh during the request is also uncertain.
  saveBookingAttempt(attempt)
  const result = await confirmBooking({ path: { slug }, body: attempt.body })
  if (!result.response || result.response.status >= 500) throw new Error('Unconfirmed result')
  // Only definitive rejections allow a new logical attempt. Successful state is
  // cleared together with the draft when the private confirmation is saved.
  if (result.error) saveBookingAttempt()
  return result
}
