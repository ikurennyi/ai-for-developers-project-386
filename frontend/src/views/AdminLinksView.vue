<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import {
  listAdminMeetingTypes,
  setAdminMeetingTypePublication,
  type AdminMeetingType,
} from '../generated/sdk'
import { adminRequestHeaders, requireAdminLogin } from '../admin/session'

const router = useRouter()
const types = ref<AdminMeetingType[]>([])
const loading = ref(true)
const error = ref('')
const pending = reactive<Record<string, boolean>>({})
const actionErrors = reactive<Record<string, string>>({})
const copyStatus = reactive<Record<string, string>>({})

async function publication(type: AdminMeetingType) {
  if (pending[type.id]) return
  pending[type.id] = true
  actionErrors[type.id] = ''
  try {
    const result = await setAdminMeetingTypePublication({
      headers: adminRequestHeaders,
      path: { id: type.id },
      body: { published: !type.published },
    })
    if (result.response?.status === 401) return await requireAdminLogin(router)
    if (!result.response?.ok || !result.data) throw new Error('Publication failed')
    // Keep the displayed state unchanged until the server confirms success.
    const index = types.value.findIndex((item) => item.id === type.id)
    if (index !== -1) types.value[index] = result.data
  } catch {
    actionErrors[type.id] =
      'Unable to change publication. The displayed state is unchanged. Please try again.'
  } finally {
    pending[type.id] = false
  }
}

async function copyLink(type: AdminMeetingType) {
  copyStatus[type.id] = ''
  try {
    await navigator.clipboard.writeText(new URL(`/book/${type.slug}`, window.location.origin).href)
    copyStatus[type.id] = 'Link copied.'
  } catch {
    copyStatus[type.id] = 'Unable to copy the link. Please copy the displayed address.'
  }
}

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
        <RouterLink :to="`/admin/links/${type.id}/edit`">Edit</RouterLink>
        <button :disabled="pending[type.id]" @click="publication(type)">
          {{ pending[type.id] ? 'Updating…' : type.published ? 'Hide' : 'Publish' }}
        </button>
        <button @click="copyLink(type)">Copy link</button>
        <p v-if="actionErrors[type.id]" role="alert">{{ actionErrors[type.id] }}</p>
        <p v-if="copyStatus[type.id]" role="status">{{ copyStatus[type.id] }}</p>
      </li>
    </ul>
  </section>
</template>

<style scoped>
li {
  margin-block: 1rem;
  overflow-wrap: anywhere;
}
a,
button {
  margin-inline-end: 0.75rem;
}
:focus-visible {
  outline: 3px solid #165dcc;
  outline-offset: 3px;
}
</style>
