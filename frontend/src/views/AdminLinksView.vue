<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { listAdminMeetingTypes, type AdminMeetingType } from '../generated/sdk'
import { requireAdminLogin } from '../admin/session'

const router = useRouter()
const types = ref<AdminMeetingType[]>([])
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    const result = await listAdminMeetingTypes()
    if (result.response?.status === 401) return await requireAdminLogin(router)
    if (!result.data) throw new Error('Unable to load meeting types.')
    types.value = result.data.meetingTypes
  } catch {
    error.value = 'Unable to load meeting types. Please try again.'
  } finally {
    loading.value = false
  }
}
onMounted(load)
</script>

<template>
  <section>
    <h1>Links</h1>
    <RouterLink to="/admin/links/new">Create meeting type</RouterLink>
    <p v-if="loading" role="status">Loading meeting types…</p>
    <div v-else-if="error" role="alert">
      <p>{{ error }}</p>
      <button @click="load">Retry</button>
    </div>
    <p v-else-if="types.length === 0">No meeting types yet.</p>
    <ul v-else>
      <li v-for="type in types" :key="type.id">
        <h2>{{ type.name }}</h2>
        <p>{{ type.description }}</p>
        <p>
          {{ type.durationMinutes }} minutes ·
          <span>{{ type.published ? 'Published' : 'Hidden' }}</span>
        </p>
        <a :href="`/book/${type.slug}`">{{ `/book/${type.slug}` }}</a>
      </li>
    </ul>
  </section>
</template>

<style scoped>
li {
  margin-block: 1rem;
  overflow-wrap: anywhere;
}
</style>
