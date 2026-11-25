import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import type { Report } from '../types'
import { END, PANE, SHOW } from './register'

const CWD = '/repo'
const SESSION = 'session-a'
const REPORT = `/state/claude-tour/${SESSION}.json`
const FILES = new Set(['/repo/src/auth.rs', '/repo/src/main.rs'])

const STEPS = [
  { file: 'src/auth.rs', line: 10, description: 'The check' },
  { file: '/repo/src/main.rs', description: 'Where it is wired' },
]

// Stands for the engine: a session in /repo, nvim at `server` (none when undefined) answering `nvimSays`, files on disk in `files`.
function engine(on: On, server: string | undefined, files: Map<string, string> = new Map(), nvimSays = '') {
  const ran: string[][] = []
  const opened: string[] = []
  on('env.get', (_, e) => ({ value: { NVIM: server, XDG_STATE_HOME: '/state', HOME: '/home/me' }[e.name] }))
  on('session.id', () => ({ value: SESSION }))
  on('session.cwd', () => ({ value: CWD }))
  on('clock.now', () => ({ value: 1 }))
  on('tool.register', (_, e) => ({ value: { tool: e.name } }))
  on('ui.open', (_, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', () => ({ value: undefined }))
  on('fs.stat', (_, e) => {
    if (!FILES.has(e.path)) throw new Error('ENOENT')
    return { value: { kind: 'file', size: 1, mtimeMs: 0, isLink: false } }
  })
  on('fs.read', (_, e) => {
    const text = files.get(e.path)
    if (text === undefined) throw new Error('ENOENT')
    return { value: text }
  })
  on('process.run', (_, e) => {
    ran.push([...e.argv])
    if (e.argv[0] === 'rm') files.delete(e.argv[2] ?? '')
    return { value: { exitCode: 0, stdout: e.argv[0] === 'nvim' ? nvimSays : '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('prompt.submit', (_, e) => ({ text: e.text, context: e.context }))
  return { ran, opened, files }
}

const typed = (text: string) => ({ text, wait: false, origin: { kind: 'composer' as const } })
const showTour = { tool: SHOW, tool_use_id: 'toolu_1', title: 'Auth flow', steps: STEPS } as const
const report = (r: Report) => JSON.stringify(r)

test('a tour inside nvim goes to fishmonger with its session, absolute paths and report file', async ($, on) => {
  const { ran } = engine(on, '/run/nvim.sock')

  const answer = await $.tool.call(showTour)

  expect(answer.deny).toBeUndefined()
  expect(ran).toHaveLength(1)
  const [argv] = ran
  expect(argv?.slice(0, 4)).toEqual(['nvim', '--server', '/run/nvim.sock', '--remote-expr'])
  const payload = JSON.parse(argv?.[4]?.match(/json_decode\('(.*)'\)\)$/)?.[1]?.replaceAll("''", "'") ?? 'null')
  expect(argv?.[4]).toContain('require("fishmonger.tour").show(_A)')
  expect(payload).toEqual({
    id: 'toolu_1',
    title: 'Auth flow',
    steps: [
      { path: '/repo/src/auth.rs', line: 10, description: 'The check' },
      { path: '/repo/src/main.rs', description: 'Where it is wired' },
    ],
    session: SESSION,
    report: REPORT,
  })
})

test('a subagent is told to hand its tour to its parent', async ($, on) => {
  const { ran } = engine(on, '/run/nvim.sock')

  const answer = await $.tool.call({ ...showTour, agentId: 'agent-1' })

  expect(answer.deny).toContain('hand these steps to your parent')
  expect(ran).toEqual([])
})

test('a step on a missing file refuses the tour, naming the file', async ($, on) => {
  const { ran } = engine(on, '/run/nvim.sock')

  const answer = await $.tool.call({ ...showTour, steps: [...STEPS, { file: 'gone.rs', description: 'x' }] })

  expect(answer.deny).toBe('No such file: /repo/gone.rs')
  expect(ran).toEqual([])
})

test('nvim refusing the tour is the agent refused', async ($, on) => {
  engine(on, '/run/nvim.sock', new Map(), 'no agent terminal for this session\n')

  const answer = await $.tool.call(showTour)

  expect(answer.deny).toBe('nvim could not show the tour: no agent terminal for this session')
})

test('a prompt says where I am on the tour, from nvim\'s report', async ($, on) => {
  const { files } = engine(on, '/run/nvim.sock')
  await $.tool.call(showTour)
  files.set(REPORT, report({ id: 'toolu_1', status: 'active', current: 2, visited: [2, 1] }))

  const { context } = await $.prompt.submit(typed('next?'))

  expect(context).toEqual(['tour "Auth flow": on step 2 of 2, visited 1-2.'])
})

test('a report of an earlier tour is not read as this one', async ($, on) => {
  const { files } = engine(on, '/run/nvim.sock')
  await $.tool.call(showTour)
  files.set(REPORT, report({ id: 'toolu_0', status: 'dismissed', current: 1, visited: [1] }))

  const { context } = await $.prompt.submit(typed('next?'))

  expect(context).toEqual(['tour "Auth flow": no step opened yet, 2 steps.'])
})

test('a tour dismissed in nvim is reported once, then forgotten', async ($, on) => {
  const { files, ran } = engine(on, '/run/nvim.sock')
  await $.tool.call(showTour)
  files.set(REPORT, report({ id: 'toolu_1', status: 'dismissed', current: 1, visited: [1] }))

  const first = await $.prompt.submit(typed('done'))
  const second = await $.prompt.submit(typed('and?'))

  expect(first.context).toEqual(['The user dismissed tour "Auth flow".'])
  expect(second.context).toBeUndefined()
  expect(ran.at(-1)).toEqual(['rm', '-f', REPORT])
})

test('ending a tour finishes it in nvim and deletes its report', async ($, on) => {
  const { files, ran } = engine(on, '/run/nvim.sock')
  await $.tool.call(showTour)
  files.set(REPORT, report({ id: 'toolu_1', status: 'active', current: 1, visited: [1] }))

  const answer = await $.tool.call({ tool: END })

  expect(answer.deny).toBeUndefined()
  expect(ran[1]?.[4]).toBe(`luaeval('require("fishmonger.tour").finish(_A) or ""', json_decode('{"session":"${SESSION}"}'))`)
  expect(ran[2]).toEqual(['rm', '-f', REPORT])
  expect(files.has(REPORT)).toBe(false)
  expect((await $.prompt.submit(typed('next'))).context).toBeUndefined()
})

const PANE_RENDER = {
  plugin: 'tour',
  component: 'Pane',
  requestId: PANE,
  props: { title: 'Auth flow', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

test('outside nvim the tour is a pane, and dismissing it is reported once', async ($, on) => {
  const { opened, ran } = engine(on, undefined)

  await $.tool.call(showTour)
  expect(opened).toEqual([PANE])
  expect(ran).toEqual([])

  const ui = await $.ui.mount({ ...PANE_RENDER, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /auth\.rs/ }))?.text).toBe('1. src/auth.rs:10 — The check')
  expect((await ui.find({ type: 'Text', text: /main\.rs/ }))?.text).toBe('2. src/main.rs — Where it is wired')
  await ui.press({ key: 'dismiss' })
  await ui.unmount()

  expect((await $.prompt.submit(typed('ok'))).context).toEqual(['The user dismissed tour "Auth flow".'])
  expect((await $.prompt.submit(typed('ok'))).context).toBeUndefined()
})
