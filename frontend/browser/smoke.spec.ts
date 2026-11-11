import { mount } from '@vue/test-utils'
import { expect, it } from 'vitest'
import App from '../src/App.vue'
import router from '../src/router'
import 'element-plus/dist/index.css'

it('renders the real API status in the root application', async () => {
  await router.push('/')
  await router.isReady()
  const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
  try {
    await expect.poll(() => wrapper.get('[role="alert"]').text()).toBe('API healthy: ok')
    expect(wrapper.get('h1').text()).toBe('Calendar — technical scaffold')
  } finally {
    wrapper.unmount()
  }
})
