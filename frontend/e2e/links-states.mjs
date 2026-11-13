import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const origin = process.env.APP_ORIGIN
assert.ok(origin)
const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext()
  const page = await context.newPage()
  await page.goto(`${origin}/admin/links`)
  await page.getByLabel('Username', { exact: true }).fill('owner-browser')
  await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByText('No meeting types yet.', { exact: true }).waitFor()
  assert.equal(await page.getByRole('listitem').count(), 0)
  // Hold and then abort only the actual list transport; never fabricate API data.
  let release
  const held = new Promise((resolve) => {
    release = resolve
  })
  await page.route('**/api/v1/admin/meeting-types', async (route) => {
    await held
    await route.abort('failed')
  })
  await page.reload()
  await page.getByRole('status').filter({ hasText: 'Loading meeting types…' }).waitFor()
  assert.equal(await page.getByText('No meeting types yet.', { exact: true }).count(), 0)
  release()
  await page.getByRole('alert').filter({ hasText: 'Unable to load meeting types.' }).waitFor()
  assert.equal(await page.getByText('No meeting types yet.', { exact: true }).count(), 0)
  await page.unroute('**/api/v1/admin/meeting-types')
  await page.getByRole('button', { name: 'Retry', exact: true }).click()
  await page.getByText('No meeting types yet.', { exact: true }).waitFor()

  const whitespace =
    ' \t\n\v\f\r\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff'
  for (const [index, description] of [
    whitespace,
    '\ufeff'.repeat(2001),
    ' '.repeat(2001),
    whitespace.repeat(100),
    `${whitespace}Text${whitespace}`,
    '\u0085',
  ].entries()) {
    await page.getByRole('link', { name: 'Create meeting type', exact: true }).click()
    await page.getByLabel('Name', { exact: true }).fill(`${whitespace}Parity ${index}${whitespace}`)
    await page.getByLabel('Description', { exact: true }).fill(description)
    await page.getByLabel('Duration (minutes)', { exact: true }).fill('20')
    await page
      .getByLabel('Public address', { exact: true })
      .fill(`${whitespace}parity-${index}${whitespace}`)
    await page.getByRole('button', { name: 'Save', exact: true }).click()
    await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
    const response = await context.request.get(`${origin}/api/v1/admin/meeting-types`)
    assert.equal(response.status(), 200)
    const type = (await response.json()).meetingTypes.find(
      (entry) => entry.slug === `parity-${index}`,
    )
    assert.equal(type.name, `Parity ${index}`)
    // Textarea normalizes CRLF/CR to LF; all other nonempty characters survive.
    assert.equal(type.description, index < 4 ? '' : description.replace(/\r\n?/g, '\n'))
    assert.equal(description.trim() === '', index < 4)
  }
  console.log(
    'Links real empty/loading/error/retry and ASCII/Unicode whitespace form/server parity passed.',
  )
} finally {
  await browser.close()
}
