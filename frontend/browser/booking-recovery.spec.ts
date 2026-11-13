import { mount } from '@vue/test-utils'
import { expect, inject, it } from 'vitest'
import App from '../src/App.vue'
import router from '../src/router'
import {
  confirmBooking,
  createAdminMeetingType,
  getAdminSession,
  getAvailability,
  loginAdmin,
  setAdminMeetingTypePublication,
  updateAdminMeetingType,
} from '../src/generated/sdk'
import 'element-plus/dist/index.css'

async function authenticateOwner() {
  if ((await getAdminSession()).data) return
  await loginAdmin({
    headers: { 'X-Calendar-Request': '1' },
    body: { username: 'owner-browser', password: 'browser-only-password-24!' },
    throwOnError: true,
  })
}

it.skipIf(inject('emptyMeetingTypes') || inject('occupiedCalendar'))(
  'refreshes occupied time without substituting a time or losing the date and guest draft',
  async () => {
    const { data } = await getAvailability({
      path: { slug: '15-minute-meeting' },
      throwOnError: true,
    })
    const day = data.days.filter(
      (entry) => entry.date > data.today && entry.intervals.some((slot) => slot.available),
    )[3]!
    const slot = day.intervals.find((entry) => entry.available)!
    await router.push({
      name: 'meeting-form',
      params: { slug: data.meetingType.slug },
      query: { date: day.date, start: slot.startsAt },
    })
    const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
    try {
      await expect.poll(() => wrapper.text()).toContain('Guest details')
      await wrapper.get('input[name="guestName"]').setValue('Recovering guest')
      await wrapper.get('input[name="guestEmail"]').setValue('recovery@example.com')
      await wrapper.get('textarea[name="notes"]').setValue('Keep these notes')
      await confirmBooking({
        path: { slug: data.meetingType.slug },
        body: {
          startsAt: slot.startsAt,
          meetingType: data.meetingType,
          guestName: 'Other guest',
          guestEmail: 'other@example.com',
        },
        throwOnError: true,
      })
      await wrapper.get('form').trigger('submit')
      await expect.poll(() => router.currentRoute.value.name).toBe('meeting-calendar')
      await expect
        .poll(() => wrapper.text())
        .toContain('This time is no longer available. Please choose another time.')
      expect(router.currentRoute.value.query).toEqual({ date: day.date })
      expect(wrapper.text()).toContain('No time selected')
      expect(
        wrapper.get(`button[data-start="${slot.startsAt}"]`).attributes('disabled'),
      ).toBeDefined()
      expect(wrapper.get('button.continue').attributes('disabled')).toBeDefined()
      const next = wrapper
        .findAll('button[data-start]')
        .find((button) => !button.element.hasAttribute('disabled'))!
      await next.trigger('click')
      await expect.poll(() => wrapper.get('button.continue').attributes('disabled')).toBeUndefined()
      await wrapper.get('button.continue').trigger('click')
      await expect.poll(() => wrapper.find('input[name="guestName"]').exists()).toBe(true)
      expect(wrapper.get<HTMLInputElement>('input[name="guestName"]').element.value).toBe(
        'Recovering guest',
      )
      expect(wrapper.get<HTMLInputElement>('input[name="guestEmail"]').element.value).toBe(
        'recovery@example.com',
      )
      expect(wrapper.get<HTMLTextAreaElement>('textarea[name="notes"]').element.value).toBe(
        'Keep these notes',
      )
    } finally {
      wrapper.unmount()
    }
  },
)

it.skipIf(inject('emptyMeetingTypes') || inject('occupiedCalendar'))(
  'removes confirmation for a hidden meeting type and offers the meeting list without losing the draft',
  async () => {
    await authenticateOwner()
    const { data: offer } = await createAdminMeetingType({
      headers: { 'X-Calendar-Request': '1' },
      body: {
        name: 'Hide during form',
        durationMinutes: 15,
        slug: `hidden-${crypto.randomUUID()}`,
      },
      throwOnError: true,
    })
    await setAdminMeetingTypePublication({
      path: { id: offer.id },
      headers: { 'X-Calendar-Request': '1' },
      body: { published: true },
      throwOnError: true,
    })
    const { data } = await getAvailability({ path: { slug: offer.slug }, throwOnError: true })
    const day = data.days.filter(
      (entry) => entry.date > data.today && entry.intervals.some((slot) => slot.available),
    )[5]!
    const slot = day.intervals.find((entry) => entry.available)!
    await router.push({
      name: 'meeting-form',
      params: { slug: offer.slug },
      query: { date: day.date, start: slot.startsAt },
    })
    const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
    try {
      await expect.poll(() => wrapper.text()).toContain('Guest details')
      await wrapper.get('input[name="guestName"]').setValue('Hidden draft guest')
      await wrapper.get('input[name="guestEmail"]').setValue('hidden@example.com')
      await wrapper.get('textarea[name="notes"]').setValue('Keep hidden draft')
      await setAdminMeetingTypePublication({
        path: { id: offer.id },
        headers: { 'X-Calendar-Request': '1' },
        body: { published: false },
        throwOnError: true,
      })
      await wrapper.get('form').trigger('submit')
      await expect.poll(() => wrapper.get('h1').text()).toBe('Meeting type unavailable')
      expect(wrapper.find('button[type="submit"]').exists()).toBe(false)
      expect(
        wrapper
          .findAll('a')
          .some(
            (link) =>
              link.text() === 'Choose a meeting type' && link.attributes('href') === '/book',
          ),
      ).toBe(true)
      await setAdminMeetingTypePublication({
        path: { id: offer.id },
        headers: { 'X-Calendar-Request': '1' },
        body: { published: true },
        throwOnError: true,
      })
      await router.push({
        name: 'meeting-calendar',
        params: { slug: offer.slug },
        query: { date: day.date, start: slot.startsAt },
      })
      await expect.poll(() => wrapper.find('button.continue').exists()).toBe(true)
      await wrapper.get('button.continue').trigger('click')
      await expect.poll(() => wrapper.find('input[name="guestName"]').exists()).toBe(true)
      expect(wrapper.get<HTMLInputElement>('input[name="guestName"]').element.value).toBe(
        'Hidden draft guest',
      )
      expect(wrapper.get<HTMLInputElement>('input[name="guestEmail"]').element.value).toBe(
        'hidden@example.com',
      )
      expect(wrapper.get<HTMLTextAreaElement>('textarea[name="notes"]').element.value).toBe(
        'Keep hidden draft',
      )
    } finally {
      wrapper.unmount()
    }
  },
)

