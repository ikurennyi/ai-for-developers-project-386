import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext()
  const page = await context.newPage()
  const origin = process.env.APP_ORIGIN
  assert.ok(origin, 'APP_ORIGIN is required')
  await page.goto(`${origin}/admin/bookings`)
  await page.getByRole('heading', { name: 'Administrator login' }).waitFor()
  await page.getByLabel('Username', { exact: true }).fill('owner-browser')
  await page.getByLabel('Password', { exact: true }).fill('wrong-password')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('alert').filter({ hasText: 'Invalid username or password' }).waitFor()
  await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('heading', { name: 'Bookings', exact: true }).waitFor()
  assert.equal(new URL(page.url()).pathname, '/admin/bookings')
  await page.reload()
  await page.getByRole('heading', { name: 'Bookings', exact: true }).waitFor()
  await page.getByRole('link', { name: 'Links', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  assert.ok(
    (await context.cookies()).some(
      (cookie) =>
        cookie.name === 'calendar_admin' && cookie.httpOnly && cookie.sameSite === 'Strict',
    ),
  )
  await page.getByRole('button', { name: 'Log out', exact: true }).click()
  await page.getByRole('heading', { name: 'Administrator login' }).waitFor()
  await page.goto(`${origin}/admin`)
  await page.getByRole('heading', { name: 'Administrator login' }).waitFor()
  await page.getByLabel('Username', { exact: true }).fill('owner-browser')
  await page.getByLabel('Password', { exact: true }).fill('browser-only-password-24!')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('heading', { name: 'Home', exact: true }).waitFor()
  assert.equal(new URL(page.url()).pathname, '/admin')
  // The server session has been revoked in another tab: focus revalidates it.
  const second = await context.newPage()
  await second.goto(`${origin}/admin/links`)
  await second.getByRole('button', { name: 'Log out', exact: true }).click()
  await second.getByRole('heading', { name: 'Administrator login' }).waitFor()
  await page.bringToFront()
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await page.getByRole('heading', { name: 'Administrator login' }).waitFor()
  console.log(
    'Administrator browser navigation: direct return, invalid login, refresh, Home/Links/Bookings, logout and revoked-session recovery passed.',
  )
} finally {
  await browser.close()
}
