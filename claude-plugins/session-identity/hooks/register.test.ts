import type { CommandRunInput, On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

// Stands for the engine: records each command the mod runs and each script's
// arguments, and answers its scripts with <printed> (a script left out fails).
// /clear moves the session from id abc to def, as Claude does. The clock is
// mocked so the queued commands can be let run.
function engine(on: On, printed: Record<string, string>) {
  const ran: string[] = []
  const scripts: string[][] = []
  let id = 'abc'
  on('session.id', () => ({ value: id }))
  on('command.run', (_, e) => {
    ran.push(`/${e.command} ${e.args}`.trim())
    if (e.command === 'clear') id = 'def'
    return { text: '' }
  })
  on('process.run', (_, e) => {
    const [script = '', ...args] = [e.argv[0]?.split('/').pop(), ...e.argv.slice(1)]
    scripts.push([script, ...args])
    const stdout = printed[[script, ...args.slice(0, 1)].join(' ')] ?? printed[script]
    return { value: { exitCode: stdout === undefined ? 1 : 0, stdout: stdout ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  return { ran, scripts, clock: mock.clock(on) }
}

const PET = { 'session-name': 'loyal-fly\n', 'claim-colour': 'blue\n' }
const NAMED = { ...PET, 'recorded title': 'calm-otter\n', 'recorded colour': 'cyan\n' }
const START = { cwd: '/w', surface: null, isInteractive: false }

// A command as the person types it at the prompt.
function typed(command: string): CommandRunInput {
  return { command, args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } }
}

test('a session with no title is named and coloured', async ($, on) => {
  const { ran, scripts, clock } = engine(on, PET)

  await $.session.start(START)
  await clock.settle()
  expect(scripts).toContainEqual(['session-name', 'abc'])
  expect(scripts).toContainEqual(['claim-colour'])
  expect(ran).toEqual(['/rename loyal-fly', '/color blue'])
})

test("a session whose transcript has a title keeps it and asks back the colour it had", async ($, on) => {
  const { ran, scripts, clock } = engine(on, NAMED)

  await $.session.start(START)
  await clock.settle()
  expect(scripts).toContainEqual(['recorded', 'title', 'abc'])
  expect(scripts).toContainEqual(['recorded', 'colour', 'abc'])
  expect(scripts).toContainEqual(['claim-colour', 'cyan'])
  expect(scripts.map(([script]) => script)).not.toContain('session-name')
  expect(ran).toEqual(['/color blue'])
})

test('a /clear gives the colour back from the transcript it leaves, keeping the title', async ($, on) => {
  const { ran, scripts, clock } = engine(on, NAMED)

  await $.command.run(typed('clear'))
  await clock.settle()
  expect(scripts).toContainEqual(['recorded', 'colour', 'abc'])
  expect(scripts).toContainEqual(['claim-colour', 'cyan'])
  expect(ran).toEqual(['/clear', '/color blue'])
})

test('a /clear of a session with no title names it', async ($, on) => {
  const { ran, clock } = engine(on, PET)

  await $.command.run(typed('clear'))
  await clock.settle()
  expect(ran).toEqual(['/clear', '/rename loyal-fly', '/color blue'])
})

test('other commands leave the name and colour alone', async ($, on) => {
  const { ran, scripts, clock } = engine(on, PET)

  await $.command.run(typed('compact'))
  await clock.settle()
  expect(ran).toEqual(['/compact'])
  expect(scripts).toEqual([])
})

test('a script that fails leaves that part as Claude has it', async ($, on) => {
  const { ran, clock } = engine(on, { 'session-name': 'loyal-fly\n' })

  await $.session.start(START)
  await clock.settle()
  expect(ran).toEqual(['/rename loyal-fly'])
})
