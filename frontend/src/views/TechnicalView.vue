<script setup lang="ts">
import { ElAlert, ElCard } from 'element-plus'
</script>

<template>
  <main>
    <ElCard>
      <h1>Calendar — technical scaffold</h1>
      <ElAlert title="API connection not checked" type="info" :closable="false">
        Live API integration is a separate task. This page does not make an API request.
      </ElAlert>
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
