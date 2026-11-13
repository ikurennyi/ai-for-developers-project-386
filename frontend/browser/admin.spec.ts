import { mount, flushPromises } from '@vue/test-utils'
import { expect, inject, it } from 'vitest'
import App from '../src/App.vue'
import router from '../src/router'
import 'element-plus/dist/index.css'

it('returns to a protected page, survives a fresh mount, and logs out', async () => {
  await router.push('/admin/links')
  await router.isReady()
  let wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
  try {
    expect(router.currentRoute.value.path).toBe('/admin/login')
    await wrapper.get('input[name="username"]').setValue('owner-browser')
    await wrapper.get('input[name="password"]').setValue('browser-only-password-24!')
    await wrapper.get('form').trigger('submit')
    await expect.poll(() => router.currentRoute.value.path).toBe('/admin/links')
    expect(wrapper.get('h1').text()).toBe('Links')
    wrapper.unmount()
    // A new app mount and navigation must consult the real server cookie, not
    // rely on an in-memory "logged in" flag.
    await router.push('/admin')
    wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
    await flushPromises()
    expect(wrapper.get('h1').text()).toBe('Home')
    const expectedHomeText =
      inject('occupiedCalendar') || inject('emptyMeetingTypes')
        ? 'No unfinished bookings.'
        : 'Unfinished bookings'
    await expect.poll(() => wrapper.text()).toContain(expectedHomeText)
    expect(wrapper.text()).toContain('Europe/Berlin')
    await wrapper.get('button[data-test="logout"]').trigger('click')
    await expect.poll(() => router.currentRoute.value.path).toBe('/admin/login')
    await router.push('/admin/bookings')
    expect(router.currentRoute.value.path).toBe('/admin/login')
    expect(document.cookie).not.toContain('calendar_admin')
  } finally {
    wrapper.unmount()
  }
})
