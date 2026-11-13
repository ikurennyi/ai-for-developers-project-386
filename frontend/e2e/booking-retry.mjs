import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const origin = process.env.APP_ORIGIN
assert.ok(origin, 'APP_ORIGIN is required')
const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext()
  const page = await context.newPage()
  const response = await page.request.get(
    `${origin}/api/v1/meeting-types/15-minute-meeting/availability`,
  )
  const calendar = await response.json()
  const day = calendar.days.find(
    (entry) => entry.date > calendar.today && entry.intervals.some((slot) => slot.available),
  )
  const interval = day.intervals.find((slot) => slot.available)
  const formUrl = `${origin}/book/15-minute-meeting/details?${new URLSearchParams({
    date: day.date,
    start: interval.startsAt,
  })}`
  await page.goto(formUrl)
  await page.getByLabel('Your name', { exact: true }).fill('Retry Guest')
  await page.getByLabel('Email address', { exact: true }).fill('retry-private@example.com')
  await page.getByLabel('Additional notes (optional)', { exact: true }).fill('Private retry notes')
  let committed
  let firstToken
  // Forward to the real Rails server, wait for its committed creation response,
  // then cut only the response to the browser. This is not a mocked booking.
  await page.route('**/api/v1/meeting-types/*/bookings', async (route) => {
    firstToken = route.request().postDataJSON().attemptToken
    const result = await route.fetch()
    assert.equal(result.status(), 201)
    committed = await result.json()
    await route.abort('connectionreset')
  })
  await page.getByRole('button', { name: 'Confirm booking', exact: true }).click()
  await page.getByRole('alert').filter({ hasText: 'We couldn’t confirm the result.' }).waitFor()
  assert.equal(await page.getByLabel('Your name', { exact: true }).inputValue(), 'Retry Guest')
  assert.match(firstToken, /^[0-9a-f]{64}$/)
  assert.ok(
    !(await page.evaluate(() => JSON.stringify({ ...sessionStorage, ...localStorage }))).includes(
      firstToken,
    ),
    'retry capability never enters cloneable storage',
  )
  const popupPromise = context.waitForEvent('page')
  await page.evaluate((url) => window.open(url, '_blank'), formUrl)
  const popup = await popupPromise
  await popup.getByRole('alert').filter({ hasText: 'This time is no longer available' }).waitFor()
  assert.ok(!(await popup.locator('body').innerText()).includes('retry-private@example.com'))
  await popup.close()
  await page.unroute('**/api/v1/meeting-types/*/bookings')
  await page.reload()
  await page.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  assert.equal(
    await page.getByLabel('Additional notes (optional)', { exact: true }).inputValue(),
    'Private retry notes',
  )
  const recoveredPromise = page.waitForResponse(
    (result) => result.request().method() === 'POST' && result.url().endsWith('/bookings'),
  )
  await page.getByRole('button', { name: 'Confirm booking', exact: true }).click()
  const recovered = await recoveredPromise
  assert.equal(recovered.request().postDataJSON().attemptToken, firstToken)
  assert.deepEqual(await recovered.json(), committed)
  await page.getByRole('heading', { name: 'This meeting is scheduled', exact: true }).waitFor()
  await page.reload()
  await page.getByRole('heading', { name: 'This meeting is scheduled', exact: true }).waitFor()
  assert.ok((await page.locator('main').innerText()).includes('retry-private@example.com'))
  await page.getByRole('link', { name: 'Book another meeting', exact: true }).click()
  const next = day.intervals.find((slot) => slot.available && slot.startsAt !== interval.startsAt)
  await page.goto(
    `${origin}/book/15-minute-meeting/details?${new URLSearchParams({
      date: day.date,
      start: next.startsAt,
    })}`,
  )
  await page.getByLabel('Your name', { exact: true }).fill('Next Guest')
  await page.getByLabel('Email address', { exact: true }).fill('next@example.com')
  let nextCommitted
  let nextToken
  await page.route('**/api/v1/meeting-types/*/bookings', async (route) => {
    nextToken = route.request().postDataJSON().attemptToken
    const result = await route.fetch()
    assert.equal(result.status(), 201)
    nextCommitted = await result.json()
    // Headers can arrive before a response is interrupted. The generated SDK
    // then returns a parsing error together with the successful HTTP status.
    await route.fulfill({ status: 201, contentType: 'application/json', body: '{"id":' })
  })
  await page.getByRole('button', { name: 'Confirm booking', exact: true }).click()
  await page.getByRole('alert').filter({ hasText: 'We couldn’t confirm the result.' }).waitFor()
  assert.notEqual(nextToken, firstToken)
  await page.unroute('**/api/v1/meeting-types/*/bookings')
  const nextPromise = page.waitForResponse(
    (result) => result.request().method() === 'POST' && result.url().endsWith('/bookings'),
  )
  await page.getByRole('button', { name: 'Confirm booking', exact: true }).click()
  const nextResponse = await nextPromise
  assert.equal(nextResponse.request().postDataJSON().attemptToken, nextToken)
  assert.deepEqual(await nextResponse.json(), nextCommitted)
  assert.notEqual(nextCommitted.id, committed.id)
  console.log(
    'Booking retry: real committed lost response, refresh, private recovery and new attempt passed.',
  )
} finally {
  await browser.close()
}
