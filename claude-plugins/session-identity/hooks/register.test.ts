import type { ClassicEventOf, On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

type Start = ClassicEventOf['classic.SessionStart']

// SessionStart as Claude fires it, for a <source> and the title the session already has.
function start(source: Start['source'], session_title?: string): Start {
  return { hook_event_name: 'SessionStart', session_id: 'abc', transcript_path: '/t/abc.jsonl', cwd: '/w', source, session_title }
}

// Stands for the engine: records each command the mod runs and each script's
// arguments, and answers its scripts with <printed> (a script left out fails).
// The clock is mocked so the queued commands can be let run.
function engine(on: On, printed: Record<string, string>) {
  const ran: string[] = []
  const scripts: string[][] = []
  on('command.run', (_, e) => {
    ran.push(`/${e.command} ${e.args}`.trim())
    return { text: '' }
  })
  on('process.run', (_, e) => {
    const script = e.argv[0]?.split('/').pop() ?? ''
    scripts.push([script, ...e.argv.slice(1)])
    const stdout = printed[script]
    return { value: { exitCode: stdout === undefined ? 1 : 0, stdout: stdout ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('classic.SessionStart', () => ({}))
  return { ran, scripts, clock: mock.clock(on) }
}

const PET = { 'session-name': 'loyal-fly\n', 'claim-colour': 'blue\n' }

test('a new session is named and coloured', async ($, on) => {
  const { ran, clock } = engine(on, PET)

  await $.classic.SessionStart(start('startup'))
  await clock.settle()
  expect(ran).toEqual(['/rename loyal-fly', '/color blue'])
})

test('a resumed session that has a name keeps it and gets only its colour', async ($, on) => {
  const { ran, scripts, clock } = engine(on, PET)

  await $.classic.SessionStart(start('resume', 'calm-otter'))
  await clock.settle()
  expect(ran).toEqual(['/color blue'])
  expect(scripts.map(([script]) => script)).not.toContain('session-name')
})

test('a resumed session with no name is named', async ($, on) => {
  const { ran, clock } = engine(on, PET)

  await $.classic.SessionStart(start('resume'))
  await clock.settle()
  expect(ran).toEqual(['/rename loyal-fly', '/color blue'])
})

test('a cleared session with no name is named', async ($, on) => {
  const { ran, clock } = engine(on, PET)

  await $.classic.SessionStart(start('clear'))
  await clock.settle()
  expect(ran).toEqual(['/rename loyal-fly', '/color blue'])
})

test('a compaction leaves the name and colour alone', async ($, on) => {
  const { ran, scripts, clock } = engine(on, PET)

  await $.classic.SessionStart(start('compact', 'calm-otter'))
  await clock.settle()
  expect(ran).toEqual([])
  expect(scripts).toEqual([])
})

test("a fork is named after its parent's title", async ($, on) => {
  const { ran, scripts, clock } = engine(on, { ...PET, 'session-name': 'brave-otter\n' })

  await $.classic.SessionStart(start('fork', 'calm-otter'))
  await clock.settle()
  expect(scripts).toContainEqual(['session-name', '--fork-of', 'calm-otter', 'abc'])
  expect(ran).toEqual(['/rename brave-otter', '/color blue'])
})

test('a script that fails leaves that part as Claude has it', async ($, on) => {
  const { ran, clock } = engine(on, { 'session-name': 'loyal-fly\n' })

  await $.classic.SessionStart(start('startup'))
  await clock.settle()
  expect(ran).toEqual(['/rename loyal-fly'])
})
