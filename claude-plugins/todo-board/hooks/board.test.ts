import { expect, test } from 'claude-code/testing'

import type { Item, Priority, WaitingOn } from '../types'
import { applyUpdate, describe, parseUpdate, sections, sourceLabel } from './board'

function item(id: string, waitingOn: WaitingOn = 'you', priority: Priority = 'normal'): Item {
  return { id, title: `work ${id}`, waitingOn, note: 'why', priority, sources: [{ kind: 'ticket', ref: id }] }
}

// An item as an upsert writes it with no priority given.
function change(id: string, waitingOn: WaitingOn = 'you') {
  const { priority: _, ...rest } = item(id, waitingOn)
  return rest
}

test('a valid update parses into items, dropping fields the board does not keep', async () => {
  const parsed = parseUpdate({ upsert: [{ ...item('ABC-1', 'you', 'high'), owner: 'ross' }, change('ABC-3')], remove: ['ABC-2'] })
  expect(parsed).toEqual({ kind: 'valid', update: { upsert: [item('ABC-1', 'you', 'high'), change('ABC-3')], remove: ['ABC-2'] } })
})

test('an update with a bad item names every problem and keeps none of it', async () => {
  const parsed = parseUpdate({
    upsert: [item('ok'), { id: '', title: 'x'.repeat(81), waitingOn: 'later', note: 'n', priority: 1, sources: [{ kind: 'jira', ref: 'A' }] }],
  })
  expect(parsed.kind).toBe('invalid')
  expect(parsed.kind === 'invalid' && parsed.problems).toEqual([
    'upsert[1].id must be a non-empty string',
    'upsert[1].title must be a string of at most 80 characters',
    'upsert[1].waitingOn must be one of you, agent, others, done',
    'upsert[1].priority must be one of high, normal, low',
    'upsert[1].sources must be a list of { kind: ticket|pr|session, ref }',
  ])
})

test('an upsert that keeps an item in its section replaces it where it stands', async () => {
  const board = applyUpdate([item('a'), item('b')], { upsert: [{ ...change('a'), note: 'new' }], remove: [] })
  expect(board).toEqual([{ ...item('a'), note: 'new' }, item('b')])
})

test('an item new to a section, added or moved, joins its end', async () => {
  const board = applyUpdate([item('a'), item('b'), item('c', 'others')], { upsert: [change('a', 'others'), change('n')], remove: [] })
  expect(board.map((i) => `${i.id}:${i.waitingOn}`)).toEqual(['b:you', 'c:others', 'a:others', 'n:you'])
})

test('an upsert without a priority keeps the one the item has, and a new item is normal', async () => {
  const board = applyUpdate([item('a', 'you', 'high')], { upsert: [change('a', 'others'), change('n')], remove: [] })
  expect(board.map((i) => `${i.id}:${i.priority}`)).toEqual(['a:high', 'n:normal'])
})

test('a removed id wins over an upsert of it', async () => {
  expect(applyUpdate([item('a')], { upsert: [change('a')], remove: ['a'] })).toEqual([])
})

test('a removed id leaves the board', async () => {
  expect(applyUpdate([item('a'), item('b')], { upsert: [], remove: ['a'] })).toEqual([item('b')])
})

test('only the five most recently done items are kept', async () => {
  const done = ['d1', 'd2', 'd3', 'd4', 'd5'].map((id) => item(id, 'done'))
  const board = applyUpdate([item('open'), ...done], { upsert: [item('d6', 'done')], remove: [] })
  expect(board.map((i) => i.id)).toEqual(['open', 'd2', 'd3', 'd4', 'd5', 'd6'])
})

test('sections come in the order you, agents, others, done, empty ones left out', async () => {
  const grouped = sections([item('d', 'done'), item('y'), item('o', 'others')])
  expect(grouped.map((s) => [s.heading, s.items.map((i) => i.id)])).toEqual([
    ['You', ['y']],
    ['Others', ['o']],
    ['Done', ['d']],
  ])
})

test('each section lists high, then normal, then low, in board order within each', async () => {
  const board = [item('n1'), item('l', 'you', 'low'), item('h1', 'you', 'high'), item('n2'), item('h2', 'you', 'high')]
  expect(sections(board)[0]?.items.map((i) => i.id)).toEqual(['h1', 'h2', 'n1', 'n2', 'l'])
})

test('the board reads back with ids so Claude can update items', async () => {
  expect(describe([item('ABC-1')])).toBe('You:\n- [ABC-1, normal] work ABC-1: why (ABC-1)')
  expect(describe([])).toBe('The board is empty.')
})

test('a GitHub PR URL reads as owner/repo#number', async () => {
  expect(sourceLabel({ kind: 'pr', ref: 'https://github.com/acme/app/pull/42' })).toBe('acme/app#42')
  expect(sourceLabel({ kind: 'session', ref: 'calm-otter' })).toBe('calm-otter')
})
