<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { listMeetingTypes, type MeetingType } from '../generated/sdk'

const meetingTypes = ref<MeetingType[]>([])
const loading = ref(true)
const failed = ref(false)

async function load() {
  loading.value = true
  failed.value = false
  try {
    const { data } = await listMeetingTypes({ throwOnError: true })
    meetingTypes.value = data.meetingTypes
  } catch {
    failed.value = true
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <header class="site-header">
    <RouterLink class="brand" to="/" aria-label="Calendar home">Calendar</RouterLink>
    <nav aria-label="Main navigation">
      <RouterLink class="nav-link" to="/book">Book a meeting</RouterLink>
      <a class="nav-link admin-link" href="/admin">Admin</a>
    </nav>
  </header>
  <main class="meeting-types-page">
    <h1>Book a meeting</h1>
    <p>Choose a meeting type. No account needed.</p>
    <p v-if="loading" role="status">Loading meeting types…</p>
    <div v-else-if="failed" role="alert">
      <p>We couldn’t load meeting types. Please try again.</p>
      <button type="button" @click="load">Try again</button>
    </div>
    <p v-else-if="meetingTypes.length === 0" role="status">No meeting types available</p>
    <ul v-else class="meeting-type-list">
      <li v-for="meetingType in meetingTypes" :key="meetingType.id">
        <article class="feature-card">
          <h2>{{ meetingType.name }}</h2>
          <p class="meeting-description">{{ meetingType.description }}</p>
          <p>{{ meetingType.durationMinutes }} minutes</p>
        </article>
      </li>
    </ul>
  </main>
</template>

<style scoped>
.meeting-types-page {
  width: min(900px, calc(100% - 40px));
  margin: 48px auto;
}
h1 {
  font-size: clamp(36px, 8vw, 56px);
  letter-spacing: -1.5px;
}
.meeting-type-list {
  list-style: none;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
  gap: 20px;
}
h2 {
  font-size: 24px;
  letter-spacing: -0.5px;
  overflow-wrap: anywhere;
}
.meeting-description {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
button {
  padding: 12px 20px;
  cursor: pointer;
}
</style>
