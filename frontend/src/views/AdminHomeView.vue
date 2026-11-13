<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { getAdminHome, type AdminHomeDay } from '../generated/sdk'
import { requireAdminLogin } from '../admin/session'

const router = useRouter()
const days = ref<AdminHomeDay[]>([])
const loading = ref(true)
const error = ref('')
const timeFormat = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Europe/Berlin',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})

function time(instant: string) {
  return timeFormat.format(new Date(instant))
}

async function load() {
  loading.value = true
  error.value = ''
  days.value = []
  try {
    const result = await getAdminHome()
    if (result.response?.status === 401) return await requireAdminLogin(router)
    if (!result.response?.ok || !result.data) throw new Error('Unable to load bookings')
    days.value = result.data.days
  } catch {
    error.value = 'Unable to load bookings. Please try again.'
  } finally {
    loading.value = false
  }
}
onMounted(load)
</script>

<template>
  <section>
    <h1>Home</h1>
    <p>Unfinished bookings · Europe/Berlin</p>
    <p v-if="loading" role="status">Loading bookings…</p>
    <div v-else-if="error" role="alert">
      <p>{{ error }}</p>
      <button @click="load">Retry</button>
    </div>
    <p v-else-if="days.length === 0">No unfinished bookings.</p>
    <section v-for="day in days" v-else :key="day.date" class="booking-day">
      <h2>
        <time :datetime="day.date">{{ day.date }}</time>
      </h2>
      <article v-for="booking in day.bookings" :key="booking.id" class="booking">
        <h3>{{ booking.meetingName }}</h3>
        <p>
          <time :datetime="booking.startsAt">{{ time(booking.startsAt) }}</time>
          –
          <time :datetime="booking.endsAt">{{ time(booking.endsAt) }}</time>
        </p>
        <p>{{ booking.guestName }}</p>
        <p>{{ booking.guestEmail }}</p>
        <p class="notes">{{ booking.notes }}</p>
      </article>
    </section>
  </section>
</template>

<style scoped>
.booking {
  margin-block: 1rem;
  padding: 1rem;
  border: 1px solid #999;
  overflow-wrap: anywhere;
}
.notes {
  white-space: pre-wrap;
}
:focus-visible {
  outline: 3px solid #165dcc;
  outline-offset: 3px;
}
</style>
