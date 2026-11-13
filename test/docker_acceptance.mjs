import assert from 'node:assert/strict'
import { readFileSync, writeFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { chromium } from '../frontend/node_modules/playwright/index.mjs'

const root = process.env.CALENDAR_DOCKER_CHECKOUT ?? fileURLToPath(new URL('..', import.meta.url))
const configPath = path.join(root, '.services/docker.env')
let source = readFileSync(configPath, 'utf8')
const config = Object.fromEntries(source.trim().split('\n').map((line) => {
  const index = line.indexOf('=')
  return [line.slice(0, index), line.slice(index + 1)]
}))
const origin = `https://localhost:${config.HTTPS_PORT}`
const headers = { 'X-Calendar-Request': '1' }
const docker = (...args) => execFileSync('ruby', ['scripts/docker.rb', ...args], {
  cwd: root, stdio: 'inherit', timeout: 240000,
  // A caller may have another worktree's database variables exported.
  env: { ...process.env, POSTGRES_PASSWORD: randomBytes(32).toString('hex') },
})
const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext({ ignoreHTTPSErrors: true, timezoneId: 'Pacific/Honolulu' })
  const page = await context.newPage()
  await page.goto(`${origin}/admin/links`)
  await page.getByLabel('Username', { exact: true }).fill(config.ADMIN_USERNAME)
  await page.getByLabel('Password', { exact: true }).fill(config.ADMIN_PASSWORD)
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  const cookies = await context.cookies()
  assert.ok(cookies.some((cookie) => cookie.secure && cookie.httpOnly), 'production uses secure HttpOnly sessions')
  const api = context.request
  const get = async (path) => {
    const response = await api.get(`${origin}${path}`)
    assert.equal(response.status(), 200, path)
    return response.json()
  }
  const initial = (await get('/api/v1/admin/meeting-types')).meetingTypes
  assert.equal(initial.length, 2, 'initial offers are not recreated by repeated initialization')
  const type = initial[0]
  const other = initial[1]
  // A repeated acceptance run can use the previously edited hidden initial offer.
  assert.equal((await api.put(`${origin}/api/v1/admin/meeting-types/${type.id}/publication`, {
    headers, data: { published: true },
  })).status(), 200)
  const calendar = await get(`/api/v1/meeting-types/${type.slug}/availability`)
  const day = calendar.days.find((entry) => entry.date > calendar.today && entry.intervals.some((slot) => slot.available))
  const interval = day.intervals.find((slot) => slot.available)
  const guest = await browser.newContext({ ignoreHTTPSErrors: true, timezoneId: 'Pacific/Honolulu' })
  const guestPage = await guest.newPage()
  const query = new URLSearchParams({ date: day.date, start: interval.startsAt })
  await guestPage.goto(`${origin}/book/${type.slug}/details?${query}`)
  await guestPage.getByLabel('Your name', { exact: true }).fill('Docker Guest')
  await guestPage.getByLabel('Email address', { exact: true }).fill('docker-guest@example.com')
  await guestPage.getByLabel('Additional notes (optional)', { exact: true }).fill('Persistent private notes')
  const confirmationResponse = guestPage.waitForResponse((response) => response.request().method() === 'POST' && response.url().endsWith('/bookings'))
  await guestPage.getByRole('button', { name: 'Confirm booking', exact: true }).click()
  const confirmed = await confirmationResponse
  assert.equal(confirmed.status(), 201)
  const booking = await confirmed.json()
  assert.equal(booking.meetingName, type.name)
  assert.equal(booking.meetingDescription, type.description)
  assert.equal(booking.durationMinutes, type.durationMinutes)
  assert.equal(Date.parse(booking.startsAt), Date.parse(interval.startsAt))
  assert.equal(Date.parse(booking.endsAt) - Date.parse(booking.startsAt), type.durationMinutes * 60000)
  await guestPage.getByRole('heading', { name: 'This meeting is scheduled', exact: true }).waitFor()
  await guestPage.getByText('No confirmation email will be sent.', { exact: true }).waitFor()

  const suffix = Date.now()
  let row = page.getByRole('listitem').filter({ hasText: type.name })
  await row.getByRole('link', { name: 'Edit', exact: true }).click()
  await page.getByLabel('Name', { exact: true }).fill(`Docker edited ${suffix}`)
  await page.getByLabel('Description', { exact: true }).fill('Preserved initialization edit')
  await page.getByLabel('Duration (minutes)', { exact: true }).fill('20')
  await page.getByLabel('Public address', { exact: true }).fill(`docker-edited-${suffix}`)
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await page.getByRole('heading', { name: 'Links', exact: true }).waitFor()
  row = page.getByRole('listitem').filter({ hasText: `Docker edited ${suffix}` })
  await row.getByRole('button', { name: 'Hide', exact: true }).click()
  await row.getByText('Hidden', { exact: true }).waitFor()
  const edited = await get(`/api/v1/admin/meeting-types/${type.id}`)
  const before = (await get('/api/v1/admin/bookings?period=upcoming&page=1')).bookings.find((entry) => entry.id === booking.id)
  assert.ok(before, 'created booking is visible in authenticated HTTP API')
  await page.goto(`${origin}/admin/bookings`)
  await page.getByText('docker-guest@example.com', { exact: true }).first().waitFor()

  const verifyPersistence = async () => {
    assert.deepEqual(await get(`/api/v1/admin/meeting-types/${type.id}`), edited)
    assert.equal((await get('/api/v1/admin/meeting-types')).meetingTypes.length, 2)
    const after = (await get('/api/v1/admin/bookings?period=upcoming&page=1')).bookings.find((entry) => entry.id === booking.id)
    assert.deepEqual(after, before, 'snapshot, exact instants and guest data survive')
    assert.equal(after.meetingName, type.name)
    assert.equal(after.startsAt, booking.startsAt)
    assert.equal(after.endsAt, booking.endsAt)
    const availability = await get(`/api/v1/meeting-types/${other.slug}/availability`)
    const occupied = availability.days.flatMap((entry) => entry.intervals).find((slot) => Date.parse(slot.startsAt) === Date.parse(booking.startsAt))
    assert.equal(occupied.available, false, 'hidden original type still occupies shared calendar')
    const overlap = await guest.request.post(`${origin}/api/v1/meeting-types/${other.slug}/bookings`, {
      data: {
        startsAt: booking.startsAt,
        meetingType: { name: other.name, description: other.description, durationMinutes: other.durationMinutes },
        guestName: 'Overlapping Docker Guest', guestEmail: 'docker-overlap@example.com',
      },
    })
    assert.equal(overlap.status(), 409, 'persistent occupancy rejects a new overlapping booking')
    assert.equal((await overlap.json()).code, 'occupied')
    assert.equal((await api.get(`${origin}/api/v1/meeting-types/${type.slug}/availability`)).status(), 404)
    assert.equal((await api.get(`${origin}/api/v1/meeting-types/${edited.slug}/availability`)).status(), 404)
    await page.reload()
    await page.getByText('docker-guest@example.com', { exact: true }).first().waitFor()
  }
  docker('restart')
  await verifyPersistence()
  docker('recreate')
  await verifyPersistence()
  docker('stop')
  docker('up')
  await verifyPersistence()
  console.log('Docker booking/admin edit, restart and recreation retain snapshots, instants, publication, initialization edits and shared occupancy')

  const replacement = randomBytes(24).toString('hex')
  execFileSync('ruby', ['scripts/docker.rb', 'exec', '-e', 'ADMIN_NEW_PASSWORD', 'app', 'bundle', 'exec', 'rails', 'admin:change_password'], {
    cwd: root, env: { ...process.env, ADMIN_NEW_PASSWORD: replacement }, stdio: 'inherit', timeout: 60000,
  })
  source = source.replace(/^ADMIN_PASSWORD=.*$/m, `ADMIN_PASSWORD=${replacement}`)
  writeFileSync(configPath, source, { mode: 0o600 })
  assert.equal((await api.get(`${origin}/api/v1/admin/meeting-types`)).status(), 401, 'old session revoked')
  const login = (password) => api.post(`${origin}/api/v1/admin/session`, {
    headers, data: { username: config.ADMIN_USERNAME, password },
  })
  assert.equal((await login(config.ADMIN_PASSWORD)).status(), 401, 'old password rejected')
  assert.equal((await login(replacement)).status(), 200, 'rotated password accepted')
  await verifyPersistence()
  console.log('Server-side password rotation rejects old password and revokes existing session; new login preserves data')
} finally {
  await browser.close()
}
