<script setup lang="ts">
defineProps<{ title: string }>()
</script>

<template>
  <h1>{{ title }}</h1>
  <p>Administrator access is active.</p>
</template>
