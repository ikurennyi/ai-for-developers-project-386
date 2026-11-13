import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const origin = process.env.APP_ORIGIN
assert.ok(origin, 'APP_ORIGIN is required')
const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext({
    timezoneId: 'Pacific/Honolulu',
    viewport: { width: 1440, height: 1000 },
  })
  const page = await context.newPage()
  await page.goto(`${origin}/book`)
  await page.locator('a[href="/book/15-minute-meeting"]').click()
  await page.getByText('Select a date to see available times', { exact: true }).waitFor()
  assert.equal(await page.getByRole('button', { name: 'Continue', exact: true }).isEnabled(), false)
  assert.equal(await page.getByText('No date selected', { exact: true }).count(), 1)
  const positions = await page
    .locator('.calendar-layout')
    .evaluate((layout) =>
      [...layout.children].map((section) => section.getBoundingClientRect().left),
    )
  assert.ok(positions[0] < positions[1] && positions[1] < positions[2], 'desktop has three columns')
  const response = await page.request.get(
    `${origin}/api/v1/meeting-types/15-minute-meeting/availability`,
  )
  assert.equal(response.status(), 200)
  const calendar = await response.json()
  const day = calendar.days.find((entry) => entry.date > calendar.today && entry.workingDay)
  const interval = day.intervals.find((entry) => entry.available)
  assert.ok(interval)
  if (day.date.slice(0, 7) !== calendar.today.slice(0, 7)) {
    await page.getByRole('button', { name: 'Next month', exact: true }).click()
  }
  await page.locator(`[data-date="${day.date}"]`).click()
  await page.locator(`[data-start="${interval.startsAt}"]`).click()
  await page.getByRole('button', { name: 'Continue', exact: true }).click()
  await page.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  await page.reload()
  await page.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  assert.equal(new URL(page.url()).searchParams.get('start'), interval.startsAt)
  await page.getByRole('link', { name: '← Back to calendar', exact: true }).click()
  await page.locator(`[data-start="${interval.startsAt}"][aria-pressed="true"]`).waitFor()
  await page.reload()
  await page.locator(`[data-start="${interval.startsAt}"][aria-pressed="true"]`).waitFor()
  await page.setViewportSize({ width: 320, height: 740 })
  assert.ok(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    'phone calendar must not scroll horizontally',
  )
  await page.goto(
    `${origin}/book/15-minute-meeting/details?date=2000-01-01&start=2000-01-01T09:00:00Z`,
  )
  await page.getByRole('alert').filter({ hasText: 'This time is no longer available' }).waitFor()
  assert.equal(new URL(page.url()).pathname, '/book/15-minute-meeting')
  assert.equal(new URL(page.url()).searchParams.has('start'), false)
  for (const slug of ['private', 'does-not-exist']) {
    await page.goto(`${origin}/book/${slug}`)
    await page.getByRole('heading', { name: 'Meeting type unavailable', exact: true }).waitFor()
  }
  console.log(
    'Calendar full-page navigation: desktop, selection, Continue, refresh, Back, phone and stale/unavailable direct links passed.',
  )
} finally {
  await browser.close()
}
