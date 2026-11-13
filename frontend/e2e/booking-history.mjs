import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext({ timezoneId: 'America/Los_Angeles' })
  const page = await context.newPage()
  page.setDefaultTimeout(10000)
  const origin = process.env.APP_ORIGIN
  assert.ok(origin, 'APP_ORIGIN is required')
  assert.equal((await context.request.get(`${origin}/api/v1/admin/bookings`)).status(), 401)
  await page.goto(`${origin}/admin/bookings`)
  await page.getByLabel('Username', { exact: true }).fill('owner-browser')
  await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('heading', { name: 'Bookings', exact: true }).waitFor()
  if (process.env.HISTORY_EMPTY === '1') {
    await page.getByRole('button', { name: 'Past', exact: true }).click()
    await page.getByText('No past bookings.', { exact: true }).waitFor()
  } else {
    const rows = page.locator('tbody tr')
    await page.getByText('Page 1 of 2 · 23 bookings', { exact: true }).waitFor()
    assert.equal(await rows.count(), 20)
    assert.match(await rows.first().innerText(), /Future 00/)
    assert.match(await rows.last().innerText(), /Future 19/)
    const first = rows.first()
    assert.match(await first.innerText(), /13:00–13:15/)
    await page.getByText('Europe/Berlin', { exact: true }).waitFor()
    await first.getByText('Show full notes', { exact: true }).click()
    assert.equal(
      await first.locator('.notes').innerText(),
      '<script>plain text</script>\n' + 'Long note. '.repeat(180) + 'END',
    )
    assert.equal(await first.locator('script').count(), 0)
    assert.match(await first.innerText(), /<b>History guest<\/b>/)
    assert.match(await first.innerText(), /history@example.com/)
    assert.match(await first.innerText(), /Saved description/)
    await page.getByRole('button', { name: 'Next page', exact: true }).click()
    await page.getByText('Page 2 of 2 · 23 bookings', { exact: true }).waitFor()
    assert.equal(await rows.count(), 3)
    assert.match(await rows.first().innerText(), /Future 20/)
    await page.getByRole('button', { name: 'Past', exact: true }).click()
    await page.getByText('Page 1 of 2 · 23 bookings', { exact: true }).waitFor()
    assert.match(await rows.first().innerText(), /Past 00/)
    assert.match(await rows.last().innerText(), /Past 19/)
    await page.getByRole('button', { name: 'Next page', exact: true }).click()
    await page.getByText('Page 2 of 2 · 23 bookings', { exact: true }).waitFor()
    assert.match(await rows.first().innerText(), /Past 20/)
    await page.reload()
    // Fresh entry always opens Upcoming.
    await page.getByText('Page 1 of 2 · 23 bookings', { exact: true }).waitFor()
    assert.match(await rows.first().innerText(), /Future 00/)
    await context.setOffline(true)
    await page.getByRole('button', { name: 'Past', exact: true }).click()
    await page.getByText('Unable to load bookings. Please try again.', { exact: true }).waitFor()
    assert.equal(await rows.count(), 0)
    await context.setOffline(false)
    const cdp = await context.newCDPSession(page)
    await cdp.send('Network.enable')
    await cdp.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: 500,
      downloadThroughput: -1,
      uploadThroughput: -1,
    })
    await page.getByRole('button', { name: 'Retry', exact: true }).click()
    await page.getByText('Loading bookings…', { exact: true }).waitFor()
    await page.getByText('Page 1 of 2 · 23 bookings', { exact: true }).waitFor()
    assert.match(await rows.first().innerText(), /Past 00/)
    await cdp.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: 0,
      downloadThroughput: -1,
      uploadThroughput: -1,
    })
    await rows.first().getByRole('button', { name: 'Delete booking', exact: true }).click()
    const confirmation = page.getByRole('dialog', { name: 'Delete booking?' })
    await confirmation.waitFor()
    assert.match(await confirmation.innerText(), /Past 00/)
    assert.match(await confirmation.innerText(), /<b>History guest<\/b>/)
    assert.match(await confirmation.innerText(), /Europe\/Berlin/)
    await confirmation.getByRole('button', { name: 'Cancel', exact: true }).click()
    assert.equal(await rows.count(), 20)
    await rows.first().getByRole('button', { name: 'Delete booking', exact: true }).click()
    await context.setOffline(true)
    await confirmation.getByRole('button', { name: 'Delete booking', exact: true }).click()
    await confirmation.getByRole('alert').waitFor()
    assert.match(await rows.first().innerText(), /Past 00/)
    await context.setOffline(false)
    await confirmation.getByRole('button', { name: 'Delete booking', exact: true }).click()
    await page.getByText('Page 1 of 2 · 22 bookings', { exact: true }).waitFor()
    assert.match(await rows.first().innerText(), /Past 01/)
    await page.getByRole('button', { name: 'Next page', exact: true }).click()
    for (const total of [21, 20]) {
      await rows.first().getByRole('button', { name: 'Delete booking', exact: true }).click()
      await confirmation.getByRole('button', { name: 'Delete booking', exact: true }).click()
      await page
        .getByText(`Page ${total === 20 ? 1 : 2} of ${total === 20 ? 1 : 2} · ${total} bookings`, {
          exact: true,
        })
        .waitFor()
    }
    await page.setViewportSize({ width: 375, height: 812 })
    assert.equal(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
      true,
    )
    await page.getByRole('button', { name: 'Upcoming', exact: true }).click()
    await page.getByText('Page 1 of 2 · 23 bookings', { exact: true }).waitFor()
    await rows.first().getByRole('button', { name: 'Delete booking', exact: true }).click()
    await confirmation.getByRole('button', { name: 'Delete booking', exact: true }).click()
    await page.getByText('Page 1 of 2 · 22 bookings', { exact: true }).waitFor()
    const upcomingResponse = await context.request.get(`${origin}/api/v1/admin/bookings`)
    const upcoming = (await upcomingResponse.json()).bookings
    const secondPage = await context.request.get(`${origin}/api/v1/admin/bookings?page=2`)
    upcoming.push(...(await secondPage.json()).bookings)
    for (const booking of upcoming.slice(1)) {
      const result = await context.request.delete(`${origin}/api/v1/admin/bookings/${booking.id}`, {
        headers: { 'X-Calendar-Request': '1' },
      })
      assert.equal(result.status(), 204)
    }
    await page.reload()
    await page.getByText('Page 1 of 1 · 1 bookings', { exact: true }).waitFor()
    await rows.first().getByRole('button', { name: 'Delete booking', exact: true }).click()
    await confirmation.getByRole('button', { name: 'Delete booking', exact: true }).click()
    await page.getByText('No upcoming bookings.', { exact: true }).waitFor()
    await page.reload()
    await page.getByText('No upcoming bookings.', { exact: true }).waitFor()
  }
  await page.getByRole('button', { name: 'Log out', exact: true }).click()
  await page.getByRole('heading', { name: 'Administrator login', exact: true }).waitFor()
  assert.equal(
    (await context.request.get(`${origin}/api/v1/admin/bookings?period=past`)).status(),
    401,
  )
  await context.close()
} finally {
  await browser.close()
}
