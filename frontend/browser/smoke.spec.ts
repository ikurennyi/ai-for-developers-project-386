import { mount } from '@vue/test-utils'
import { expect, it } from 'vitest'
import App from '../src/App.vue'
import router from '../src/router'
import { getHealth } from '../src/generated/sdk'
import 'element-plus/dist/index.css'

it('renders the service homepage in the root application', async () => {
  await router.push('/')
  await router.isReady()
  const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
  try {
    const { data } = await getHealth({ throwOnError: true })
    expect(data.status).toBe('ok')
    expect(wrapper.get('h1').text()).toBe('Book a call in minutes')
    expect(wrapper.get('header a[href="/book"]').text()).toBe('Book')
    expect(wrapper.get('header a[href="/admin"]').text()).toBe('Admin')
    expect(wrapper.get('main a[href="/book"]').text()).toBe('Book now →')
  } finally {
    wrapper.unmount()
  }
})
