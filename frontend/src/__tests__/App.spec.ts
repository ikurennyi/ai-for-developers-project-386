import { afterEach, describe, it, expect, vi } from 'vitest'

import { flushPromises, mount } from '@vue/test-utils'
import App from '../App.vue'
import router from '../router'

describe('Technical page', () => {
  afterEach(() => vi.unstubAllGlobals())
  it('opens the root route with a technical heading', async () => {
    await router.push('/')
    await router.isReady()
    const wrapper = mount(App, { global: { plugins: [router] } })

    expect(wrapper.get('h1').text()).toBe('Calendar — technical scaffold')
    wrapper.unmount()
  })

  it('shows loading rather than claiming API success before a response', async () => {
    await router.push('/')
    await router.isReady()
    const wrapper = mount(App, { global: { plugins: [router] } })

    expect(wrapper.get('[role="alert"]').text()).toContain('Checking API')
    wrapper.unmount()
  })

  it('reports an unavailable API without claiming success', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Network unavailable')))
    const NativeRequest = globalThis.Request
    vi.stubGlobal(
      'Request',
      class extends NativeRequest {
        constructor(input: RequestInfo | URL, init?: RequestInit) {
          super(typeof input === 'string' ? new URL(input, 'http://localhost') : input, init)
        }
      },
    )
    await router.push('/')
    await router.isReady()
    const wrapper = mount(App, { global: { plugins: [router] } })
    await flushPromises()

    expect(wrapper.get('[role="alert"]').text()).toContain('API unavailable')
    expect(fetch).toHaveBeenCalledOnce()
    wrapper.unmount()
  })
})
