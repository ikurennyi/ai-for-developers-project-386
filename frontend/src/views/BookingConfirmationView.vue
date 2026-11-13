<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { confirmedBooking } from '../guest/state'

const route = useRoute()
const booking = computed(() => confirmedBooking(String(route.params.token)))

function dateTime(value: string) {
  return new Intl.DateTimeFormat('en-GB', {
    dateStyle: 'full',
    timeStyle: 'short',
    timeZone: 'Europe/Berlin',
    hourCycle: 'h23',
  }).format(new Date(value))
}
</script>

<template>
  <main class="confirmation-page">
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
    <section v-else>
      <h1>Confirmation unavailable in this tab</h1>
      <p>Booking details are only available in the tab that confirmed the meeting.</p>
      <RouterLink to="/book">Choose a meeting type</RouterLink>
    </section>
  </main>
</template>

<style scoped>
.confirmation-page {
  width: min(800px, calc(100% - 32px));
  margin: 32px auto;
  overflow-wrap: anywhere;
}
.plain-text {
  white-space: pre-wrap;
}
a:focus-visible {
  outline: 3px solid #2457d6;
  outline-offset: 3px;
}
</style>
