import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'] })
  const page = await context.newPage()
  page.setDefaultTimeout(10000)
  const origin = process.env.APP_ORIGIN
  assert.ok(origin, 'APP_ORIGIN is required')
  await page.goto(`${origin}/admin/links`)
  await page.getByLabel('Username', { exact: true }).fill('owner-browser')
  await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  const created = await context.request.post(`${origin}/api/v1/admin/meeting-types`, {
    headers: { 'X-Calendar-Request': '1' },
    data: { name: 'Manage browser offer', slug: 'manage-browser-old', durationMinutes: 20 },
  })
  assert.equal(created.status(), 201)
  await page.reload()
  let row = page.getByRole('listitem').filter({ hasText: 'Manage browser offer' })
  await row.getByRole('link', { name: 'Edit', exact: true }).click()
  await page.getByRole('heading', { name: 'Edit meeting type' }).waitFor()
  assert.equal(await page.getByLabel('Name', { exact: true }).inputValue(), 'Manage browser offer')
  await page.getByLabel('Name', { exact: true }).fill('Managed browser offer')
  await page.getByLabel('Description', { exact: true }).fill('Edited details')
  await page.getByLabel('Duration (minutes)', { exact: true }).fill('45')
  await page.getByLabel('Public address', { exact: true }).fill('manage-browser-new')
  const save = page.getByRole('button', { name: 'Save', exact: true })
  await page.getByLabel('Public address', { exact: true }).fill('double--dash')
  await save.click()
  await page.getByText('Use 1–80 lowercase letters or digits', { exact: false }).waitFor()
  assert.equal(await page.getByLabel('Name', { exact: true }).inputValue(), 'Managed browser offer')
  await page.getByLabel('Public address', { exact: true }).fill('short-meeting')
  // An address reserved by a hidden type is just as unavailable as a published one.
  const occupied = await context.request.post(`${origin}/api/v1/admin/meeting-types`, {
    headers: { 'X-Calendar-Request': '1' },
    data: { name: 'Reserved address', slug: 'manage-occupied', durationMinutes: 15 },
  })
  assert.equal(occupied.status(), 201)
  await page.getByLabel('Public address', { exact: true }).fill('manage-occupied')
  await save.click()
  await page.getByText('has already been taken', { exact: true }).waitFor()
  assert.equal(await page.getByLabel('Description', { exact: true }).inputValue(), 'Edited details')
  await page.getByLabel('Public address', { exact: true }).fill('manage-browser-new')
  await context.setOffline(true)
  await save.click()
  await page.getByText('Unable to save the meeting type.', { exact: false }).waitFor()
  assert.equal(
    await page.getByLabel('Public address', { exact: true }).inputValue(),
    'manage-browser-new',
  )
  await context.setOffline(false)
  // Throttle real HTTP, never substitute a fabricated API response.
  const cdp = await context.newCDPSession(page)
  await cdp.send('Network.enable')
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false,
    latency: 400,
    downloadThroughput: -1,
    uploadThroughput: -1,
  })
  let saves = 0
  let publications = 0
  page.on('request', (request) => {
    if (request.method() !== 'PUT') return
    if (request.url().endsWith('/publication')) publications++
    else if (request.url().includes('/admin/meeting-types/')) saves++
  })
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  assert.equal(await page.getByRole('button', { name: 'Saving…' }).isDisabled(), true)
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  assert.equal(saves, 1)
  row = page.getByRole('listitem').filter({ hasText: 'Managed browser offer' })
  await row.getByText('Hidden', { exact: true }).waitFor()
  await row.getByRole('button', { name: 'Copy link', exact: true }).click()
  assert.equal(
    await page.evaluate(() => navigator.clipboard.readText()),
    `${origin}/book/manage-browser-new`,
  )
  await cdp.send('Network.emulateNetworkConditions', {
    offline: true,
    latency: 0,
    downloadThroughput: -1,
    uploadThroughput: -1,
  })
  await row.getByRole('button', { name: 'Publish', exact: true }).click()
  await row.getByRole('alert').filter({ hasText: 'Unable to change publication' }).waitFor()
  await row.getByText('Hidden', { exact: true }).waitFor()
  assert.equal(await row.getByRole('button', { name: 'Publish', exact: true }).isEnabled(), true)
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false,
    latency: 400,
    downloadThroughput: -1,
    uploadThroughput: -1,
  })
  const beforePublish = publications
  await row.getByRole('button', { name: 'Publish', exact: true }).click()
  assert.equal(await row.getByRole('button', { name: 'Updating…' }).isDisabled(), true)
  await row.getByText('Hidden', { exact: true }).waitFor()
  await row.getByText('Published', { exact: true }).waitFor()
  assert.equal(publications, beforePublish + 1)
  await cdp.detach()
  assert.equal(
    (
      await context.request.get(`${origin}/api/v1/meeting-types/manage-browser-old/availability`)
    ).status(),
    404,
  )
  assert.equal(
    (
      await context.request.get(`${origin}/api/v1/meeting-types/manage-browser-new/availability`)
    ).status(),
    200,
  )
  await row.getByRole('button', { name: 'Hide', exact: true }).click()
  await row.getByText('Hidden', { exact: true }).waitFor()
  await row.getByRole('button', { name: 'Publish', exact: true }).click()
  await row.getByText('Published', { exact: true }).waitFor()
  await page.reload()
  await row.getByText('Published', { exact: true }).waitFor()
  await row.getByRole('link', { name: 'Edit', exact: true }).click()
  await page.getByLabel('Name', { exact: true }).fill('Published browser offer')
  await save.click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  row = page.getByRole('listitem').filter({ hasText: 'Published browser offer' })
  await row.getByText('Published', { exact: true }).waitFor()
  const guest = await browser.newContext()
  const guestPage = await guest.newPage()
  await guestPage.goto(`${origin}/book`)
  await guestPage.getByRole('heading', { name: 'Published browser offer', exact: true }).waitFor()
  await guestPage.goto(`${origin}/book/manage-browser-old`)
  await guestPage.getByText('Meeting type unavailable', { exact: true }).waitFor()
  // Keep the existing smoke fixture stable for its restart/empty-state phases.
  await row.getByRole('button', { name: 'Hide', exact: true }).click()
  await row.getByText('Hidden', { exact: true }).waitFor()
  await guestPage.goto(`${origin}/book/manage-browser-new`)
  await guestPage.getByText('Meeting type unavailable', { exact: true }).waitFor()
  assert.ok(!(await guestPage.locator('main').textContent()).includes('Edited details'))
  await guestPage.goto(`${origin}/book/nonexistent-manage`)
  await guestPage.getByText('Meeting type unavailable', { exact: true }).waitFor()
  await guest.close()
  console.log(
    'Meeting type editing, separate publication/hiding/republishing and current copied link passed.',
  )
} finally {
  await browser.close()
}
