import { defineConfig, mergeConfig } from 'vitest/config'
import { playwright } from '@vitest/browser-playwright'
import viteConfig from './vite.config.ts'

export default mergeConfig(
  viteConfig,
  defineConfig({
    cacheDir: process.env.SMOKE_RUNTIME_DIR
      ? `${process.env.SMOKE_RUNTIME_DIR}/vite-cache`
      : undefined,
    test: {
      provide: {
        emptyMeetingTypes: process.env.SMOKE_EMPTY_MEETING_TYPES === '1',
      },
      attachmentsDir: process.env.SMOKE_RUNTIME_DIR
        ? `${process.env.SMOKE_RUNTIME_DIR}/attachments`
        : undefined,
      include: ['browser/**/*.spec.ts'],
      testTimeout: 15000,
      expect: { poll: { timeout: 10000 } },
      browser: {
        enabled: true,
        headless: true,
        api: {
          host: '127.0.0.1',
          port: Number(process.env.SMOKE_BROWSER_PORT || 63315),
          strictPort: true,
        },
        screenshotFailures: false,
        provider: playwright(),
        instances: [{ browser: 'chromium' }],
      },
    },
  }),
)
