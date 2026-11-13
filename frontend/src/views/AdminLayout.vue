<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { hasAdminSession, logOut, requireAdminLogin } from '../admin/session'

const router = useRouter()
const error = ref('')
const pending = ref(false)

async function logout() {
  pending.value = true
  error.value = ''
  try {
    await logOut(router)
  } catch {
    error.value = 'Unable to log out. Please try again.'
  } finally {
    pending.value = false
  }
}

async function checkSession() {
  try {
    if (!(await hasAdminSession())) await requireAdminLogin(router)
  } catch {
    error.value = 'Unable to check administrator access. Please try again.'
  }
}

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  window.addEventListener('focus', checkSession)
  timer = setInterval(checkSession, 30_000)
})
onUnmounted(() => {
  window.removeEventListener('focus', checkSession)
  clearInterval(timer)
})
</script>

<template>
  <div class="admin-layout">
    <header>
      <RouterLink to="/">Calendar</RouterLink>
      <nav aria-label="Administrator">
        <RouterLink to="/admin">Home</RouterLink>
        <RouterLink to="/admin/links">Links</RouterLink>
        <RouterLink to="/admin/bookings">Bookings</RouterLink>
      </nav>
      <button data-test="logout" :disabled="pending" @click="logout">Log out</button>
    </header>
    <p v-if="error" role="alert">{{ error }}</p>
    <main><RouterView :key="$route.path" /></main>
  </div>
</template>

<style scoped>
.admin-layout {
  max-width: 70rem;
  margin: auto;
  padding: 1rem;
}
header,
nav {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 1rem;
}
:focus-visible {
  outline: 3px solid #165dcc;
  outline-offset: 3px;
}
</style>
