// The quickfix list as `nvim-qf state` reports it.
export type QuickfixState = {
  id: number
  title: string
  current: number
  visited: number[]
  changedtick: number
  entries: QuickfixEntry[]
}

export type QuickfixEntry = { path: string; line: number; text: string }

declare module 'claude-code' {
  interface PluginState {
    // The list last given in full, as `<id>:<changedtick>`.
    'nvim-quickfix': { shownList: string | null }
  }
}
