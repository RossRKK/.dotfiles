import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import type { Item } from '../types'

const START = { cwd: '/work', surface: 'terminal', isInteractive: true } as const
const PANE = {
  plugin: 'todo-board',
  component: 'Pane',
  requestId: 'todo-board',
  surface: 'terminal',
  props: { title: 'Board', isFocused: false, bodyColumns: 40, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const
const REVIEW: Item = {
  id: 'ABC-1',
  title: 'Review the cache PR',
  waitingOn: 'you',
  note: 'review requested',
  sources: [{ kind: 'pr', ref: 'https://github.com/acme/app/pull/7' }],
}

// Stands for the engine: a store holding <stored>, a session in /work, and a
// record of each pane the mod opens.
function engine(on: On, stored: Record<string, unknown> = {}) {
  const store = { ...stored }
  const opened: string[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work' }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__todo-board__${e.name}` } }))
  on('ui.open', (_, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('store.get', (_, e) => ({ value: store[e.key] }))
  on('store.set', (_, e) => {
    store[e.key] = e.value
    return { value: undefined }
  })
  return { store, opened }
}

test("a session starts on its checkout's stored board and shows it", async ($, on) => {
  const { opened } = engine(on, { 'board:/work': [REVIEW] })
  await $.session.start(START)

  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /You/ }))?.text).toBe('You (1)')
  expect(await ui.find({ type: 'Text', text: /acme\/app#7/ })).toBeDefined()
  expect(opened).toEqual(['todo-board'])
  await ui.unmount()
})

test('a session with an empty board leaves the pane closed', async ($, on) => {
  const { opened } = engine(on)
  await $.session.start(START)
  expect(opened).toEqual([])
})

test('an update is stored for the checkout, opens the pane and redraws it', async ($, on) => {
  const { store, opened } = engine(on)
  await $.session.start(START)
  const ui = await $.ui.mount(PANE)

  const ran = await $.tool.call({ tool: 'mcp__todo-board__update', upsert: [REVIEW] })
  expect(ran.text ?? ran.result).toBe('You:\n- [ABC-1] Review the cache PR: review requested (acme/app#7)')
  expect(store['board:/work']).toEqual([REVIEW])
  expect(opened).toEqual(['todo-board'])
  expect((await ui.find({ type: 'Text', text: /Review the cache PR/ }))?.text).toContain('review requested')
  await ui.unmount()
})

test('an invalid update is refused and changes nothing', async ($, on) => {
  const { store } = engine(on, { 'board:/work': [REVIEW] })
  await $.session.start(START)

  const ran = await $.tool.call({ tool: 'mcp__todo-board__update', upsert: [{ ...REVIEW, waitingOn: 'someday' }] })
  expect(ran.deny ?? ran.text).toContain('waitingOn must be one of')
  expect(store['board:/work']).toEqual([REVIEW])
})

test('list reads the board back', async ($, on) => {
  engine(on, { 'board:/work': [REVIEW] })
  await $.session.start(START)

  const ran = await $.tool.call({ tool: 'mcp__todo-board__list' })
  expect(ran.text ?? ran.result).toContain('[ABC-1]')
})

test('a board stored in another shape starts over empty', async ($, on) => {
  engine(on, { 'board:/work': [{ id: 'old', status: 'open' }] })
  await $.session.start(START)

  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text' }))?.text).toBe('Nothing on the board.')
  await ui.unmount()
})
