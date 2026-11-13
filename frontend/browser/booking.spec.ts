import { mount } from '@vue/test-utils'
import { expect, inject, it } from 'vitest'
import App from '../src/App.vue'
import router from '../src/router'
import { getAvailability } from '../src/generated/sdk'
import 'element-plus/dist/index.css'

it.skipIf(inject('emptyMeetingTypes') || inject('occupiedCalendar'))(
  'validates guest input and confirms a real meeting with plain-text details',
  async () => {
    const { data } = await getAvailability({
      path: { slug: '30-minute-meeting' },
      throwOnError: true,
    })
    const day = [...data.days]
      .reverse()
      .find((entry) => entry.date > data.today && entry.intervals.some((slot) => slot.available))!
    const slot = [...day.intervals].reverse().find((entry) => entry.available)!
    await router.push({
      name: 'meeting-form',
      params: { slug: '30-minute-meeting' },
      query: { date: day.date, start: slot.startsAt },
    })
    const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
    try {
      await expect.poll(() => wrapper.text()).toContain('Guest details')
      expect(wrapper.text()).toContain('Alex Morgan')
      expect(wrapper.text()).toContain('30 minutes')
      expect(wrapper.text()).toContain('Europe/Berlin')
      await wrapper.get('form').trigger('submit')
      expect(wrapper.get('#guest-name-error').text()).toBe('Enter your name (1–100 characters).')
      expect(wrapper.get('#guest-email-error').text()).toBe(
        'Enter a valid email address (up to 254 characters).',
      )
      await wrapper.get('input[name="guestName"]').setValue('  <b>Guest</b>  ')
      await wrapper.get('input[name="guestEmail"]').setValue('not-an-email')
      await wrapper.get('textarea[name="notes"]').setValue('x'.repeat(2001))
      await wrapper.get('form').trigger('submit')
      expect(wrapper.get('#notes-error').text()).toBe('Use at most 2000 characters.')
      expect(wrapper.get<HTMLInputElement>('input[name="guestName"]').element.value).toBe(
        '  <b>Guest</b>  ',
      )
      await wrapper.get('input[name="guestEmail"]').setValue('guest@example.com')
      await wrapper.get('textarea[name="notes"]').setValue('<img src=x onerror=alert(1)>')
      await wrapper.get('form').trigger('submit')
      expect(wrapper.get('button[type="submit"]').attributes('disabled')).toBeDefined()
      await expect.poll(() => wrapper.text()).toContain('This meeting is scheduled')
      expect(wrapper.text()).toContain('No confirmation email will be sent.')
      expect(wrapper.text()).toContain('<b>Guest</b>')
      expect(wrapper.text()).toContain('guest@example.com')
      expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>')
      expect(wrapper.find('.booking-success b, .booking-success img').exists()).toBe(false)
      expect(router.currentRoute.value.fullPath).not.toContain('guest')
      const { data: after } = await getAvailability({
        path: { slug: '15-minute-meeting' },
        throwOnError: true,
      })
      expect(
        after.days
          .find((entry) => entry.date === day.date)
          ?.intervals.find((entry) => entry.startsAt === slot.startsAt)?.available,
      ).toBe(false)
      await wrapper.get('a.book-another').trigger('click')
      await expect.poll(() => router.currentRoute.value.path).toBe('/book')
    } finally {
      wrapper.unmount()
    }
  },
)
