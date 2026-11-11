import { readFileSync } from 'node:fs'
import { execFileSync, spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim()
const zero = '0'.repeat(40)
const sha = (value) => {
  if (!/^[a-f0-9]{40}$/.test(value ?? '')) throw new Error('Missing or invalid event SHA')
  git('cat-file', '-e', `${value}^{commit}`)
  return value
}

try {
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'))
  const name = process.env.GITHUB_EVENT_NAME
  if (name !== 'push' && name !== 'pull_request') throw new Error('Unsupported event')
  if (name === 'push' && event.after === zero) {
    console.log('Deleted ref: no new commits')
  } else {
    // The immutable adoption boundary exempts only the pre-hook scaffold history.
    const baseline = sha(readFileSync(new URL('./commitlint-baseline', import.meta.url), 'utf8').trim())
    let head, base
    if (name === 'pull_request') {
      head = sha(event.pull_request?.head?.sha)
      base = sha(event.pull_request?.base?.sha)
    } else {
      head = sha(event.after)
      if (event.before !== zero) {
        base = sha(event.before)
      } else if (event.ref !== `refs/heads/${event.repository?.default_branch}`) {
        const branch = event.repository?.default_branch
        if (!branch) throw new Error('Missing default branch for new ref')
        // Full checkout supplies remote branch refs. A first publication may have none.
        const ref = `refs/remotes/origin/${branch}`
        const found = spawnSync('git', ['rev-parse', '--verify', ref], { encoding: 'utf8' })
        if (found.status === 0) base = sha(found.stdout.trim())
      }
    }
    const commits = git('rev-list', '--reverse', head, '--not', baseline, ...(base ? [base] : []))
      .split('\n').filter(Boolean)
    let failed = false
    for (const commit of commits) {
      console.log(`Commitlint: ${commit}`)
      const result = spawnSync(process.execPath, [
        fileURLToPath(new URL('./node_modules/@commitlint/cli/cli.js', import.meta.url)),
        '--config', fileURLToPath(new URL('./commitlint.config.cjs', import.meta.url)),
      ], { input: git('show', '-s', '--format=%B', commit), stdio: ['pipe', 'inherit', 'inherit'] })
      if (result.error) throw result.error
      if (result.status !== 0) failed = true
    }
    if (failed) process.exitCode = 1
    if (!commits.length) console.log('No new commits to lint')
  }
} catch (error) {
  console.error(`Commit range check failed: ${error.message}`)
  process.exitCode = 1
}
