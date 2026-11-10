// Who has to act next for an item to move.
export type WaitingOn = 'you' | 'agent' | 'others' | 'done'

export type SourceKind = 'ticket' | 'pr' | 'session'

// Where an item comes from: a ticket key, a PR URL or a session name.
export type Source = { kind: SourceKind; ref: string }

export type Item = {
  // Stable across updates, so the same work is replaced, not duplicated.
  id: string
  title: string
  waitingOn: WaitingOn
  // Why it waits there, in a few words.
  note: string
  sources: Source[]
}

declare module 'claude-code' {
  interface PluginState {
    'todo-board': { items: Shaped<Item[]> }
  }
  // Loose on purpose: the update hook parses what the model sent.
  interface McpToolInputs {
    'mcp__todo-board__list': {}
    'mcp__todo-board__update': { upsert?: unknown; remove?: unknown }
  }
}
