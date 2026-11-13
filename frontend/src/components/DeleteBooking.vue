<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { deleteAdminBooking, type Booking } from '../generated/sdk'
import { adminRequestHeaders, requireAdminLogin } from '../admin/session'

const props = defineProps<{ booking: Booking }>()
const emit = defineEmits<{ deleted: [] }>()
const router = useRouter()
const dialog = ref<HTMLDialogElement>()
const pending = ref(false)
const error = ref('')
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

function open() {
  error.value = ''
  dialog.value?.showModal()
}

async function remove() {
  if (pending.value) return
  pending.value = true
  error.value = ''
  try {
    const result = await deleteAdminBooking({
      path: { id: props.booking.id },
      headers: adminRequestHeaders,
    })
    if (result.response?.status === 401) {
      dialog.value?.close()
      return await requireAdminLogin(router)
    }
    if (result.response?.status !== 204) throw new Error('Deletion failed')
    dialog.value?.close()
    emit('deleted')
  } catch {
    error.value = 'Unable to delete booking. The result was not confirmed. Please try again.'
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <button @click="open">Delete booking</button>
  <dialog ref="dialog" aria-label="Delete booking?" @cancel="pending && $event.preventDefault()">
    <h2>Delete booking?</h2>
    <p>{{ booking.meetingName }}</p>
    <p>{{ dateFormat.format(new Date(booking.startsAt)) }}</p>
    <p>
      {{ timeFormat.format(new Date(booking.startsAt)) }}–{{
        timeFormat.format(new Date(booking.endsAt))
      }}
      · Europe/Berlin
    </p>
    <p>{{ booking.guestName }}</p>
    <p>This permanently deletes the booking. It cannot be restored.</p>
    <p v-if="error" role="alert">{{ error }}</p>
    <button :disabled="pending" autofocus @click="dialog?.close()">Cancel</button>
    <button :disabled="pending" @click="remove">
      {{ pending ? 'Deleting…' : 'Delete booking' }}
    </button>
  </dialog>
</template>

<style scoped>
dialog {
  max-width: min(30rem, calc(100vw - 4rem));
  overflow-wrap: anywhere;
}
button {
  margin: 0.25rem;
}
:focus-visible {
  outline: 3px solid #165dcc;
  outline-offset: 3px;
}
</style>
