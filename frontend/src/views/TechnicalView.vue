<script setup lang="ts">
import { ElAlert, ElCard } from 'element-plus'
import { onMounted, ref } from 'vue'
import { getHealth } from '@/generated/sdk'

const state = ref<'loading' | 'healthy' | 'error'>('loading')

onMounted(async () => {
  try {
    const { data } = await getHealth({ throwOnError: true, signal: AbortSignal.timeout(5000) })
    state.value = data.status === 'ok' ? 'healthy' : 'error'
  } catch {
    state.value = 'error'
  }
})
</script>

<template>
  <main>
    <ElCard>
      <h1>Calendar — technical scaffold</h1>
      <ElAlert v-if="state === 'loading'" title="Checking API" type="info" :closable="false" />
      <ElAlert
        v-else-if="state === 'healthy'"
        title="API healthy: ok"
        type="success"
        :closable="false"
      />
      <ElAlert v-else title="API unavailable" type="error" :closable="false" />
    </ElCard>
  </main>
</template>

<style scoped>
main {
  max-width: 48rem;
  margin: 3rem auto;
  padding: 0 1rem;
}
</style>
