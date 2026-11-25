// One place on a tour, its path absolute.
export type Step = { path: string; line?: number; description: string }

// A tour as the agent gave it, named by the tool call that made it.
export type Tour = { id: string; title: string; steps: Step[] }

// Who draws the tour: nvim's own list, or this mod's pane in plain Claude Code.
export type Drawer = 'nvim' | 'pane'

// The session's tour: none, one being shown, or one dismissed in the pane and not yet reported.
export type TourState =
  | { kind: 'none' }
  | { kind: 'shown'; tour: Tour; drawer: Drawer }
  | { kind: 'dismissed'; title: string }

// What nvim writes of the tour it draws.
export type Report = { id: string; status: 'active' | 'dismissed'; current?: number; visited: number[] }

declare module 'claude-code' {
  interface PluginState {
    tour: { current: Shaped<TourState> }
  }
}
