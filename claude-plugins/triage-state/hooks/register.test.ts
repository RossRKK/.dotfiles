import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import type { Review } from '../types'
import { MAX_FILES } from './register'

const REVIEW: Review = {
  root: '/repo',
  base: 'main',
  label: '#412',
  files: [
    { rel: 'a.rs', status: 'approved' },
    { rel: 'b.rs', status: 'rejected' },
    { rel: 'c.rs', status: 'changed' },
    { rel: 'd.rs', status: 'stale' },
    { rel: 'e.rs', status: 'changed' },
  ],
}

// Stands for the engine: a session in /repo/src, $NVIM is `server`, and nvim answers what `answer` holds.
function engine(on: On, server: string | undefined, answer: { exitCode: number; stdout: string }) {
  const asked: string[][] = []
  on('env.get', (_, e) => ({ value: e.name === 'NVIM' ? server : undefined }))
  on('session.cwd', () => ({ value: '/repo/src' }))
  on('process.run', (_, e) => {
    asked.push([...e.argv])
    return { value: { ...answer, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('prompt.submit', (_, e) => ({ text: e.text, context: e.context }))
  return { asked, answer }
}

// A prompt as typed at the composer.
const typed = (text: string) => ({ text, wait: false, origin: { kind: 'composer' as const } })

const nvimSays = (review: Review | null) => ({ exitCode: 0, stdout: JSON.stringify(review) })

test('a prompt carries the review, files grouped by what they need, from the session dir', async ($, on) => {
  const { asked } = engine(on, '/run/nvim.sock', nvimSays(REVIEW))

  const { context } = await $.prompt.submit(typed('next?'))

  expect(asked).toHaveLength(1)
  expect(asked[0]?.slice(0, 3)).toEqual(['nvim', '--server', '/run/nvim.sock'])
  expect(asked[0]?.[4]).toContain(`json_decode('"/repo/src"')`)
  expect(context).toEqual([
    [
      'triage: reviewing this repo against main (#412), 5 files: 1 rejected, 1 approved, then edited (to re-review), 2 not reviewed yet, 1 approved.',
      'rejected: b.rs',
      'approved, then edited (to re-review): d.rs',
      'not reviewed yet: c.rs, e.rs',
      'approved: a.rs',
    ].join('\n'),
  ])
})

test('an unchanged review is not told again', async ($, on) => {
  engine(on, '/run/nvim.sock', nvimSays(REVIEW))
  await $.prompt.submit(typed('first'))

  const { context } = await $.prompt.submit(typed('second'))

  expect(context).toBeUndefined()
})

test('a decision since is told as the whole review again', async ($, on) => {
  const { answer } = engine(on, '/run/nvim.sock', nvimSays(REVIEW))
  await $.prompt.submit(typed('first'))
  answer.stdout = JSON.stringify({ ...REVIEW, files: REVIEW.files.map((f) => ({ ...f, status: 'approved' })) })

  const { context } = await $.prompt.submit(typed('second'))

  expect(context).toEqual(['triage: reviewing this repo against main (#412), 5 files: 5 approved.\napproved: a.rs, b.rs, c.rs, d.rs, e.rs'])
})

test('review mode turned off after a report is told once', async ($, on) => {
  const { answer } = engine(on, '/run/nvim.sock', nvimSays(REVIEW))
  await $.prompt.submit(typed('first'))
  answer.stdout = 'null'

  const off = await $.prompt.submit(typed('second'))
  const after = await $.prompt.submit(typed('third'))

  expect(off.context?.[0]).toMatch(/^triage: review mode is now off/)
  expect(after.context).toBeUndefined()
})

test('no review, never reported, adds nothing', async ($, on) => {
  engine(on, '/run/nvim.sock', nvimSays(null))

  const { context } = await $.prompt.submit(typed('hi'))

  expect(context).toBeUndefined()
})

test('a long review is cut short, approvals first, saying how many more there are', async ($, on) => {
  const files = [
    ...Array.from({ length: MAX_FILES }, (_, i) => ({ rel: `open${i}.rs`, status: 'changed' as const })),
    { rel: 'done.rs', status: 'approved' as const },
  ]
  engine(on, '/run/nvim.sock', nvimSays({ ...REVIEW, files }))

  const { context } = await $.prompt.submit(typed('where?'))

  const lines = context?.[0]?.split('\n') ?? []
  expect(lines.some((l) => l.includes('done.rs'))).toBe(false)
  expect(lines.at(-1)).toBe('… and 1 more')
})

test('outside nvim nothing is asked or added', async ($, on) => {
  const { asked } = engine(on, undefined, nvimSays(REVIEW))

  const { context } = await $.prompt.submit(typed('hi'))

  expect(asked).toEqual([])
  expect(context).toBeUndefined()
})

test('an nvim that cannot say lets the prompt in, adding nothing and forgetting nothing', async ($, on) => {
  const { answer } = engine(on, '/run/nvim.sock', nvimSays(REVIEW))
  await $.prompt.submit(typed('first'))
  answer.exitCode = 1

  const failed = await $.prompt.submit(typed('hi'))
  answer.exitCode = 0
  const recovered = await $.prompt.submit(typed('again'))

  expect(failed.text).toBe('hi')
  expect(failed.context).toBeUndefined()
  expect(recovered.context).toBeUndefined()
})
