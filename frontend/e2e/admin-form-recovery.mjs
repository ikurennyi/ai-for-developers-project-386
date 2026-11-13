import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext()
  const page = await context.newPage()
  page.setDefaultTimeout(10000)
  const origin = process.env.APP_ORIGIN
  assert.ok(origin)
  async function login() {
    await page.getByRole('heading', { name: 'Administrator login' }).waitFor()
    await page.getByLabel('Username', { exact: true }).fill('owner-browser')
    await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
    await page.getByRole('button', { name: 'Log in', exact: true }).click()
  }
  await page.goto(`${origin}/admin/links/new`)
  await login()
  const name = page.getByLabel('Name', { exact: true })
  await name.fill('Private unfinished offer')
  await page.getByLabel('Description', { exact: true }).fill('Private recovery notes')
  await page.getByLabel('Duration (minutes)', { exact: true }).fill('23')
  await page.getByLabel('Public address', { exact: true }).fill('private-recovery-offer')
  // Revoke the real server session without replacing any API.
  const revoked = await context.request.delete(`${origin}/api/v1/admin/session`, {
    headers: { 'X-Calendar-Request': '1' },
  })
  assert.equal(revoked.status(), 204)
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await page.getByRole('heading', { name: 'Administrator login' }).waitFor()
  // window.open clones sessionStorage. A draft must still not cross to its child.
  const popupPromise = page.waitForEvent('popup')
  await page.evaluate(() => window.open('/admin/links/new', '_blank'))
  const popup = await popupPromise
  await popup.getByRole('heading', { name: 'Administrator login' }).waitFor()
  let mutations = 0
  page.on('request', (request) => {
    if (
      ['POST', 'PUT', 'DELETE'].includes(request.method()) &&
      !request.url().endsWith('/admin/session')
    )
      mutations++
  })
  // Login refresh must preserve the recovery data in the original tab.
  await page.reload()
  await login()
  await page.getByRole('heading', { name: 'New meeting type' }).waitFor()
  assert.equal(await name.inputValue(), 'Private unfinished offer')
  assert.equal(
    await page.getByLabel('Description', { exact: true }).inputValue(),
    'Private recovery notes',
  )
  assert.equal(await page.getByLabel('Duration (minutes)', { exact: true }).inputValue(), '23')
  assert.equal(
    await page.getByLabel('Public address', { exact: true }).inputValue(),
    'private-recovery-offer',
  )
  assert.equal(mutations, 0, 'Login must not replay a mutation')
  await popup.goto(`${origin}/admin/links/new`)
  assert.equal(await popup.getByLabel('Name', { exact: true }).inputValue(), '')
  assert.ok(
    !(await page.evaluate(() => JSON.stringify({ ...sessionStorage, ...localStorage }))).includes(
      'Private recovery notes',
    ),
  )
  page.once('dialog', (dialog) => dialog.dismiss())
  await page.getByRole('link', { name: 'Cancel', exact: true }).click()
  assert.equal(await name.inputValue(), 'Private unfinished offer')
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('link', { name: 'Cancel', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  await page.getByRole('link', { name: 'Create meeting type' }).click()
  assert.equal(await name.inputValue(), '')
  await page.goBack()
  await page.goBack()
  await page.getByRole('heading', { name: 'New meeting type' }).waitFor()
  assert.equal(await name.inputValue(), '', 'History must not resurrect a discarded draft')
  await page.getByRole('link', { name: 'Cancel', exact: true }).click()
  const created = await context.request.post(`${origin}/api/v1/admin/meeting-types`, {
    headers: { 'X-Calendar-Request': '1' },
    data: { name: 'Recovery saved offer', slug: 'recovery-saved', durationMinutes: 30 },
  })
  assert.equal(created.status(), 201)
  const type = await created.json()
  await page.goto(`${origin}/admin/links/${type.id}/edit?from=links`)
  await name.fill('Recovery edited offer')
  await context.request.delete(`${origin}/api/v1/admin/session`, {
    headers: { 'X-Calendar-Request': '1' },
  })
  // Focus/session polling also recovers an unfinished edit, without Save.
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await login()
  await page.getByRole('heading', { name: 'Edit meeting type' }).waitFor()
  assert.equal(await name.inputValue(), 'Recovery edited offer')
  assert.equal(new URL(page.url()).pathname, `/admin/links/${type.id}/edit`)
  assert.equal(new URL(page.url()).search, '?from=links')
  const unchanged = await context.request.get(`${origin}/api/v1/admin/meeting-types/${type.id}`)
  assert.equal((await unchanged.json()).name, 'Recovery saved offer')
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  const row = page.getByRole('listitem').filter({ hasText: 'Recovery edited offer' })
  await row.getByText('Hidden', { exact: true }).waitFor()
  await context.request.delete(`${origin}/api/v1/admin/session`, {
    headers: { 'X-Calendar-Request': '1' },
  })
  await row.getByRole('button', { name: 'Publish', exact: true }).click()
  await page.getByRole('heading', { name: 'Administrator login' }).waitFor()
  const beforePublishLogin = mutations
  await login()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  await row.getByText('Hidden', { exact: true }).waitFor()
  assert.equal(mutations, beforePublishLogin, 'Login must not replay Publish')
  await row.getByRole('button', { name: 'Publish', exact: true }).click()
  await row.getByText('Published', { exact: true }).waitFor()
  await row.getByRole('button', { name: 'Hide', exact: true }).click()
  await row.getByText('Hidden', { exact: true }).waitFor()
  await page.goto(`${origin}/admin/login?returnTo=https://example.com/steal`)
  await login()
  await page.getByRole('heading', { name: 'Home', exact: true }).waitFor()
  assert.equal(new URL(page.url()).origin, origin)
  assert.equal(new URL(page.url()).pathname, '/admin')
  console.log(
    'Administrator tab-private recovery, refresh, opener privacy, no replay and discard passed.',
  )
} finally {
  await browser.close()
}
