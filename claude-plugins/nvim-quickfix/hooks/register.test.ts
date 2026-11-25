import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import type { QuickfixState } from '../types'
import { MAX_ENTRIES } from './register'

const WALK: QuickfixState = {
  id: 7,
  title: 'Auth flow',
  current: 3,
  visited: [1, 2, 3, 5],
  changedtick: 1,
  entries: [1, 2, 3, 4, 5].map((n) => ({ path: 'src/auth.rs', line: n * 10, text: `stop ${n}` })),
}

// Stands for the engine: $NVIM is `server`, and `nvim-qf state` answers what `answer` holds when asked.
function engine(on: On, server: string | undefined, answer: { exitCode: number; stdout: string }) {
  const asked: (Record<string, string> | undefined)[] = []
  on('env.get', (_, e) => ({ value: e.name === 'NVIM' ? server : undefined }))
  on('process.run', (_, e) => {
    asked.push(e.init?.env)
    return { value: { ...answer, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('prompt.submit', (_, e) => ({ text: e.text, context: e.context }))
  return { asked, answer }
}

// A prompt as typed at the composer.
const typed = (text: string) => ({ text, wait: false, origin: { kind: 'composer' as const } })

const listing = (state: QuickfixState | null) => ({ exitCode: 0, stdout: JSON.stringify(state) })

test('a prompt carries the list, where I am in it and its entries', async ($, on) => {
  const { asked } = engine(on, '/run/nvim.sock', listing(WALK))

  const { context } = await $.prompt.submit(typed('next?'))

  expect(asked).toEqual([{ NVIM: '/run/nvim.sock' }])
  expect(context).toEqual([
    [
      'nvim quickfix list "Auth flow": on entry 3 of 5, visited 1-3, 5.',
      '1. src/auth.rs:10: stop 1',
      '2. src/auth.rs:20: stop 2',
      '3. src/auth.rs:30: stop 3',
      '4. src/auth.rs:40: stop 4',
      '5. src/auth.rs:50: stop 5',
    ].join('\n'),
  ])
})

test('the next prompt on the same list carries only where I am', async ($, on) => {
  engine(on, '/run/nvim.sock', listing(WALK))
  await $.prompt.submit(typed('first'))

  const { context } = await $.prompt.submit(typed('second'))

  expect(context).toEqual(['nvim quickfix list "Auth flow", entries as last listed: on entry 3 of 5, visited 1-3, 5.'])
})

test('a list that changed since is listed again', async ($, on) => {
  const { answer } = engine(on, '/run/nvim.sock', listing(WALK))
  await $.prompt.submit(typed('first'))
  answer.stdout = JSON.stringify({ ...WALK, changedtick: 2, visited: [] })

  const { context } = await $.prompt.submit(typed('second'))

  expect(context?.[0]?.split('\n')[0]).toBe('nvim quickfix list "Auth flow": on entry 3 of 5, none visited yet.')
  expect(context?.[0]?.split('\n')).toHaveLength(6)
})

test('a long list is cut short, saying how many more there are', async ($, on) => {
  const entries = Array.from({ length: MAX_ENTRIES + 3 }, (_, i) => ({ path: 'a.rs', line: i + 1, text: 'hit' }))
  engine(on, '/run/nvim.sock', listing({ ...WALK, entries, visited: [] }))

  const { context } = await $.prompt.submit(typed('where?'))

  const lines = context?.[0]?.split('\n') ?? []
  expect(lines).toHaveLength(MAX_ENTRIES + 2)
  expect(lines.at(-1)).toBe('… and 3 more')
})

test('an empty list adds nothing', async ($, on) => {
  engine(on, '/run/nvim.sock', listing(null))

  const { context } = await $.prompt.submit(typed('hi'))

  expect(context).toBeUndefined()
})

test('outside nvim nothing is asked or added', async ($, on) => {
  const { asked } = engine(on, undefined, listing(WALK))

  const { context } = await $.prompt.submit(typed('hi'))

  expect(asked).toEqual([])
  expect(context).toBeUndefined()
})

test('an nvim that cannot say still lets the prompt in, adding nothing', async ($, on) => {
  engine(on, '/run/nvim.sock', { exitCode: 1, stdout: '' })

  const result = await $.prompt.submit(typed('hi'))

  expect(result.text).toBe('hi')
  expect(result.context).toBeUndefined()
})