it.skipIf(inject('emptyMeetingTypes') || inject('occupiedCalendar'))(
  'shows every changed meeting term and waits for a fresh explicit confirmation with the draft intact',
  async () => {
    await authenticateOwner()
    for (const changes of [
      { name: 'Revised meeting name' },
      { description: 'Revised meeting description' },
      { durationMinutes: 30 },
    ]) {
      const original = {
        name: 'Recovery discussion',
        description: 'Original discussion terms',
        durationMinutes: 15,
        slug: `recovery-${crypto.randomUUID()}`,
      }
      const { data: offer } = await createAdminMeetingType({
        headers: { 'X-Calendar-Request': '1' },
        body: original,
        throwOnError: true,
      })
      await setAdminMeetingTypePublication({
        path: { id: offer.id },
        headers: { 'X-Calendar-Request': '1' },
        body: { published: true },
        throwOnError: true,
      })
      const { data } = await getAvailability({ path: { slug: offer.slug }, throwOnError: true })
      const day = data.days.filter(
        (entry) => entry.date > data.today && entry.intervals.some((slot) => slot.available),
      )[4]!
      const slot = day.intervals.find((entry) => entry.available)!
      await router.push({
        name: 'meeting-form',
        params: { slug: offer.slug },
        query: { date: day.date, start: slot.startsAt },
      })
      const wrapper = mount(App, { attachTo: document.body, global: { plugins: [router] } })
      try {
        await expect.poll(() => wrapper.text()).toContain('Guest details')
        await wrapper.get('input[name="guestName"]').setValue('Terms guest')
        await wrapper.get('input[name="guestEmail"]').setValue('terms@example.com')
        await wrapper.get('textarea[name="notes"]').setValue('Preserved terms draft')
        await updateAdminMeetingType({
          path: { id: offer.id },
          headers: { 'X-Calendar-Request': '1' },
          body: { ...original, ...changes },
          throwOnError: true,
        })
        await wrapper.get('form').trigger('submit')
        await expect
          .poll(() => wrapper.text())
          .toContain(
            'Meeting details changed. Please review the current details before confirming again.',
          )
        await expect.poll(() => wrapper.find('input[name="guestName"]').exists()).toBe(true)
        const current = { ...original, ...changes }
        expect(wrapper.get('h1').text()).toBe(current.name)
        expect(wrapper.get('.description').text()).toBe(current.description)
        expect(wrapper.text()).toContain(`${current.durationMinutes} minutes`)
        expect(wrapper.get<HTMLInputElement>('input[name="guestName"]').element.value).toBe(
          'Terms guest',
        )
        expect(wrapper.get<HTMLInputElement>('input[name="guestEmail"]').element.value).toBe(
          'terms@example.com',
        )
        expect(wrapper.get<HTMLTextAreaElement>('textarea[name="notes"]').element.value).toBe(
          'Preserved terms draft',
        )
        expect(router.currentRoute.value.query).toEqual({ date: day.date, start: slot.startsAt })
        const { data: beforeConsent } = await getAvailability({
          path: { slug: offer.slug },
          throwOnError: true,
        })
        expect(
          beforeConsent.days
            .find((entry) => entry.date === day.date)!
            .intervals.find((entry) => entry.startsAt === slot.startsAt)!.available,
        ).toBe(true)
        expect(wrapper.text()).not.toContain('This meeting is scheduled')
        await wrapper.get('form').trigger('submit')
        await expect.poll(() => wrapper.text()).toContain('This meeting is scheduled')
        expect(wrapper.text()).toContain(current.name)
        expect(wrapper.text()).toContain(current.description)
        expect(wrapper.text()).toContain(`${current.durationMinutes} minutes`)
      } finally {
        wrapper.unmount()
      }
    }
  },
)
