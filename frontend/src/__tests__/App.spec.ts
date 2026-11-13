import { afterEach, describe, it, expect, vi } from 'vitest'

import { mount } from '@vue/test-utils'
import App from '../App.vue'
import router from '../router'

describe('Home page', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('explains the service and its features in English', async () => {
    await router.push('/')
    await router.isReady()
    const wrapper = mount(App, { global: { plugins: [router] } })

    expect(wrapper.get('h1').text()).toBe('Book a call in minutes')
    expect(wrapper.text()).toContain(
      'Book a meeting in a minute: choose a meeting type and a time that works for you.',
    )
    expect(wrapper.text()).toContain('Features')
    expect(wrapper.text()).toContain('Choose a meeting type and a convenient time')
    expect(wrapper.text()).toContain('Book quickly')
    expect(wrapper.text()).toContain('Manage meeting types')
    wrapper.unmount()
  })

  it('links the header and main call to action to booking and admin', async () => {
    await router.push('/')
    await router.isReady()
    const wrapper = mount(App, { global: { plugins: [router] } })

    expect(wrapper.get('header a[aria-label="Calendar home"]').text()).toBe('Calendar')
    expect(wrapper.get('header a[href="/book"]').text()).toBe('Book a meeting')
    expect(wrapper.get('header a[href="/admin"]').text()).toBe('Admin')
    expect(wrapper.get('main a[href="/book"]').text()).toBe('Book now →')
    wrapper.unmount()
  })
})
