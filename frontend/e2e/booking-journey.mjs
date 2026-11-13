import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const origin = process.env.APP_ORIGIN
assert.ok(origin, 'APP_ORIGIN is required')
const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext({ timezoneId: 'Europe/Berlin' })
  const page = await context.newPage()
  page.setDefaultTimeout(10000)

  await page.goto(origin)
  await page.getByRole('link', { name: /Book now/ }).click()
  await page.getByRole('heading', { name: 'Book a meeting', exact: true }).waitFor()
  await page.getByRole('heading', { name: '15-minute meeting', exact: true }).waitFor()
  await page.getByRole('heading', { name: '30-minute meeting', exact: true }).waitFor()
  await page.getByRole('link', { name: 'Choose a time →' }).first().click()
  await page.getByText('Select a date to see available times', { exact: true }).waitFor()

  const response = await page.request.get(
    `${origin}/api/v1/meeting-types/15-minute-meeting/availability`,
  )
  assert.equal(response.status(), 200)
  const calendar = await response.json()
  const tomorrow = new Date(`${calendar.today}T12:00:00Z`)
  tomorrow.setUTCDate(tomorrow.getUTCDate() + 1)
  if ([0, 6].includes(tomorrow.getUTCDay())) {
    do tomorrow.setUTCDate(tomorrow.getUTCDate() + 1)
    while ([0, 6].includes(tomorrow.getUTCDay()))
  }
  const targetDate = [
    tomorrow.getUTCFullYear(),
    String(tomorrow.getUTCMonth() + 1).padStart(2, '0'),
    String(tomorrow.getUTCDate()).padStart(2, '0'),
  ].join('-')
  const targetDay = calendar.days.find((day) => day.date === targetDate && day.workingDay)
  const day = targetDay?.intervals.some((slot) => slot.available)
    ? targetDay
    : calendar.days.find(
        (entry) =>
          entry.date > calendar.today &&
          entry.workingDay &&
          entry.intervals.some((slot) => slot.available),
      )
  assert.ok(day, 'A future working day with an available time is required')
  const interval = day.intervals.find((slot) => slot.available)
  const month = page.locator(`[data-date="${day.date}"]`)
  if (!(await month.count())) {
    await page.getByRole('button', { name: 'Next month', exact: true }).click()
  }
  await page.locator(`[data-date="${day.date}"]`).click()
  await page.locator(`[data-start="${interval.startsAt}"]`).click()
  await page.locator(`[data-start="${interval.startsAt}"][aria-pressed="true"]`).waitFor()
  await page.getByRole('button', { name: 'Continue', exact: true }).click()
  await page.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  assert.match(await page.locator('.meeting-summary').innerText(), /15-minute meeting/)
  assert.match(await page.locator('.meeting-summary').innerText(), /Europe\/Berlin/)
  await page.getByLabel('Your name', { exact: true }).fill('Journey Guest')
  await page.getByLabel('Email address', { exact: true }).fill('journey@example.test')
  await page
    .getByLabel('Additional notes (optional)', { exact: true })
    .fill('Created in browser journey')
  await page.getByRole('button', { name: 'Confirm booking', exact: true }).click()
  await page.getByRole('heading', { name: 'This meeting is scheduled', exact: true }).waitFor()
  assert.ok(!page.url().includes('journey@example.test'))

  await page.goto(`${origin}/admin/bookings`)
  await page.getByLabel('Username', { exact: true }).fill('owner-browser')
  await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('heading', { name: 'Bookings', exact: true }).waitFor()
  const booking = page.locator('tbody tr').filter({ hasText: 'journey@example.test' })
  await booking.waitFor()
  assert.match(await booking.innerText(), /Journey Guest/)
  assert.match(await booking.innerText(), /Created in browser journey/)
  assert.match(await booking.innerText(), /15-minute meeting/)
  console.log('Guest booking is confirmed and visible to the administrator.')
  await context.close()
} finally {
  await browser.close()
}
