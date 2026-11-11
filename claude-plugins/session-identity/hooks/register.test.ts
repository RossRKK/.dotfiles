import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

// /clear as the person types it at the prompt.
const CLEAR = { command: 'clear', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as const
const START = { cwd: '/w', surface: 'terminal', isInteractive: true } as const

// Stands for the engine: records each command the mod runs and answers its
// scripts with <printed> (a script left out fails). The clock is mocked so the
// queued commands can be let run.
function engine(on: On, printed: Record<string, string>) {
  const ran: string[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.id', () => ({ value: 'abc' }))
  on('command.run', (_, e) => {
    ran.push(`/${e.command} ${e.args}`.trim())
    return { text: '' }
  })
  on('process.run', (_, e) => {
    const script = e.argv[0].split('/').pop() ?? ''
    const stdout = printed[script]
    return { value: { exitCode: stdout === undefined ? 1 : 0, stdout: stdout ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return { ran, clock: mock.clock(on) }
}

const PET = { 'session-name': 'loyal-fly\n', 'claim-colour': 'blue\n' }

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
