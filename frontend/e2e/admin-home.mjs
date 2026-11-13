import assert from 'node:assert/strict'
// Reuse the existing authenticated browser scenario, keeping the smoke suite
// within the real login rate limit rather than weakening production protection.
export async function checkAdminHome(page, context, origin) {
  page.setDefaultTimeout(10000)
  assert.ok(origin, 'APP_ORIGIN is required')
  await page.goto(`${origin}/admin`)
  await page.getByRole('heading', { name: 'Ongoing saved meeting', exact: true }).waitFor()
  for (const name of ['Later saved meeting', 'Distant saved meeting']) {
    await page.getByRole('heading', { name, exact: true }).waitFor()
  }
  assert.equal(await page.getByText('Completed Home fixture', { exact: true }).count(), 0)
  assert.equal(await page.getByText('Changed Home fixture', { exact: true }).count(), 0)
  const response = await context.request.get(`${origin}/api/v1/admin/home`)
  assert.equal(response.status(), 200)
  const { days } = await response.json()
  for (const day of days) {
    const group = page.locator('.booking-day').filter({
      has: page.getByRole('heading', { name: day.date, exact: true }),
    })
    assert.equal(await group.count(), 1)
    assert.deepEqual(
      await group.locator('h3').allTextContents(),
      day.bookings.map((booking) => booking.meetingName),
    )
  }
  const ongoing = page.locator('article').filter({ hasText: 'Ongoing saved meeting' })
  assert.equal(await ongoing.locator('b, img, script').count(), 0)
  assert.equal(
    await ongoing.locator('.notes').textContent(),
    '<img src=x onerror=alert(1)>\n' + 'full notes '.repeat(190),
  )
  assert.ok((await ongoing.textContent()).includes('home-browser@example.com'))
  const distant = page.locator('article').filter({ hasText: 'Distant saved meeting' })
  assert.equal(await distant.locator('time').first().textContent(), '09:00')
  assert.equal(await distant.locator('time').last().textContent(), '09:30')
  // Delay/abort transport only: successful data always comes from the real API.
  let release
  const gate = new Promise((resolve) => {
    release = resolve
  })
  await page.route('**/api/v1/admin/home', async (route) => {
    await gate
    await route.continue()
  })
  await page.reload({ waitUntil: 'domcontentloaded' })
  await page.getByRole('status').filter({ hasText: 'Loading bookings…' }).waitFor()
  assert.equal(await page.locator('article').count(), 0)
  release()
  await page.getByRole('heading', { name: 'Ongoing saved meeting', exact: true }).waitFor()
  await page.unroute('**/api/v1/admin/home')
  await page.route('**/api/v1/admin/home', (route) => route.abort())
  await page.reload({ waitUntil: 'domcontentloaded' })
  await page.getByRole('alert').filter({ hasText: 'Unable to load bookings' }).waitFor()
  assert.equal(await page.getByText('No unfinished bookings.', { exact: true }).count(), 0)
  assert.equal(await page.locator('article').count(), 0)
  await page.unroute('**/api/v1/admin/home')
  await page.getByRole('button', { name: 'Retry', exact: true }).click()
  await page.getByRole('heading', { name: 'Ongoing saved meeting', exact: true }).waitFor()
  await page.setViewportSize({ width: 360, height: 800 })
  assert.equal(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    true,
  )
  await page.getByRole('button', { name: 'Log out', exact: true }).click()
  await page.getByRole('heading', { name: 'Administrator login', exact: true }).waitFor()
  assert.equal(await page.getByText('home-browser@example.com', { exact: true }).count(), 0)
  const unauthorized = await context.request.get(`${origin}/api/v1/admin/home`)
  assert.equal(unauthorized.status(), 401)
  assert.ok(!(await unauthorized.text()).includes('home-browser@example.com'))
  console.log(
    'Protected Home: grouping, snapshots, ongoing, distant dates, Berlin times, plain text, loading/error/retry and mobile passed',
  )
}
