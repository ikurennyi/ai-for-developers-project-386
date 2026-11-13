<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getAvailability, type Availability } from '../generated/sdk'
import GuestBookingForm from './GuestBookingForm.vue'
import { pendingBookingAttempt } from '../guest/state'

const route = useRoute()
const router = useRouter()
const calendar = ref<Availability>()
const loading = ref(true)
const failed = ref(false)
const unavailable = ref(false)
const notice = ref('')
const month = ref('')
let requestId = 0
let loadedSlug = ''

const date = computed(() => (typeof route.query.date === 'string' ? route.query.date : ''))
const start = computed(() => (typeof route.query.start === 'string' ? route.query.start : ''))
const selectedDay = computed(() => calendar.value?.days.find((day) => day.date === date.value))
const selectedInterval = computed(() =>
  selectedDay.value?.intervals.find(
    (interval) => interval.startsAt === start.value && interval.available,
  ),
)
const isForm = computed(() => route.name === 'meeting-form')
const hasAvailability = computed(() =>
  calendar.value?.days.some((day) => day.intervals.some((interval) => interval.available)),
)
const hasDayAvailability = computed(() =>
  selectedDay.value?.intervals.some((interval) => interval.available),
)

// Civil calendar arithmetic uses UTC, not the device's local time zone.
function civilDate(value: string) {
  return new Date(`${value}T12:00:00Z`)
}
function monthOffset(value: string, offset: number) {
  const day = civilDate(`${value}-01`)
  day.setUTCMonth(day.getUTCMonth() + offset)
  return day.toISOString().slice(0, 7)
}
const monthLabel = computed(() =>
  month.value
    ? new Intl.DateTimeFormat('en-GB', {
        month: 'long',
        year: 'numeric',
        timeZone: 'Europe/Berlin',
      }).format(civilDate(`${month.value}-01`))
    : '',
)
const cells = computed(() => {
  if (!month.value) return []
  const first = civilDate(`${month.value}-01`)
  first.setUTCDate(1 - ((first.getUTCDay() + 6) % 7))
  return Array.from({ length: 42 }, (_, index) => {
    const day = new Date(first)
    day.setUTCDate(day.getUTCDate() + index)
    const value = day.toISOString().slice(0, 10)
    return {
      date: value,
      number: day.getUTCDate(),
      outside: !value.startsWith(month.value),
      enabled:
        value.startsWith(month.value) &&
        calendar.value?.days.some((entry) => entry.date === value && entry.workingDay),
    }
  })
})
const previousDisabled = computed(
  () => !calendar.value || month.value <= calendar.value.today.slice(0, 7),
)
const nextDisabled = computed(
  () => !calendar.value || month.value >= calendar.value.windowEnd.slice(0, 7),
)

function formatDate(value: string) {
  return new Intl.DateTimeFormat('en-GB', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'Europe/Berlin',
  }).format(civilDate(value))
}
function formatTime(value: string) {
  return new Intl.DateTimeFormat('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: 'Europe/Berlin',
  }).format(new Date(value))
}
function calendarLocation(query: Record<string, string>) {
  return { name: 'meeting-calendar', params: { slug: route.params.slug }, query }
}
async function load() {
  const id = ++requestId
  const slug = String(route.params.slug)
  loading.value = true
  failed.value = false
  unavailable.value = false
  try {
    const { data, response } = await getAvailability({ path: { slug } })
    if (id !== requestId) return
    const attempt = isForm.value && pendingBookingAttempt(slug, start.value)
    if (attempt) {
      // Availability may now include our own committed booking. Only this
      // tab's unresolved capability can recover it, with explicit confirmation.
      calendar.value = attempt.calendar
      month.value = date.value.slice(0, 7)
      return
    }
    if (response?.status === 404) {
      unavailable.value = true
      calendar.value = undefined
      return
    }
    if (!data) throw new Error('Calendar request failed')
    calendar.value = data
    if (
      loadedSlug !== slug ||
      !month.value ||
      month.value < data.today.slice(0, 7) ||
      month.value > data.windowEnd.slice(0, 7)
    ) {
      month.value = data.today.slice(0, 7)
      loadedSlug = slug
    }
    if (selectedDay.value?.workingDay) month.value = date.value.slice(0, 7)
    if (
      (date.value && !selectedDay.value?.workingDay) ||
      (start.value && !selectedInterval.value) ||
      (isForm.value && !selectedInterval.value)
    ) {
      notice.value = 'This time is no longer available. Please choose another time.'
      await router.replace(
        calendarLocation(selectedDay.value?.workingDay ? { date: date.value } : {}),
      )
    }
  } catch {
    if (id === requestId) failed.value = true
  } finally {
    if (id === requestId) loading.value = false
  }
}
function selectDate(value: string) {
  notice.value = ''
  void router.push(calendarLocation({ date: value }))
}
function selectInterval(value: string) {
  notice.value = ''
  void router.push(calendarLocation({ date: date.value, start: value }))
}
function continueToForm() {
  if (!selectedInterval.value) return
  void router.push({
    name: 'meeting-form',
    params: { slug: route.params.slug },
    query: { date: date.value, start: start.value },
  })
}
watch(() => route.fullPath, load, { immediate: true })
onBeforeUnmount(() => {
  requestId++
})
</script>

