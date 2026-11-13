<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { listAdminBookings, type Booking } from '../generated/sdk'
import { requireAdminLogin } from '../admin/session'

const router = useRouter()
const period = ref<'upcoming' | 'past'>('upcoming')
const page = ref(1)
const total = ref(0)
const pageSize = ref(20)
const bookings = ref<Booking[]>([])
const loading = ref(true)
const error = ref('')
const pages = computed(() => Math.max(1, Math.ceil(total.value / pageSize.value)))
const dateFormat = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Europe/Berlin',
  day: 'numeric',
  month: 'long',
  year: 'numeric',
})
const timeFormat = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Europe/Berlin',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})

async function load() {
  loading.value = true
  error.value = ''
  bookings.value = []
  try {
    const result = await listAdminBookings({ query: { period: period.value, page: page.value } })
    if (result.response?.status === 401) return await requireAdminLogin(router)
    if (!result.response?.ok || !result.data) throw new Error('Unable to load bookings')
    bookings.value = result.data.bookings
    total.value = result.data.total
    pageSize.value = result.data.pageSize
  } catch {
    error.value = 'Unable to load bookings. Please try again.'
  } finally {
    loading.value = false
  }
}

function choosePeriod(value: 'upcoming' | 'past') {
  period.value = value
  page.value = 1
  void load()
}

function choosePage(value: number) {
  page.value = value
  void load()
}

onMounted(load)
</script>

<template>
  <section>
    <h1>Bookings</h1>
    <div class="controls" aria-label="Booking period">
      <button
        :aria-pressed="period === 'upcoming'"
        :disabled="loading"
        @click="choosePeriod('upcoming')"
      >
        Upcoming
      </button>
      <button :aria-pressed="period === 'past'" :disabled="loading" @click="choosePeriod('past')">
        Past
      </button>
    </div>
    <p>Europe/Berlin</p>
    <p v-if="loading" role="status">Loading bookings…</p>
    <div v-else-if="error" role="alert">
      <p>{{ error }}</p>
      <button @click="load">Retry</button>
    </div>
    <p v-else-if="total === 0">No {{ period }} bookings.</p>
    <template v-else>
      <table>
        <caption>
          {{
            period === 'past' ? 'Past bookings' : 'Upcoming bookings'
          }}
        </caption>
        <thead>
          <tr>
            <th scope="col">Meeting</th>
            <th scope="col">Date and time</th>
            <th scope="col">Guest</th>
            <th scope="col">Notes</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="booking in bookings" :key="booking.id">
            <td data-label="Meeting">
              <strong>{{ booking.meetingName }}</strong>
              <p class="plain-text">{{ booking.meetingDescription }}</p>
              <p>{{ booking.durationMinutes }} minutes</p>
            </td>
            <td data-label="Date and time">
              {{ dateFormat.format(new Date(booking.startsAt)) }}
              <p>
                {{ timeFormat.format(new Date(booking.startsAt)) }}–{{
                  timeFormat.format(new Date(booking.endsAt))
                }}
              </p>
            </td>
            <td data-label="Guest">
              {{ booking.guestName }}
              <p>{{ booking.guestEmail }}</p>
            </td>
            <td data-label="Notes">
              <details v-if="booking.notes.length > 160">
                <summary>Show full notes</summary>
                <p class="notes plain-text">{{ booking.notes }}</p>
              </details>
              <p v-else class="notes plain-text">{{ booking.notes || 'No notes.' }}</p>
            </td>
          </tr>
        </tbody>
      </table>
      <nav class="controls" aria-label="Booking pages">
        <button :disabled="page <= 1" @click="choosePage(page - 1)">Previous page</button>
        <p role="status">Page {{ page }} of {{ pages }} · {{ total }} bookings</p>
        <button :disabled="page >= pages" @click="choosePage(page + 1)">Next page</button>
      </nav>
    </template>
  </section>
</template>

<style scoped>
table {
  width: 100%;
  table-layout: fixed;
  border-collapse: collapse;
}
th,
td {
  text-align: left;
  vertical-align: top;
  padding: 0.75rem;
  border-bottom: 1px solid #aaa;
  overflow-wrap: anywhere;
}
.plain-text {
  white-space: pre-wrap;
}
.controls {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.75rem;
  margin-block: 1rem;
}
button[aria-pressed='true'] {
  font-weight: bold;
  border-bottom: 3px solid #165dcc;
}
summary {
  cursor: pointer;
}
:focus-visible {
  outline: 3px solid #165dcc;
  outline-offset: 3px;
}
@media (max-width: 600px) {
  table,
  tbody,
  tr,
  td {
    display: block;
    width: auto;
  }
  thead {
    display: none;
  }
  tr {
    border: 1px solid #aaa;
    margin-block: 1rem;
  }
  td::before {
    content: attr(data-label);
    display: block;
    font-weight: bold;
    margin-bottom: 0.5rem;
  }
}
</style>
