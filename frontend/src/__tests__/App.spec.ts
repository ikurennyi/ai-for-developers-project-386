import { describe, it, expect } from 'vitest'

import { mount } from '@vue/test-utils'
import App from '../App.vue'
import router from '../router'

describe('Technical page', () => {
  it('opens the root route with a technical heading', async () => {
    await router.push('/')
    await router.isReady()
    const wrapper = mount(App, { global: { plugins: [router] } })

    expect(wrapper.get('h1').text()).toBe('Calendar — technical scaffold')
    wrapper.unmount()
  })

  it('makes clear that API integration has not been checked', async () => {
    await router.push('/')
    await router.isReady()
    const wrapper = mount(App, { global: { plugins: [router] } })

    expect(wrapper.get('[role="alert"]').text()).toContain('API connection not checked')
    wrapper.unmount()
  })
})
