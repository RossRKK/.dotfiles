import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

// /clear as the person types it at the prompt.
const CLEAR = { command: 'clear', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as const
const START = { cwd: '/w', surface: 'terminal', isInteractive: true } as const
const ROLE = 'You are big-cheese.'
// A system prompt render as the engine raises one.
const COMPOSE = { model: 'm', promptModel: 'm', surfaces: ['terminal'], tools: [], outputStyle: null, traits: [] } as const

// Stands for the engine: records each command the mod runs, answers its
// scripts with <printed> (a script left out fails), and holds a role file for
// big-cheese alone. The clock is mocked so the queued commands can be let run.
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
  on('fs.exists', (_, e) => ({ value: e.path.endsWith('/roles/big-cheese.md') }))
  on('fs.read', () => ({ value: ROLE }))
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'intro', scope: 'shared' }] }))
  return { ran, clock: mock.clock(on) }
}

test('a session is named and coloured once it starts', async ($, on) => {
  const { ran, clock } = engine(on, { 'session-name': 'loyal-fly\n', 'claim-colour': 'blue\n' })

  await $.session.start(START)
  await clock.settle()
  expect(ran).toEqual(['/rename loyal-fly', '/color blue'])
})

test('/clear gives the session its name and colour back', async ($, on) => {
  const { ran, clock } = engine(on, { 'session-name': 'loyal-fly\n', 'claim-colour': 'blue\n' })
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

test("a role's brief is the system prompt's last section", async ($, on) => {
  engine(on, { 'session-name': 'big-cheese\n', 'claim-colour': 'red\n' })

  await $.session.start(START)
  const { sections } = await $.prompt.compose(COMPOSE)
  expect(sections.map((s) => s.id)).toEqual(['intro', 'session-identity:role'])
  expect(sections[1].text).toBe(ROLE)
  expect(sections[1].scope).toBe('session')
})

test('a session with no role keeps the system prompt as it is', async ($, on) => {
  engine(on, { 'session-name': 'loyal-fly\n', 'claim-colour': 'red\n' })

  await $.session.start(START)
  const { sections } = await $.prompt.compose(COMPOSE)
  expect(sections.map((s) => s.id)).toEqual(['intro'])
})
