import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

// /clear as the person types it at the prompt.
const CLEAR = { command: 'clear', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as const
const START = { cwd: '/w', surface: 'terminal', isInteractive: true } as const

// Stands for the engine: records each command the mod runs and each prompt it
// submits (as "prompt"), answers its scripts with <printed> (a script left out
// fails), and holds a role file for big-cheese alone. The clock is mocked so
// the queued commands can be let run.
function engine(on: On, printed: Record<string, string>) {
  const ran: string[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.id', () => ({ value: 'abc' }))
  on('command.run', (_, e) => {
    ran.push(`/${e.command} ${e.args}`.trim())
    return { text: '' }
  })
  on('prompt.submit', (_, e) => {
    ran.push('prompt')
    return { text: e.text }
  })
  on('process.run', (_, e) => {
    const script = e.argv[0].split('/').pop() ?? ''
    const stdout = printed[script]
    return { value: { exitCode: stdout === undefined ? 1 : 0, stdout: stdout ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('fs.exists', (_, e) => ({ value: e.path.endsWith('/roles/big-cheese.md') }))
  return { ran, clock: mock.clock(on) }
}

const PET = { 'session-name': 'loyal-fly\n', 'claim-colour': 'blue\n' }
const BIG_CHEESE = { 'role-name': 'big-cheese\n', 'session-name': 'big-cheese\n', 'claim-colour': 'red\n' }

test('a session is named and coloured once it starts', async ($, on) => {
  const { ran, clock } = engine(on, PET)

  await $.session.start(START)
  await clock.settle()
  expect(ran).toEqual(['/rename loyal-fly', '/color blue'])
})

test('/clear gives the session its name and colour back', async ($, on) => {
  const { ran, clock } = engine(on, PET)
  await $.session.start(START)
  await clock.settle()
  ran.length = 0

  await $.command.run(CLEAR)
  await clock.settle()
  expect(ran).toEqual(['/clear', '/rename loyal-fly', '/color blue'])
})

test('a script that fails leaves that part as Claude has it', async ($, on) => {
  const { ran, clock } = engine(on, { 'session-name': 'loyal-fly\n' })

  await $.session.start(START)
  await clock.settle()
  expect(ran).toEqual(['/rename loyal-fly'])
})

test('a role session starts on its own, once it has its name', async ($, on) => {
  const { ran, clock } = engine(on, BIG_CHEESE)

  await $.session.start(START)
  await clock.settle()
  expect(ran).toEqual(['/rename big-cheese', '/color red', 'prompt'])
})

test('a role with no brief is named but waits for you', async ($, on) => {
  const { ran, clock } = engine(on, { 'role-name': 'dotty\n', 'session-name': 'dotty\n', 'claim-colour': 'red\n' })

  await $.session.start(START)
  await clock.settle()
  expect(ran).toEqual(['/rename dotty', '/color red'])
})

test('a reload of the mod in the same process does not start the role again', async ($, on) => {
  const { ran, clock } = engine(on, BIG_CHEESE)
  await $.session.start(START)
  await clock.settle()
  ran.length = 0

  await $.session.start(START)
  await clock.settle()
  expect(ran).toEqual(['/rename big-cheese', '/color red'])
})

test('/clear starts the role again', async ($, on) => {
  const { ran, clock } = engine(on, BIG_CHEESE)
  await $.session.start(START)
  await clock.settle()
  ran.length = 0

  await $.command.run(CLEAR)
  await clock.settle()
  expect(ran).toEqual(['/clear', '/rename big-cheese', '/color red', 'prompt'])
})
