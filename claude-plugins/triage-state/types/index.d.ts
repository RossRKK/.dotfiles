// A file's place in the review, as triage.nvim names it.
export type TriageStatus = 'changed' | 'approved' | 'rejected' | 'revised' | 'stale'

// The repo's active review, as `require("triage").review(dir)` gives it.
export type Review = {
  root: string
  base: string
  label?: string
  files: { rel: string; status: TriageStatus }[]
}

declare module 'claude-code' {
  interface PluginState {
    // The review as last told to Claude, JSON-encoded; null when none was, or review mode went off since.
    'triage-state': { told: string | null }
  }
}
