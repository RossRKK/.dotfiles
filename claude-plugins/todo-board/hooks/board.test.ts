import { expect, test } from 'claude-code/testing'

import type { Item, WaitingOn } from '../types'
import { applyUpdate, describe, parseUpdate, sections, sourceLabel } from './board'

function item(id: string, waitingOn: WaitingOn = 'you'): Item {
  return { id, title: `work ${id}`, waitingOn, note: 'why', sources: [{ kind: 'ticket', ref: id }] }
}

test('a valid update parses into items, dropping fields the board does not keep', async () => {
  const parsed = parseUpdate({ upsert: [{ ...item('ABC-1'), priority: 3 }], remove: ['ABC-2'] })
  expect(parsed).toEqual({ kind: 'valid', update: { upsert: [item('ABC-1')], remove: ['ABC-2'] } })
})

test('an update with a bad item names every problem and keeps none of it', async () => {
  const parsed = parseUpdate({
    upsert: [item('ok'), { id: '', title: 'x'.repeat(81), waitingOn: 'later', note: 'n', sources: [{ kind: 'jira', ref: 'A' }] }],
  })
  expect(parsed.kind).toBe('invalid')
  expect(parsed.kind === 'invalid' && parsed.problems).toEqual([
    'upsert[1].id must be a non-empty string',
    'upsert[1].title must be a string of at most 80 characters',
    'upsert[1].waitingOn must be one of you, agent, others, done',
    'upsert[1].sources must be a list of { kind: ticket|pr|session, ref }',
  ])
})

test('an upsert replaces the item with its id and moves it to the end', async () => {
  const board = applyUpdate([item('a'), item('b')], { upsert: [item('a', 'others')], remove: [] })
  expect(board).toEqual([item('b'), item('a', 'others')])
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

test('the board reads back with ids so Claude can update items', async () => {
  expect(describe([item('ABC-1')])).toBe('You:\n- [ABC-1] work ABC-1: why (ABC-1)')
  expect(describe([])).toBe('The board is empty.')
})

test('a GitHub PR URL reads as owner/repo#number', async () => {
  expect(sourceLabel({ kind: 'pr', ref: 'https://github.com/acme/app/pull/42' })).toBe('acme/app#42')
  expect(sourceLabel({ kind: 'session', ref: 'calm-otter' })).toBe('calm-otter')
})
