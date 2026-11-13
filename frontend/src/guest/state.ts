import type { Availability, Booking, BookingConfirmation, CalendarInterval } from '../generated/sdk'

export interface BookingAttempt {
  calendar: Availability
  interval: CalendarInterval
  body: BookingConfirmation
}

export interface GuestDraft {
  guestName: string
  guestEmail: string
  notes: string
}

interface GuestState {
  id: string
  generation: number
  drafts: Record<string, GuestDraft>
  confirmation?: { token: string; booking: Booking }
  attempt?: BookingAttempt
}

// Unlike sessionStorage, session history is not copied by window.open(url).
// No guest data or lookup capability lives in URLs or shared browser storage.
const saved = window.history.state?.calendarGuest as GuestState | undefined
const state: GuestState =
  saved && sessionStorage.getItem(`calendar-guest:${saved.id}`) === String(saved.generation)
    ? saved
    : { id: crypto.randomUUID(), generation: 0, drafts: {} }

export function persistGuestState() {
  sessionStorage.setItem(`calendar-guest:${state.id}`, String(state.generation))
  window.history.replaceState(
    { ...window.history.state, calendarGuest: JSON.parse(JSON.stringify(state)) },
    '',
  )
}

export function guestDraft(slug: string): GuestDraft {
  return { ...(state.drafts[slug] ?? { guestName: '', guestEmail: '', notes: '' }) }
}

export function saveGuestDraft(slug: string, draft: GuestDraft) {
  state.drafts[slug] = { ...draft }
  persistGuestState()
}

export function saveConfirmation(booking: Booking) {
  const token = crypto.randomUUID()
  state.drafts = {}
  state.attempt = undefined
  // Old history snapshots must not resurrect a draft after success.
  state.generation++
  state.confirmation = { token, booking }
  persistGuestState()
  return token
}

export function confirmedBooking(token: string) {
  return state.confirmation?.token === token ? state.confirmation.booking : undefined
}

export function pendingBookingAttempt(slug: string, startsAt: string) {
  const attempt = state.attempt
  return attempt?.calendar.meetingType.slug === slug && attempt.interval.startsAt === startsAt
    ? attempt
    : undefined
}

export function saveBookingAttempt(attempt?: BookingAttempt) {
  state.attempt = attempt
  persistGuestState()
}
