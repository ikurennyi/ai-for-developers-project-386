import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const zero = '0'.repeat(40)

const gitHasCommit = (sha) => spawnSync('git', ['cat-file', '-e', `${sha}^{commit}`], {
  stdio: 'ignore',
}).status === 0

try {
  if (process.env.GITHUB_EVENT_NAME !== 'push') process.exit(0)

  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'))
  const before = event.before
  if (before === zero) process.exit(0)
  if (!/^[a-f0-9]{40}$/.test(before ?? '')) throw new Error('Missing or invalid push before SHA')
  if (gitHasCommit(before)) process.exit(0)

  const fetch = spawnSync('git', ['fetch', '--no-tags', 'origin', before], { stdio: 'inherit' })
  if (fetch.error) throw fetch.error
  if (fetch.status !== 0 || !gitHasCommit(before)) {
    throw new Error(`Could not fetch push before commit ${before}`)
  }

  console.log(`Fetched missing push before commit ${before}`)
} catch (error) {
  console.error(`Push before commit preparation failed: ${error.message}`)
  process.exitCode = 1
}
