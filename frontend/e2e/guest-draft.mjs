import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const origin = process.env.APP_ORIGIN
assert.ok(origin, 'APP_ORIGIN is required')
const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext({ timezoneId: 'Pacific/Honolulu' })
  const page = await context.newPage()
  const response = await page.request.get(
    `${origin}/api/v1/meeting-types/15-minute-meeting/availability`,
  )
  const calendar = await response.json()
  const day = calendar.days.find(
    (entry) => entry.date > calendar.today && entry.intervals.some((slot) => slot.available),
  )
  const interval = day.intervals.find((slot) => slot.available)
  const selection = new URLSearchParams({ date: day.date, start: interval.startsAt })
  const formUrl = `${origin}/book/15-minute-meeting/details?${selection}`
  await page.goto(formUrl)
  await page.getByLabel('Your name', { exact: true }).fill('Draft Guest')
  await page.getByLabel('Email address', { exact: true }).fill('draft@example.com')
  await page.getByLabel('Additional notes (optional)', { exact: true }).fill('Private draft notes')
  assert.deepEqual([...new URL(page.url()).searchParams.keys()].sort(), ['date', 'start'])
  await page.getByRole('link', { name: '← Back to calendar', exact: true }).click()
  await page.locator(`[data-start="${interval.startsAt}"][aria-pressed="true"]`).waitFor()
  await page.getByRole('button', { name: 'Continue', exact: true }).click()
  assert.equal(await page.getByLabel('Your name', { exact: true }).inputValue(), 'Draft Guest')
  await page.reload()
  await page.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  assert.equal(
    await page.getByLabel('Email address', { exact: true }).inputValue(),
    'draft@example.com',
  )
  await page.goBack()
  await page.locator(`[data-start="${interval.startsAt}"][aria-pressed="true"]`).waitFor()
  await page.goForward()
  await page.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  assert.equal(
    await page.getByLabel('Additional notes (optional)', { exact: true }).inputValue(),
    'Private draft notes',
  )

  // window.open intentionally retains its opener and clones sessionStorage.
  const draftPopupPromise = context.waitForEvent('page')
  await page.evaluate((url) => window.open(url, '_blank'), formUrl)
  const draftPopup = await draftPopupPromise
  await draftPopup.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  assert.equal(await draftPopup.getByLabel('Your name', { exact: true }).inputValue(), '')

  let confirmations = 0
  page.on('request', (request) => {
    if (request.method() === 'POST' && request.url().endsWith('/bookings')) confirmations++
  })
  await page.getByRole('button', { name: 'Confirm booking', exact: true }).click()
  await page.getByRole('heading', { name: 'This meeting is scheduled', exact: true }).waitFor()
  const confirmationUrl = page.url()
  assert.ok(!/Draft|draft|Private/.test(confirmationUrl), 'URLs contain no guest input')
  await page.reload()
  await page.getByRole('heading', { name: 'This meeting is scheduled', exact: true }).waitFor()
  assert.ok((await page.locator('main').innerText()).includes('draft@example.com'))
  assert.equal(confirmations, 1, 'refresh never confirms again')
  await draftPopup.reload()
  await draftPopup
    .getByRole('alert')
    .filter({ hasText: 'This time is no longer available' })
    .waitFor()
  assert.equal(new URL(draftPopup.url()).searchParams.has('start'), false)
  await draftPopup.close()

  const popupPromise = context.waitForEvent('page')
  await page.evaluate(() => sessionStorage.setItem('clone-canary', 'opener-storage'))
  await page.evaluate((url) => window.open(url, '_blank'), confirmationUrl)
  const popup = await popupPromise
  assert.equal(await popup.evaluate(() => !!window.opener), true)
  assert.equal(await popup.evaluate(() => sessionStorage.getItem('clone-canary')), 'opener-storage')
  assert.ok(
    !(await popup.evaluate(() => JSON.stringify({ ...sessionStorage, ...localStorage }))).includes(
      'draft@example.com',
    ),
    'cloned browser storage contains no guest details',
  )
  await popup.getByRole('link', { name: 'Choose a meeting type', exact: true }).waitFor()
  assert.ok(!(await popup.locator('body').innerText()).includes('draft@example.com'))
  await popup.reload()
  await popup.getByRole('link', { name: 'Choose a meeting type', exact: true }).waitFor()
  const otherContext = await browser.newContext()
  const other = await otherContext.newPage()
  await other.goto(confirmationUrl)
  await other.getByRole('link', { name: 'Choose a meeting type', exact: true }).waitFor()
  assert.ok(!(await other.locator('body').innerText()).includes('Draft Guest'))

  // A previously valid direct form link is revalidated, not a confirmation lookup.
  await other.goto(formUrl)
  await other.getByRole('alert').filter({ hasText: 'This time is no longer available' }).waitFor()
  assert.equal(new URL(other.url()).searchParams.get('date'), day.date)
  assert.equal(new URL(other.url()).searchParams.has('start'), false)
  await other.goto(`${origin}/book/15-minute-meeting?${selection}`)
  await other.getByRole('alert').filter({ hasText: 'This time is no longer available' }).waitFor()
  assert.equal(new URL(other.url()).searchParams.has('start'), false)
  await page.getByRole('link', { name: 'Book another meeting', exact: true }).click()
  const next = day.intervals.find((slot) => slot.available && slot.startsAt !== interval.startsAt)
  await page.locator('a[href="/book/15-minute-meeting"]').click()
  if (day.date.slice(0, 7) !== calendar.today.slice(0, 7)) {
    await page.getByRole('button', { name: 'Next month', exact: true }).click()
  }
  await page.locator(`[data-date="${day.date}"]`).click()
  await page.locator(`[data-start="${next.startsAt}"]`).click()
  await page.getByRole('button', { name: 'Continue', exact: true }).click()
  await page.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  assert.equal(await page.getByLabel('Your name', { exact: true }).inputValue(), '')
  console.log(
    'Guest draft: Back, history, refresh, cleared draft, stale links and opener/context confirmation privacy passed.',
  )
} finally {
  await browser.close()
}
