import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext()
  const page = await context.newPage()
  const origin = process.env.APP_ORIGIN
  assert.ok(origin)
  await page.goto(`${origin}/admin/links`)
  await page.getByLabel('Username', { exact: true }).fill('owner-browser')
  await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  await page.getByRole('link', { name: 'Create meeting type' }).click()
  await page.getByRole('heading', { name: 'New meeting type' }).waitFor()
  await page.getByLabel('Name', { exact: true }).fill('  Browser planning  ')
  await page.getByLabel('Description', { exact: true }).fill('A focused conversation.')
  await page.getByLabel('Duration (minutes)', { exact: true }).fill('20')
  await page.getByLabel('Public address', { exact: true }).fill(' browser-planning ')
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  const offer = page.getByRole('listitem').filter({ hasText: 'Browser planning' })
  await offer.getByText('Hidden', { exact: true }).waitFor()
  assert.equal(
    await offer
      .getByRole('link', { name: '/book/browser-planning', exact: true })
      .getAttribute('href'),
    '/book/browser-planning',
  )
  await page.reload()
  await page.getByRole('listitem').filter({ hasText: 'Browser planning' }).waitFor()
  const publicOffers = await context.request.get(`${origin}/api/v1/meeting-types`)
  assert.ok(
    !(await publicOffers.json()).meetingTypes.some((type) => type.slug === 'browser-planning'),
  )
  await page.getByRole('link', { name: 'Create meeting type' }).click()
  const fields = {
    name: page.getByLabel('Name', { exact: true }),
    description: page.getByLabel('Description', { exact: true }),
    duration: page.getByLabel('Duration (minutes)', { exact: true }),
    slug: page.getByLabel('Public address', { exact: true }),
  }
  const save = page.getByRole('button', { name: 'Save', exact: true })
  let mutations = 0
  page.on('request', (request) => {
    if (request.method() === 'POST' && request.url().endsWith('/admin/meeting-types')) mutations++
  })
  await save.click()
  await page.getByText('Name must contain 1–100 characters.', { exact: true }).waitFor()
  await fields.name.fill('Validation draft')
  await fields.duration.fill('20')
  await fields.slug.fill('valid-draft')
  for (const [field, value, errorId] of [
    ['name', ' '.repeat(10), 'name-error'],
    ['name', 'a'.repeat(101), 'name-error'],
    ['description', 'a'.repeat(2001), 'description-error'],
    ['duration', '0', 'duration-error'],
    ['duration', '541', 'duration-error'],
    ['duration', '1.5', 'duration-error'],
    ['duration', '20minutes', 'duration-error'],
    ...['UPPER', '-edge', 'edge-', 'double--dash', 'two words', 'a_b', 'é', 'a'.repeat(81)].map(
      (value) => ['slug', value, 'slug-error'],
    ),
  ]) {
    const previous = await fields[field].inputValue()
    await fields[field].fill(value)
    await save.click()
    assert.ok((await page.locator(`#${errorId}`).textContent()).length > 0)
    assert.equal(await fields[field].inputValue(), value)
    await fields[field].fill(previous)
  }
  assert.equal(mutations, 0, 'Client validation must reject before sending a mutation')
  await fields.slug.fill('browser-planning')
  await save.click()
  await page.getByText('has already been taken', { exact: true }).waitFor()
  assert.equal(await fields.name.inputValue(), 'Validation draft')
  assert.equal(await fields.slug.inputValue(), 'browser-planning')
  await fields.slug.fill('browser-retry')
  await context.setOffline(true)
  await save.click()
  await page.getByText('Unable to save the meeting type.', { exact: false }).waitFor()
  assert.equal(await fields.slug.inputValue(), 'browser-retry')
  await context.setOffline(false)
  // Real network latency, not an API substitute: the request still reaches Rails.
  const cdp = await context.newCDPSession(page)
  await cdp.send('Network.enable')
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false,
    latency: 300,
    downloadThroughput: -1,
    uploadThroughput: -1,
  })
  const beforeSave = mutations
  await save.click()
  assert.equal(await page.getByRole('button', { name: 'Saving…' }).isDisabled(), true)
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  assert.equal(mutations, beforeSave + 1)
  await cdp.detach()
  await page.getByRole('link', { name: 'Create meeting type' }).click()
  await fields.name.fill('Unsaved draft')
  page.once('dialog', (dialog) => dialog.dismiss())
  await page.getByRole('link', { name: 'Cancel', exact: true }).click()
  assert.equal(await fields.name.inputValue(), 'Unsaved draft')
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('link', { name: 'Cancel', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  await page.getByRole('link', { name: 'Create meeting type' }).click()
  assert.equal(await fields.name.inputValue(), '')
  await fields.name.fill('Session recovery draft')
  await fields.duration.fill('7')
  await fields.slug.fill('session-recovery')
  // Revoke the actual server session in another tab, then save the current draft.
  const second = await context.newPage()
  await second.goto(`${origin}/admin/links`)
  await second.getByRole('button', { name: 'Log out', exact: true }).click()
  await second.getByRole('heading', { name: 'Administrator login' }).waitFor()
  await save.click()
  await page.getByRole('heading', { name: 'Administrator login' }).waitFor()
  const beforeLogin = mutations
  await page.getByLabel('Username', { exact: true }).fill('owner-browser')
  await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('heading', { name: 'New meeting type' }).waitFor()
  assert.equal(await fields.name.inputValue(), 'Session recovery draft')
  assert.equal(await fields.slug.inputValue(), 'session-recovery')
  assert.equal(mutations, beforeLogin, 'Login must never replay Save')
  await page.setViewportSize({ width: 375, height: 812 })
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
  // A different tab must not inherit the recovered form.
  await second.goto(`${origin}/admin/links/new`)
  assert.equal(await second.getByLabel('Name', { exact: true }).inputValue(), '')
  await save.click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  await page.getByRole('link', { name: 'Create meeting type' }).click()
  await fields.name.fill('名'.repeat(100))
  await fields.description.fill('<script>not executable</script>' + 'é'.repeat(1969))
  await fields.duration.fill('540')
  await fields.slug.fill('a'.repeat(80))
  await save.click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  assert.ok(
    (
      await page
        .getByRole('listitem')
        .filter({ hasText: '名'.repeat(100) })
        .textContent()
    ).includes('<script>not executable</script>'),
  )
  await page.getByRole('link', { name: 'Create meeting type' }).click()
  await fields.name.fill('X')
  await fields.description.fill(' '.repeat(2001))
  await fields.duration.fill('1')
  await fields.slug.fill('one-minute')
  await save.click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  console.log('Hidden meeting type browser creation and persisted Links passed.')
} finally {
  await browser.close()
}
