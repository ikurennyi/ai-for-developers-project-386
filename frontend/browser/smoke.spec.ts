import { mount } from '@vue/test-utils'
import { expect, inject, it } from 'vitest'
import App from '../src/App.vue'
import router from '../src/router'
import { getHealth } from '../src/generated/sdk'
import 'element-plus/dist/index.css'

declare module 'vitest' {
  export interface ProvidedContext {
    emptyMeetingTypes: boolean
  }
}

it('renders the service homepage in the root application', async () => {
  await router.push('/')
  await router.isReady()
  const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
  try {
    const { data } = await getHealth({ throwOnError: true })
    expect(data.status).toBe('ok')
    expect(wrapper.get('h1').text()).toBe('Book a call in minutes')
    expect(wrapper.get('header a[href="/book"]').text()).toBe('Book a meeting')
    expect(wrapper.get('header a[href="/admin"]').text()).toBe('Admin')
    expect(wrapper.get('main a[href="/book"]').text()).toBe('Book now →')
  } finally {
    wrapper.unmount()
  }
})

it.skipIf(inject('emptyMeetingTypes'))(
  'opens server-backed published offers through the booking action',
  async () => {
    await router.push('/')
    const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
    try {
      await wrapper.get('main a[href="/book"]').trigger('click')
      await expect.poll(() => wrapper.find('h1').text()).toBe('Book a meeting')
      await expect.poll(() => wrapper.text()).toContain('15-minute meeting')
      expect(wrapper.text()).toContain('30-minute meeting')
      expect(wrapper.text()).toContain('A short conversation to connect.')
      expect(wrapper.text()).toContain('More time for a focused discussion.')
      expect(wrapper.text()).toContain('15 minutes')
      expect(wrapper.text()).toContain('30 minutes')
      expect(wrapper.text()).toContain('Extended discussion')
      expect(wrapper.text()).toContain('45 minutes')
      expect(wrapper.text()).not.toContain('Private offer')
    } finally {
      wrapper.unmount()
    }
  },
)

it.runIf(inject('emptyMeetingTypes'))('explains when no offers are published', async () => {
  await router.push('/book')
  const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
  try {
    await expect.poll(() => wrapper.text()).toContain('No meeting types available')
    expect(wrapper.findAll('.meeting-type-list li')).toHaveLength(0)
  } finally {
    wrapper.unmount()
  }
})
