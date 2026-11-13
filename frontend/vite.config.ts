import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

const isSmokeRun = process.env.SMOKE_RUNTIME_DIR !== undefined

// https://vite.dev/config/
export default defineConfig({
  server: {
    host: '127.0.0.1',
    strictPort: true,
    proxy: process.env.BACKEND_PORT
      ? { '/api/v1': { target: `http://127.0.0.1:${process.env.BACKEND_PORT}` } }
      : undefined,
  },
  preview: { host: '127.0.0.1', strictPort: true },
  plugins: [vue(), ...(isSmokeRun ? [] : [vueDevTools()])],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
