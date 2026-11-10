import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Item } from '../types'
import { applyUpdate, describe, parseUpdate, sections, sourceLabel, UPDATE_SCHEMA } from './board'

const PANE = { id: 'todo-board', title: 'Board' } as const
const LIST_TOOL = 'mcp__todo-board__list'
const UPDATE_TOOL = 'mcp__todo-board__update'
// Change the tag when Item changes: it declines what an earlier version stored.
const items = atom({ plugin: 'todo-board', key: 'items' } as const, [], { shape: 'items-2' })

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({
      name: 'board',
      description: "Show this checkout's board of what is waiting on whom; `/board close` hides it",
    })
    await $.tool.register({
      name: 'list',
      description: "Reads this checkout's board: what is waiting on the user, on agents, on others, and recently done, each with its id.",
    })
    await $.tool.register({
      name: 'update',
      description:
        "Adds, replaces (by id) or removes items on this checkout's board, which the user sees in a short pane. One item per piece of work: link its ticket, PR and session as sources. Set priority high on what the user should see first; an upsert without priority keeps the item's priority and place.",
      inputSchema: UPDATE_SCHEMA,
    })
    const stored = await load($)
    await update($, items, () => stored)
    if (stored.length > 0) void $.ui.open(PANE)
    return started
  })

  on('command.run', { command: 'board' }, async ($, e) => {
    switch (e.args.trim()) {
      case '':
        await $.ui.open(PANE)
        return { text: 'Board opened.' }
      case 'close':
        await $.ui.close({ id: PANE.id })
        return { text: 'Board closed.' }
      default:
        return { text: 'Usage: /board [close]' }
    }
  })

  on('tool.call', { tool: LIST_TOOL }, async ($) => ({ result: describe(await read($, items)) }))

  on('tool.call', { tool: UPDATE_TOOL }, async ($, e) => {
    const parsed = parseUpdate(e)
    if (parsed.kind === 'invalid') return { deny: `The board was not changed: ${parsed.problems.join('; ')}` }
    // The stored board, not this session's copy: another session in the checkout may have written since.
    const before = await load($)
    const changed = applyUpdate(before, parsed.update)
    await save($, changed)
    await update($, items, () => changed)
    // Only a board that was empty pops up, so one the user closed stays closed.
    if (before.length === 0 && changed.length > 0) void $.ui.open(PANE)
    return { result: describe(changed) }
  })

  on('ui.render', { component: 'Pane', requestId: PANE.id }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const board = sections(await read($, items))
    return (
      <Box flexDirection="column">
        {board.length === 0 && <Text dimColor>Nothing on the board.</Text>}
        {board.map(({ waitingOn, heading, items }) => (
          <Box flexDirection="column" marginBottom={1}>
            <Text bold dimColor={waitingOn === 'done'}>
              {heading} ({items.length})
            </Text>
            {items.map((item) => (
              <Box flexDirection="column">
                <Text dimColor={waitingOn === 'done'}>
                  {item.title} <Text dimColor>{item.note}</Text>
                </Text>
                <Text dimColor>  {item.sources.map(sourceLabel).join(' · ')}</Text>
              </Box>
            ))}
          </Box>
        ))}
      </Box>
    )
  })
}

// One board per checkout: big-cheese's survives /clear and restarts, a worktree's is its own.
// A board stored before priorities reads as all normal; one in another shape starts over empty.
async function load($: EngineInterface): Promise<Item[]> {
  const parsed = parseUpdate({ upsert: (await $.store.get(await storeKey($))) ?? [] })
  return parsed.kind === 'valid' ? applyUpdate([], parsed.update) : []
}

async function save($: EngineInterface, board: Item[]) {
  await $.store.set(await storeKey($), board)
}

async function storeKey($: EngineInterface): Promise<string> {
  return `board:${await $.session.cwd()}`
}
