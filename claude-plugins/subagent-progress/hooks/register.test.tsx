import type { On } from 'claude-code'
import { expect, mock, test, type Engine } from 'claude-code/testing'
import { DONE_LINGER_MS, REFRESH_DELAY_MS, TICK_MS } from './register'

const T0 = 1_700_000_000_000
const WORKTREE = '/src/dotfiles/.claude/worktrees/agent-a1'

// A repository as git would answer for it; tests change it to stand for an agent's commits and edits.
type Repo = { branch: string; ahead: number; latest?: { subject: string; at: number }; changed: string[] }

// Stands for the engine: subagent a1 runs in <cwd>, git there answers from <repo>, and every git call is recorded.
function engine(on: On, repo: Repo | undefined, cwd = WORKTREE) {
  const git: { argv: readonly string[]; cwd?: string }[] = []
  on('session.cwd', () => ({ value: cwd }))
  on('agent.list', () => ({ value: [{ id: 'a1', description: 'fix the parser', type: 'general-purpose', status: 'running' }] }))
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('tool.call', () => ({ result: {} }))
  on('process.run', (_, e) => {
    git.push({ argv: e.argv, cwd: e.init?.cwd })
    const stdout = repo === undefined ? undefined : answer(repo, e.argv.slice(1))
    return { value: { exitCode: stdout === undefined ? 128 : 0, stdout: stdout ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  return { git, clock: mock.clock(on, { now: T0 }) }
}

function answer(repo: Repo, args: readonly string[]): string | undefined {
  const [first, second] = args
  if (first === 'rev-parse') return '/src/dotfiles/.git\nbase0000\n'
  if (second === 'status') return [`# branch.oid head1111`, `# branch.head ${repo.branch}`, ...repo.changed.map((path) => `1 .M N... 100644 100644 100644 a b ${path}`)].join('\n') + '\n'
  if (first === 'rev-list') return `${repo.ahead}\n`
  if (first === 'log') return repo.latest ? `${repo.latest.at / 1000}\0${repo.latest.subject}\n` : ''
  return undefined
}

const BAND = {
  plugin: 'subagent-progress',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 200, scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

const SURFACES = ['terminal', 'desktop'] as const

const turn = (agentId?: string) => ({ text: '', turnId: 't1', ...(agentId ? { agentId } : {}) })
const done = (agentId: string) => ({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't1', agentId, reason: 'answer' as const })

async function rows($: Engine, surface: (typeof SURFACES)[number]) {
  const ui = await $.ui.mount({ ...BAND, surface })
  const found = (await ui.findAll({ type: 'Text', text: /·/ })).map((row) => row.text)
  await ui.unmount()
  return found
}

test("a running agent's row shows its branch, commits since it started, uncommitted files and elapsed time", async ($, on) => {
  const repo: Repo = { branch: 'rkk/parser', ahead: 0, changed: [] }
  const { clock } = engine(on, repo)

  await $.turn.start(turn('a1'))
  Object.assign(repo, { ahead: 2, latest: { subject: 'parse nested lists', at: T0 + 10_000 }, changed: ['a.ts', 'b.ts', 'c.ts'] })
  await clock.advance(30_000)
  await $.tool.call({ tool: 'Bash', command: 'git commit -m x', agentId: 'a1' })
  await clock.advance(REFRESH_DELAY_MS)

  for (const surface of SURFACES) {
    expect(await rows($, surface)).toEqual(['● fix the parser · dotfiles:rkk/parser · +2 parse nested lists (21s ago) · 3 uncommitted · 31s'])
  }
})

test('commits are counted from the HEAD the agent started on, in its own worktree, without taking the index lock', async ($, on) => {
  const { git, clock } = engine(on, { branch: 'rkk/parser', ahead: 0, changed: [] })

  await $.turn.start(turn('a1'))
  await clock.advance(REFRESH_DELAY_MS)

  expect(git.every((call) => call.cwd === WORKTREE)).toBe(true)
  expect(git.map((call) => call.argv.slice(1))).toEqual(
    expect.arrayContaining([
      ['rev-list', '--count', 'base0000..HEAD'],
      ['--no-optional-locks', 'status', '--porcelain=v2', '--branch'],
    ]),
  )
})

test('a burst of tool calls reads git once', async ($, on) => {
  const { git, clock } = engine(on, { branch: 'main', ahead: 0, changed: [] })

  await $.turn.start(turn('a1'))
  await clock.advance(REFRESH_DELAY_MS)
  const before = git.length
  for (let i = 0; i < 5; i++) await $.tool.call({ tool: 'Read', file_path: '/x', agentId: 'a1' })
  await clock.advance(REFRESH_DELAY_MS)

  expect(git.length - before).toBe(3)
})

test("the main loop's turns and tool calls run no git and leave the band to the engine", async ($, on) => {
  const { git, clock } = engine(on, { branch: 'main', ahead: 0, changed: [] })

  await $.turn.start(turn())
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await clock.advance(REFRESH_DELAY_MS)

  expect(git).toEqual([])
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
    await ui.unmount()
  }
})

test('a finished agent is marked done with its time frozen, then leaves the band', async ($, on) => {
  const { clock } = engine(on, { branch: 'rkk/parser', ahead: 0, changed: [] })

  await $.turn.start(turn('a1'))
  await clock.advance(60_000)
  await $.turn.complete(done('a1'))
  await clock.advance(10 * TICK_MS)

  expect(await rows($, 'terminal')).toEqual(['✓ fix the parser · dotfiles:rkk/parser · no commits · clean · 1m'])
  await clock.advance(DONE_LINGER_MS)
  expect(await rows($, 'terminal')).toEqual([])
})

test('an agent working outside any repository shows where it is', async ($, on) => {
  const { clock } = engine(on, undefined, '/tmp/scratch')

  await $.turn.start(turn('a1'))
  await clock.advance(REFRESH_DELAY_MS)

  expect(await rows($, 'terminal')).toEqual(['● fix the parser · /tmp/scratch · 1s'])
})

test('an agent first seen by its tool call is tracked from then', async ($, on) => {
  const { clock } = engine(on, { branch: 'rkk/parser', ahead: 0, changed: ['a.ts'] })

  await $.tool.call({ tool: 'Edit', file_path: '/x', old_string: 'a', new_string: 'b', agentId: 'a1' })
  await clock.advance(REFRESH_DELAY_MS)

  expect(await rows($, 'terminal')).toEqual(['● fix the parser · dotfiles:rkk/parser · no commits · 1 uncommitted · 1s'])
})
