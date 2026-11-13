<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref } from 'vue'
import { onBeforeRouteLeave, RouterLink, useRoute, useRouter } from 'vue-router'
import {
  createAdminMeetingType,
  getAdminMeetingType,
  updateAdminMeetingType,
  type MeetingTypeFieldErrors,
} from '../generated/sdk'
import { adminRequestHeaders, requireAdminLogin } from '../admin/session'

const router = useRouter()
const route = useRoute()
const id = typeof route.params.id === 'string' ? route.params.id : ''
const editing = !!id
const draftKey = editing ? `calendar-edit-meeting-type-${id}` : 'calendar-new-meeting-type'
const initial = { name: '', description: '', duration: '', slug: '' }
const form = reactive({ ...initial })
const dirty = computed(() => JSON.stringify(form) !== JSON.stringify(initial))
const errors = ref<MeetingTypeFieldErrors>({})
const error = ref('')
const pending = ref(false)
const loading = ref(editing)
const loadError = ref('')
let saved = false

function length(value: string) {
  return Array.from(value).length
}

function validate() {
  const result: MeetingTypeFieldErrors = {}
  if (length(form.name.trim()) < 1 || length(form.name.trim()) > 100)
    result.name = ['Name must contain 1–100 characters.']
  if (form.description.trim() && length(form.description) > 2000)
    result.description = ['Description must contain at most 2000 characters.']
  if (!/^\d+$/.test(form.duration) || Number(form.duration) < 1 || Number(form.duration) > 540)
    result.durationMinutes = ['Duration must be a whole number from 1 to 540.']
  const slug = form.slug.trim()
  if (length(slug) > 80 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug))
    result.slug = ['Use 1–80 lowercase letters or digits with single hyphens between parts.']
  return result
}

async function save() {
  if (pending.value) return
  errors.value = validate()
  error.value = ''
  if (Object.keys(errors.value).length) return
  pending.value = true
  try {
    const options = {
      headers: adminRequestHeaders,
      body: {
        name: form.name,
        description: form.description,
        durationMinutes: Number(form.duration),
        slug: form.slug,
      },
    }
    const result = editing
      ? await updateAdminMeetingType({ ...options, path: { id } })
      : await createAdminMeetingType(options)
    if (result.response?.status === 401) return await requireAdminLogin(router)
    if (!result.response) throw new Error('Save result unavailable')
    if (result.error) {
      if (
        'errors' in result.error &&
        typeof result.error.errors === 'object' &&
        result.error.errors
      ) {
        for (const field of ['name', 'description', 'durationMinutes', 'slug'] as const) {
          const messages = Reflect.get(result.error.errors, field)
          if (Array.isArray(messages) && messages.every((message) => typeof message === 'string'))
            errors.value[field] = messages
        }
      }
      error.value = result.error.message
      return
    }
    if (!result.data) throw new Error('Save failed')
    saved = true
    sessionStorage.removeItem(draftKey)
    await router.push({ name: 'admin-links' })
  } catch {
    error.value = 'Unable to save the meeting type. Your fields are unchanged. Please try again.'
  } finally {
    pending.value = false
  }
}

onBeforeRouteLeave((to) => {
  if (to.name === 'admin-login') {
    if (dirty.value) sessionStorage.setItem(draftKey, JSON.stringify(form))
    return true
  }
  if (!saved && dirty.value && !window.confirm('Discard unsaved meeting type changes?'))
    return false
  sessionStorage.removeItem(draftKey)
  return true
})
function beforeUnload(event: BeforeUnloadEvent) {
  if (dirty.value && !saved) event.preventDefault()
}
async function load() {
  loading.value = true
  loadError.value = ''
  try {
    const result = await getAdminMeetingType({ path: { id } })
    if (result.response?.status === 401) return await requireAdminLogin(router)
    if (!result.data) throw new Error('Meeting type unavailable')
    Object.assign(initial, {
      name: result.data.name,
      description: result.data.description,
      duration: String(result.data.durationMinutes),
      slug: result.data.slug,
    })
    Object.assign(form, initial)
  } catch {
    loadError.value = 'Unable to load the meeting type. Please try again.'
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  if (editing) await load()
  const stored = sessionStorage.getItem(draftKey)
  if (stored) {
    try {
      const draft: unknown = JSON.parse(stored)
      if (typeof draft === 'object' && draft !== null) {
        for (const key of ['name', 'description', 'duration', 'slug'] as const) {
          const value: unknown = Reflect.get(draft, key)
          if (typeof value === 'string') form[key] = value
        }
      }
    } catch {
      sessionStorage.removeItem(draftKey)
    }
  }
  window.addEventListener('beforeunload', beforeUnload)
})
onUnmounted(() => window.removeEventListener('beforeunload', beforeUnload))
</script>

<template>
  <section>
    <h1>{{ editing ? 'Edit meeting type' : 'New meeting type' }}</h1>
    <p v-if="editing">Save changes details only. Publication is managed separately in Links.</p>
    <p v-else>Save creates a hidden meeting type. It does not publish it.</p>
    <p v-if="loading" role="status">Loading meeting type…</p>
    <div v-else-if="loadError" role="alert">
      <p>{{ loadError }}</p>
      <button @click="load">Retry</button>
      <RouterLink to="/admin/links">Back to Links</RouterLink>
    </div>
    <form v-else novalidate @submit.prevent="save">
      <label for="meeting-name">Name</label>
      <input
        id="meeting-name"
        v-model="form.name"
        :aria-invalid="!!errors.name"
        aria-describedby="name-error"
      />
      <p id="name-error" role="alert">{{ errors.name?.join(' ') }}</p>
      <label for="meeting-description">Description</label>
      <textarea
        id="meeting-description"
        v-model="form.description"
        :aria-invalid="!!errors.description"
        aria-describedby="description-error"
      />
      <p id="description-error" role="alert">{{ errors.description?.join(' ') }}</p>
      <label for="meeting-duration">Duration (minutes)</label>
      <input
        id="meeting-duration"
        v-model="form.duration"
        inputmode="numeric"
        :aria-invalid="!!errors.durationMinutes"
        aria-describedby="duration-error"
      />
      <p id="duration-error" role="alert">{{ errors.durationMinutes?.join(' ') }}</p>
      <label for="meeting-slug">Public address</label>
      <input
        id="meeting-slug"
        v-model="form.slug"
        :aria-invalid="!!errors.slug"
        aria-describedby="slug-error"
        autocapitalize="none"
        spellcheck="false"
      />
      <p id="slug-error" role="alert">{{ errors.slug?.join(' ') }}</p>
      <p v-if="error" role="alert">{{ error }}</p>
      <button type="submit" :disabled="pending">{{ pending ? 'Saving…' : 'Save' }}</button>
      <RouterLink to="/admin/links">Cancel</RouterLink>
    </form>
  </section>
</template>

<style scoped>
form {
  display: grid;
  gap: 0.5rem;
  max-width: 35rem;
}
input,
textarea {
  box-sizing: border-box;
  width: 100%;
  padding: 0.6rem;
  font: inherit;
}
:focus-visible {
  outline: 3px solid #165dcc;
  outline-offset: 3px;
}
[role='alert'] {
  margin: 0;
  overflow-wrap: anywhere;
}
</style>
