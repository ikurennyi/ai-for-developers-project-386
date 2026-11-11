import { mount } from '@vue/test-utils'
import { afterEach, expect, it, vi } from 'vitest'
import TechnicalView from '../src/views/TechnicalView.vue'

afterEach(() => vi.unstubAllGlobals())

it('shows real Rails health through the generated SDK and Vite proxy', async () => {
  const origin = process.env.INTEGRATION_FRONTEND_URL
  if (!origin) throw new Error('INTEGRATION_FRONTEND_URL must point to this run’s live Vite server')
  const paths: string[] = []
  const NativeRequest = globalThis.Request

  // Node's Request lacks browser-relative URL resolution. Only resolve URLs;
  // the SDK's fetch remains native and all HTTP responses come from real servers.
  vi.stubGlobal(
    'Request',
    class extends NativeRequest {
      constructor(input: RequestInfo | URL, init?: RequestInit) {
        const resolved = typeof input === 'string' ? new URL(input, origin) : input
        super(resolved, init)
        paths.push(new URL(this.url).pathname)
      }
    },
  )

  const wrapper = mount(TechnicalView)
  try {
    await vi.waitFor(() => expect(wrapper.get('[role="alert"]').text()).toBe('API healthy: ok'), {
      timeout: 8000,
    })
    expect(paths).toEqual(['/api/v1/health'])
  } finally {
    wrapper.unmount()
  }
}, 10000)
