<script setup lang="ts">
import { ref } from 'vue'
import {
  confirmBooking,
  type Availability,
  type Booking,
  type CalendarInterval,
  type GuestErrors,
} from '../generated/sdk'

const props = defineProps<{ calendar: Availability; interval: CalendarInterval }>()
const guestName = ref('')
const guestEmail = ref('')
const notes = ref('')
const errors = ref<GuestErrors>({})
const pending = ref(false)
const message = ref('')
const booking = ref<Booking>()

function fieldError(value: unknown) {
  return typeof value === 'string' ? value : undefined
}
function fieldErrors(value: unknown): GuestErrors {
  if (!value || typeof value !== 'object') return {}
  return {
    guestName: 'guestName' in value ? fieldError(value.guestName) : undefined,
    guestEmail: 'guestEmail' in value ? fieldError(value.guestEmail) : undefined,
    notes: 'notes' in value ? fieldError(value.notes) : undefined,
  }
}
function length(value: string) {
  return Array.from(value).length
}
function dateTime(value: string) {
  return new Intl.DateTimeFormat('en-GB', {
    dateStyle: 'full',
    timeStyle: 'short',
    timeZone: 'Europe/Berlin',
    hourCycle: 'h23',
  }).format(new Date(value))
}
async function confirm() {
  if (pending.value || booking.value) return
  errors.value = {}
  if (length(guestName.value.trim()) < 1 || length(guestName.value.trim()) > 100) {
    errors.value.guestName = 'Enter your name (1–100 characters).'
  }
  if (
    length(guestEmail.value) > 254 ||
    guestEmail.value !== guestEmail.value.trim() ||
    !/^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/u.test(
      guestEmail.value,
    )
  ) {
    errors.value.guestEmail = 'Enter a valid email address (up to 254 characters).'
  }
  if (length(notes.value) > 2000) errors.value.notes = 'Use at most 2000 characters.'
  if (Object.keys(errors.value).length) return
  pending.value = true
  message.value = ''
  try {
    const { data, error } = await confirmBooking({
      path: { slug: props.calendar.meetingType.slug },
      body: {
        startsAt: props.interval.startsAt,
        meetingType: props.calendar.meetingType,
        guestName: guestName.value,
        guestEmail: guestEmail.value,
        notes: notes.value,
      },
    })
    if (data) {
      booking.value = data
      guestName.value = ''
      guestEmail.value = ''
      notes.value = ''
    } else if (error) {
      message.value = error.message
      if ('errors' in error) errors.value = fieldErrors(error.errors)
    } else {
      throw new Error('Unconfirmed result')
    }
  } catch {
    message.value = 'We couldn’t confirm the result. Please try again.'
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <section v-if="booking" class="booking-success" aria-labelledby="success-heading">
    <h2 id="success-heading">This meeting is scheduled</h2>
    <p>{{ booking.meetingName }}</p>
    <p class="plain-text">{{ booking.meetingDescription }}</p>
    <p>Host: {{ booking.hostName }}</p>
    <p>{{ dateTime(booking.startsAt) }} – {{ dateTime(booking.endsAt) }} Europe/Berlin</p>
    <p>{{ booking.durationMinutes }} minutes</p>
    <p>Your name: {{ booking.guestName }}</p>
    <p>Email address: {{ booking.guestEmail }}</p>
    <p class="plain-text">Additional notes: {{ booking.notes }}</p>
    <p>No confirmation email will be sent.</p>
    <RouterLink class="book-another" to="/book">Book another meeting</RouterLink>
  </section>
  <section v-else aria-labelledby="guest-heading">
    <h2 id="guest-heading">Guest details</h2>
    <p>Your selection is not reserved.</p>
    <form novalidate @submit.prevent="confirm">
      <label for="guest-name">Your name</label>
      <input
        id="guest-name"
        v-model="guestName"
        name="guestName"
        autocomplete="name"
        :disabled="pending"
        :aria-invalid="!!errors.guestName"
        aria-describedby="guest-name-error"
      />
      <p v-if="errors.guestName" id="guest-name-error" role="alert">{{ errors.guestName }}</p>
      <label for="guest-email">Email address</label>
      <input
        id="guest-email"
        v-model="guestEmail"
        name="guestEmail"
        type="email"
        autocomplete="email"
        :disabled="pending"
        :aria-invalid="!!errors.guestEmail"
        aria-describedby="guest-email-error"
      />
      <p v-if="errors.guestEmail" id="guest-email-error" role="alert">{{ errors.guestEmail }}</p>
      <label for="guest-notes">Additional notes (optional)</label>
      <textarea
        id="guest-notes"
        v-model="notes"
        name="notes"
        rows="5"
        :disabled="pending"
        :aria-invalid="!!errors.notes"
        aria-describedby="notes-error"
      ></textarea>
      <p v-if="errors.notes" id="notes-error" role="alert">{{ errors.notes }}</p>
      <p v-if="message" role="alert">{{ message }}</p>
      <RouterLink
        v-if="!pending"
        class="back-calendar"
        :to="{
          name: 'meeting-calendar',
          params: { slug: $route.params.slug },
          query: $route.query,
        }"
        >← Back to calendar</RouterLink
      >
      <RouterLink v-if="message === 'Meeting type unavailable'" to="/book"
        >Choose a meeting type</RouterLink
      >
      <button type="submit" :disabled="pending">
        {{ pending ? 'Confirming…' : 'Confirm booking' }}
      </button>
    </form>
  </section>
</template>

<style scoped>
form {
  display: grid;
  gap: 12px;
}
input,
textarea,
button {
  box-sizing: border-box;
  width: 100%;
  min-height: 44px;
  padding: 10px;
  font: inherit;
}
input,
textarea {
  border: 1px solid #64748b;
  border-radius: 6px;
}
button {
  cursor: pointer;
}
:focus-visible {
  outline: 3px solid #2457d6;
  outline-offset: 3px;
}
.plain-text {
  white-space: pre-wrap;
}
</style>
