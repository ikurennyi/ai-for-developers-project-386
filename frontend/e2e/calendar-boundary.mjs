import assert from 'node:assert/strict'
import { chromium } from 'playwright'

const origin = process.env.APP_ORIGIN
assert.ok(origin)
const browser = await chromium.launch({ headless: true })
try {
  const context = await browser.newContext({
    timezoneId: 'Pacific/Honolulu',
    viewport: { width: 320, height: 740 },
  })
  const page = await context.newPage()
  await page.goto(`${origin}/book/15-minute-meeting`)
  await page.getByRole('heading', { name: 'December 2026', exact: true }).waitFor()
  const previous = page.getByRole('button', { name: 'Previous month', exact: true })
  const next = page.getByRole('button', { name: 'Next month', exact: true })
  assert.equal(await previous.isDisabled(), true)
  assert.equal(await next.isEnabled(), true)
  assert.equal(await page.locator('[data-date="2026-12-27"]').isDisabled(), true)
  assert.equal(await page.locator('[aria-current="date"]').textContent(), '28Today')
  assert.equal(await page.locator('[data-date="2026-12-28"]').isEnabled(), true)

  // Reach controls only with Tab; no locator.focus(), click(), fill(), or DOM events.
  async function tabTo(locator) {
    for (let count = 0; count < 100; count++) {
      await page.keyboard.press('Tab')
      if (await locator.evaluate((element) => element === document.activeElement)) {
        const focus = await locator.evaluate((element) => {
          const style = getComputedStyle(element)
          return {
            visible: element.matches(':focus-visible'),
            width: parseFloat(style.outlineWidth),
            style: style.outlineStyle,
            color: style.outlineColor,
          }
        })
        assert.equal(focus.visible, true)
        assert.ok(focus.width >= 2 && focus.style !== 'none' && focus.color !== 'rgba(0, 0, 0, 0)')
        return
      }
    }
    assert.fail(`Control is not keyboard reachable: ${locator}`)
  }
  await tabTo(page.locator('[data-date="2026-12-28"]'))
  await page.keyboard.press('Enter')
  const started = page.locator('[data-start="2026-12-28T08:00:00Z"]')
  await started.waitFor()
  assert.equal(await started.isDisabled(), true)
  assert.match(await started.textContent(), /09:00–09:15 · Unavailable/)
  await tabTo(next)
  await page.keyboard.press('Enter')
  await page.getByRole('heading', { name: 'January 2027', exact: true }).waitFor()
  assert.equal(await next.isDisabled(), true)
  assert.equal(await previous.isEnabled(), true)
  assert.equal(await page.locator('[data-date="2026-12-31"].outside').isDisabled(), true)
  assert.equal(await page.locator('[data-date="2027-01-09"]').isDisabled(), true)
  assert.equal(await page.locator('[data-date="2027-01-10"]').isDisabled(), true)
  assert.equal(await page.locator('[data-date="2027-01-11"]').isDisabled(), true)
  assert.equal(await page.locator('[data-date="2027-01-08"]').isEnabled(), true)
  await tabTo(previous)
  await page.keyboard.press('Enter')
  await page.getByRole('heading', { name: 'December 2026', exact: true }).waitFor()
  assert.equal(await previous.isDisabled(), true)
  await tabTo(next)
  await page.keyboard.press('Enter')
  await tabTo(page.locator('[data-date="2027-01-04"]'))
  await page.keyboard.press('Enter')
  const interval = page.locator('[data-start="2027-01-04T08:00:00Z"]')
  await interval.waitFor()
  assert.match(await interval.textContent(), /09:00–09:15 · Available/)
  await tabTo(interval)
  await page.keyboard.press('Enter')
  assert.equal(await interval.getAttribute('aria-pressed'), 'true')
  const selectedBorder = await interval.evaluate(
    (element) => getComputedStyle(element).borderTopWidth,
  )
  assert.equal(selectedBorder, '3px', 'selection has a structural, non-colour-only border')
  await tabTo(page.getByRole('button', { name: 'Continue', exact: true }))
  await page.keyboard.press('Enter')
  await page.getByRole('heading', { name: 'Guest details', exact: true }).waitFor()
  const summary = await page.locator('.meeting-summary').boundingBox()
  const form = await page.locator('section[aria-labelledby="guest-heading"]').boundingBox()
  assert.ok(form.y >= summary.y + summary.height, 'phone form stacks below the summary')
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
  assert.match(await page.locator('.meeting-summary').textContent(), /09:00–09:15 Europe\/Berlin/)
  await tabTo(page.getByLabel('Your name', { exact: true }))
  await page.keyboard.type('Keyboard Guest')
  await tabTo(page.getByLabel('Email address', { exact: true }))
  await page.keyboard.type('keyboard@example.test')
  await tabTo(page.getByLabel('Additional notes (optional)', { exact: true }))
  await page.keyboard.type('Phone keyboard booking')
  await tabTo(page.getByRole('button', { name: 'Confirm booking', exact: true }))
  await page.keyboard.press('Enter')
  await page.getByRole('heading', { name: 'This meeting is scheduled', exact: true }).waitFor()
  await page.getByText('No confirmation email will be sent.', { exact: true }).waitFor()
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
  const blocks = await page.locator('.booking-success > *').evaluateAll((elements) =>
    elements.map((element) => {
      const box = element.getBoundingClientRect()
      return { top: box.top, bottom: box.bottom, left: box.left, right: box.right }
    }),
  )
  blocks.forEach((box, index) => {
    assert.ok(box.left >= 0 && box.right <= 320)
    if (index) assert.ok(box.top >= blocks[index - 1].bottom, 'success content stacks vertically')
  })
  await tabTo(page.getByRole('link', { name: 'Book another meeting', exact: true }))
  await page.keyboard.press('Enter')
  await page.getByRole('heading', { name: 'Book a meeting', exact: true }).waitFor()
  console.log(
    'Deterministic Dec/Jan boundaries, keyboard-only booking, visible focus, non-colour selection and phone form/success passed.',
  )
} finally {
  await browser.close()
}