<template>
  <main class="calendar-page">
    <RouterLink class="back-types" to="/book">← Back to meeting types</RouterLink>
    <p v-if="loading" role="status">Loading calendar…</p>
    <section v-else-if="unavailable">
      <h1>Meeting type unavailable</h1>
      <RouterLink to="/book">Choose a meeting type</RouterLink>
    </section>
    <section v-else-if="failed" role="alert">
      <h1>We couldn’t load the calendar. Please try again.</h1>
      <button type="button" @click="load">Try again</button>
    </section>
    <template v-else-if="calendar">
      <p v-if="notice" role="alert">{{ notice }}</p>
      <p class="zone">All dates and times: Europe/Berlin · 24-hour time</p>
      <div class="calendar-layout" :class="{ 'form-layout': isForm }">
        <section class="meeting-summary" aria-label="Meeting summary">
          <p>Host: {{ calendar.hostName }}</p>
          <h1>{{ calendar.meetingType.name }}</h1>
          <p class="description">{{ calendar.meetingType.description }}</p>
          <p>{{ calendar.meetingType.durationMinutes }} minutes</p>
          <p>Monday–Friday, 09:00–18:00 Europe/Berlin</p>
          <h2>Your selection</h2>
          <p>{{ selectedDay ? formatDate(selectedDay.date) : 'No date selected' }}</p>
          <p>
            {{
              selectedInterval
                ? `${formatTime(selectedInterval.startsAt)}–${formatTime(selectedInterval.endsAt)} Europe/Berlin`
                : 'No time selected'
            }}
          </p>
        </section>
        <GuestBookingForm
          v-if="isForm && selectedInterval"
          :calendar="calendar"
          :interval="selectedInterval"
        />
        <template v-else>
          <section class="month-calendar" aria-label="Choose a date">
            <div class="month-navigation">
              <button
                type="button"
                aria-label="Previous month"
                :disabled="previousDisabled"
                @click="month = monthOffset(month, -1)"
              >
                ←
              </button>
              <h2 aria-live="polite">{{ monthLabel }}</h2>
              <button
                type="button"
                aria-label="Next month"
                :disabled="nextDisabled"
                @click="month = monthOffset(month, 1)"
              >
                →
              </button>
            </div>
            <div class="date-grid">
              <span
                v-for="weekday in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']"
                :key="weekday"
              >
                {{ weekday }}
              </span>
              <button
                v-for="cell in cells"
                :key="cell.date"
                type="button"
                :data-date="cell.date"
                :disabled="!cell.enabled"
                :class="{ outside: cell.outside, today: cell.date === calendar.today }"
                :aria-label="`${formatDate(cell.date)}${cell.date === calendar.today ? ', Today' : ''}`"
                :aria-current="cell.date === calendar.today ? 'date' : undefined"
                :aria-pressed="date === cell.date"
                @click="selectDate(cell.date)"
              >
                {{ cell.number
                }}<span v-if="cell.date === calendar.today" class="today-label">Today</span>
              </button>
            </div>
            <p>
              Booking window: {{ formatDate(calendar.today) }}–{{ formatDate(calendar.windowEnd) }}
            </p>
          </section>
          <section class="time-selection" aria-labelledby="times-heading">
            <h2 id="times-heading">Choose a time</h2>
            <p v-if="!hasAvailability" role="status">No available times in the next 14 days</p>
            <p v-if="!selectedDay" role="status">Select a date to see available times</p>
            <template v-else>
              <h3>{{ formatDate(selectedDay.date) }}</h3>
              <p v-if="!hasDayAvailability" role="status">No available times on this date</p>
              <ul class="intervals">
                <li v-for="interval in selectedDay.intervals" :key="interval.startsAt">
                  <button
                    type="button"
                    :data-start="interval.startsAt"
                    :disabled="!interval.available"
                    :aria-pressed="start === interval.startsAt"
                    @click="selectInterval(interval.startsAt)"
                  >
                    {{ formatTime(interval.startsAt) }}–{{ formatTime(interval.endsAt) }} ·
                    {{ interval.available ? 'Available' : 'Unavailable' }}
                  </button>
                </li>
              </ul>
            </template>
            <button
              class="continue"
              type="button"
              :disabled="!selectedInterval || !hasAvailability"
              @click="continueToForm"
            >
              Continue
            </button>
          </section>
        </template>
      </div>
    </template>
  </main>
</template>

<style scoped>
.calendar-page {
  width: min(1240px, calc(100% - 32px));
  margin: 32px auto;
  overflow-wrap: anywhere;
}
.calendar-layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.3fr) minmax(0, 1fr);
  gap: 24px;
  align-items: start;
}
.form-layout {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}
section {
  min-width: 0;
}
.description {
  white-space: pre-wrap;
}
.month-navigation {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}
h1 {
  font-size: 28px;
}
h2 {
  font-size: 20px;
}
h3 {
  font-size: 16px;
}
.date-grid {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  gap: 3px;
  text-align: center;
}
button {
  min-height: 44px;
  padding: 8px;
  border: 1px solid #64748b;
  border-radius: 6px;
  background: white;
  color: #172033;
  font: inherit;
  cursor: pointer;
}
button:disabled {
  cursor: default;
  background: #f1f5f9;
  color: #526075;
}
button[aria-pressed='true'] {
  border: 3px solid #2457d6;
  font-weight: bold;
}
button:focus-visible,
a:focus-visible {
  outline: 3px solid #2457d6;
  outline-offset: 3px;
}
.outside {
  opacity: 0.5;
}
.today {
  text-decoration: underline;
}
.today-label {
  display: block;
  font-size: 9px;
}
.intervals {
  list-style: none;
  padding: 4px;
  max-height: 420px;
  overflow-y: auto;
}
.intervals button {
  width: 100%;
  margin-bottom: 6px;
}
.continue {
  margin-top: 16px;
}
.zone {
  font-weight: bold;
}
@media (max-width: 800px) {
  .calendar-layout {
    grid-template-columns: minmax(0, 1fr);
  }
  .intervals {
    max-height: none;
  }
}
</style>
