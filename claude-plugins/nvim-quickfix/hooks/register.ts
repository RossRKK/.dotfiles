import { atom, read, update, type EngineInterface, type Register } from 'claude-code'
import type { QuickfixState } from '../types'

const shownList = atom({ plugin: 'nvim-quickfix', key: 'shownList' } as const, null)

// A grep can fill thousands of entries; past this many the context names how many more there are.
export const MAX_ENTRIES = 50
// The prompt waits on this, so a busy nvim costs it no more than a moment.
const STATE_TIMEOUT_MS = 2000

export const register: Register = (on) => {
  on('prompt.submit', async ($, e, next) => {
    if (e.command) return next(e)
    const server = await $.env.get('NVIM')
    const state = server ? await quickfixState($, server) : undefined
    if (!state) return next(e)
    const signature = `${state.id}:${state.changedtick}`
    const isUnchanged = (await read($, shownList)) === signature
    await update($, shownList, () => signature)
    return next({ ...e, context: [...(e.context ?? []), describe(state, isUnchanged)] })
  })
}

/** The quickfix list as I see it: where I am, and its entries unless the last prompt already listed them. */
export function describe(state: QuickfixState, isUnchanged: boolean): string {
  const visited = state.visited.length ? `visited ${ranges(state.visited)}` : 'none visited yet'
  const position = `on entry ${state.current} of ${state.entries.length}, ${visited}`
  if (isUnchanged) return `nvim quickfix list "${state.title}", entries as last listed: ${position}.`
  const shown = state.entries.slice(0, MAX_ENTRIES).map((entry, i) => `${i + 1}. ${entry.path}:${entry.line}: ${entry.text}`)
  const hidden = state.entries.length - shown.length
  return [`nvim quickfix list "${state.title}": ${position}.`, ...shown, ...(hidden > 0 ? [`… and ${hidden} more`] : [])].join('\n')
}

/** Ascending indices as runs: [1, 2, 3, 5] reads "1-3, 5". */
function ranges(indices: readonly number[]): string {
  const runs: [number, number][] = []
  for (const index of indices) {
    const last = runs.at(-1)
    if (last && index === last[1] + 1) last[1] = index
    else runs.push([index, index])
  }
  return runs.map(([from, to]) => (from === to ? `${from}` : `${from}-${to}`)).join(', ')
}

/** `nvim-qf state` from the nvim at `server`, or undefined when its list is empty or it cannot say. */
async function quickfixState($: EngineInterface, server: string): Promise<QuickfixState | undefined> {
  try {
    const { exitCode, stdout } = await $.process.run(['nvim-qf', 'state'], { env: { NVIM: server }, timeoutMs: STATE_TIMEOUT_MS })
    return exitCode === 0 ? parseState(JSON.parse(stdout)) : undefined
  } catch {
    return undefined
  }
}

function parseState(value: unknown): QuickfixState | undefined {
  if (typeof value !== 'object' || value === null) return undefined
  const state = value as Partial<QuickfixState>
  const isState =
    typeof state.id === 'number' &&
    typeof state.title === 'string' &&
    typeof state.current === 'number' &&
    typeof state.changedtick === 'number' &&
    Array.isArray(state.visited) &&
    Array.isArray(state.entries)
  return isState ? (state as QuickfixState) : undefined
}
