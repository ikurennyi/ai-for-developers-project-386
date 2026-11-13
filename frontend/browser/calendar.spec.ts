import { mount } from '@vue/test-utils'
import { expect, inject, it } from 'vitest'
import App from '../src/App.vue'
import router from '../src/router'
import { getAvailability } from '../src/generated/sdk'
import { page, userEvent } from '@vitest/browser/context'
import 'element-plus/dist/index.css'

declare module 'vitest' {
  export interface ProvidedContext {
    occupiedCalendar: boolean
  }
}

it.skipIf(inject('emptyMeetingTypes') || inject('occupiedCalendar'))(
  'opens a real calendar, selects a Berlin interval and continues without reserving it',
  async () => {
    await router.push('/book')
    const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
    try {
      await expect.poll(() => wrapper.find('a[href="/book/15-minute-meeting"]').exists()).toBe(true)
      await wrapper.get('a[href="/book/15-minute-meeting"]').trigger('click')
      await expect.poll(() => wrapper.text()).toContain('Select a date to see available times')
      expect(wrapper.text()).toContain('Alex Morgan')
      expect(wrapper.text()).toContain('Europe/Berlin')
      expect(wrapper.text()).toContain('No date selected')
      expect(wrapper.text()).toContain('No time selected')
      expect(wrapper.get('button.continue').attributes('disabled')).toBeDefined()
      expect(wrapper.findAll('[aria-current="date"]')).toHaveLength(1)
      const { data: before } = await getAvailability({
        path: { slug: '15-minute-meeting' },
        throwOnError: true,
      })
      const day = before.days.find(
        (entry) =>
          entry.date > before.today && entry.intervals.some((interval) => interval.available),
      )!
      const interval = day.intervals.find((entry) => entry.available)!
      expect(Intl.DateTimeFormat().resolvedOptions().timeZone).toBe('America/Los_Angeles')
      expect(
        wrapper.get('button[aria-label="Previous month"]').attributes('disabled'),
      ).toBeDefined()
      expect('disabled' in wrapper.get('button[aria-label="Next month"]').attributes()).toBe(
        before.today.slice(0, 7) === before.windowEnd.slice(0, 7),
      )
      if (day.date.slice(0, 7) !== before.today.slice(0, 7)) {
        await wrapper.get('button[aria-label="Next month"]').trigger('click')
      }
      await wrapper.get(`button[data-date="${day.date}"]`).trigger('click')
      await expect
        .poll(() => wrapper.find(`button[data-start="${interval.startsAt}"]`).exists())
        .toBe(true)
      await wrapper.get(`button[data-start="${interval.startsAt}"]`).trigger('click')
      await expect.poll(() => wrapper.get('button.continue').attributes('disabled')).toBeUndefined()
      expect(wrapper.get(`button[data-start="${interval.startsAt}"]`).text()).toContain('Available')
      const berlinStart = new Intl.DateTimeFormat('en-GB', {
        timeZone: 'Europe/Berlin',
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23',
      }).format(new Date(interval.startsAt))
      expect(wrapper.get(`button[data-start="${interval.startsAt}"]`).text()).toContain(berlinStart)
      await wrapper.get('button.continue').trigger('click')
      await expect.poll(() => wrapper.text()).toContain('Guest details')
      expect(router.currentRoute.value.query).toMatchObject({
        date: day.date,
        start: interval.startsAt,
      })
      expect(wrapper.text()).toContain('Your selection is not reserved')
      const { data: after } = await getAvailability({
        path: { slug: '15-minute-meeting' },
        throwOnError: true,
      })
      expect(after.days.find((entry) => entry.date === day.date)).toEqual(day)
      await wrapper.get('a.back-calendar').trigger('click')
      await expect.poll(() => wrapper.find('[aria-pressed="true"][data-start]').exists()).toBe(true)
      await wrapper.get('a.back-types').trigger('click')
      await expect.poll(() => wrapper.find('h1').text()).toBe('Book a meeting')
    } finally {
      wrapper.unmount()
    }
  },
)

it('does not disclose hidden offers or nonexistent direct links', async () => {
  const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
  try {
    for (const slug of ['private', 'nonexistent']) {
      await router.push(`/book/${slug}`)
      await expect.poll(() => wrapper.find('h1').text()).toBe('Meeting type unavailable')
      expect(wrapper.text()).not.toContain('Private offer')
      expect(wrapper.find('.continue').exists()).toBe(false)
    }
  } finally {
    wrapper.unmount()
  }
})

it.skipIf(inject('emptyMeetingTypes') || inject('occupiedCalendar'))(
  'revalidates direct selections and provides a keyboard-accessible phone calendar',
  async () => {
    await page.viewport(375, 812)
    await router.push('/book/15-minute-meeting/details?date=2000-01-01&start=2000-01-01T09:00:00Z')
    const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
    try {
      await expect
        .poll(() => wrapper.text())
        .toContain('This time is no longer available. Please choose another time.')
      await expect.poll(() => wrapper.find('.date-grid').exists()).toBe(true)
      expect(router.currentRoute.value.name).toBe('meeting-calendar')
      expect(wrapper.text()).toContain('No date selected')
      expect(wrapper.text()).toContain('No time selected')
      expect(wrapper.findAll('.outside').length).toBeGreaterThan(0)
      const calendar = wrapper.get('.month-calendar').element.getBoundingClientRect()
      const summary = wrapper.get('.meeting-summary').element.getBoundingClientRect()
      const times = wrapper.get('.time-selection').element.getBoundingClientRect()
      expect(calendar.top).toBeGreaterThanOrEqual(summary.bottom)
      expect(times.top).toBeGreaterThanOrEqual(calendar.bottom)
      expect(document.documentElement.scrollWidth).toBeLessThanOrEqual(window.innerWidth)
      const button = wrapper.get<HTMLButtonElement>('.date-grid button:not(:disabled)')
      button.element.focus()
      expect(document.activeElement).toBe(button.element)
      await userEvent.keyboard('{Enter}')
      await expect.poll(() => wrapper.find('.intervals').exists()).toBe(true)
      expect(
        wrapper
          .findAll('.intervals button')
          .every((entry) => /Available|Unavailable/.test(entry.text())),
      ).toBe(true)
      expect(
        wrapper
          .findAll('.intervals button:disabled')
          .every((entry) => entry.text().includes('Unavailable')),
      ).toBe(true)
    } finally {
      wrapper.unmount()
      await page.viewport(1280, 900)
    }
  },
)

it.runIf(inject('occupiedCalendar'))(
  'explains fully occupied dates and windows without offering unusable continuation',
  async () => {
    await router.push('/book/15-minute-meeting')
    const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
    try {
      await expect.poll(() => wrapper.text()).toContain('No available times in the next 14 days')
      await wrapper.get('.date-grid button:not(:disabled)').trigger('click')
      await expect.poll(() => wrapper.text()).toContain('No available times on this date')
      expect(wrapper.get('button.continue').attributes('disabled')).toBeDefined()
      expect(wrapper.findAll('.intervals button:not(:disabled)')).toHaveLength(0)
    } finally {
      wrapper.unmount()
    }
  },
)
