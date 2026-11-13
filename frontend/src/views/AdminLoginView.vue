<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { loginAdmin } from '../generated/sdk'
import { adminRequestHeaders, adminReturnTarget } from '../admin/session'

const route = useRoute()
const router = useRouter()
const username = ref('')
const password = ref('')
const error = ref('')
const pending = ref(false)

async function submit() {
  if (pending.value) return
  pending.value = true
  error.value = ''
  try {
    const { response } = await loginAdmin({
      headers: adminRequestHeaders,
      body: { username: username.value, password: password.value },
    })
    if (response?.status === 401) error.value = 'Invalid username or password'
    else if (response?.status === 429)
      error.value = 'Too many login attempts. Please try again later.'
    else if (!response?.ok) error.value = 'Unable to log in. Please try again.'
    else await router.replace(adminReturnTarget(route.query.returnTo))
  } catch {
    error.value = 'Unable to log in. Please try again.'
  } finally {
    password.value = ''
    pending.value = false
  }
}
</script>

<template>
  <main class="admin-login">
    <RouterLink to="/">Calendar</RouterLink>
    <h1>Administrator login</h1>
    <form @submit.prevent="submit">
      <label for="admin-username">Username</label>
      <input
        id="admin-username"
        v-model="username"
        name="username"
        autocomplete="username"
        required
      />
      <label for="admin-password">Password</label>
      <input
        id="admin-password"
        v-model="password"
        name="password"
        type="password"
        autocomplete="current-password"
        required
      />
      <p v-if="error" role="alert">{{ error }}</p>
      <button type="submit" :disabled="pending">{{ pending ? 'Logging in…' : 'Log in' }}</button>
    </form>
  </main>
</template>

<style scoped>
.admin-login {
  max-width: 26rem;
  margin: 3rem auto;
  padding: 1rem;
}
form {
  display: grid;
  gap: 0.75rem;
}
input,
button {
  padding: 0.75rem;
  font: inherit;
}
:focus-visible {
  outline: 3px solid #165dcc;
  outline-offset: 3px;
}
[role='alert'] {
  color: #a01616;
}
</style>
