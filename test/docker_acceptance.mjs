import { chromium } from '../frontend/node_modules/playwright/index.mjs'

const browser = await chromium.launch({ headless: true })
try {
  const page = await browser.newPage({ ignoreHTTPSErrors: true })
  await page.goto(process.env.CALENDAR_URL ?? 'https://localhost:8443')
  await page.getByRole('heading', { name: /Calendar/ }).waitFor()
  console.log('Docker HTTPS application renders')
} finally {
  await browser.close()
}
