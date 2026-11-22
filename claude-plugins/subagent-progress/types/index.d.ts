// One subagent's run as the band shows it, keyed by its agent id.
export type Runs = Record<string, AgentRun>

export type AgentRun = {
  description: string
  startedAt: number
  phase: Phase
  workspace: Workspace
}

export type Phase = { kind: 'running' } | { kind: 'done'; at: number }

// Where the agent works, read once as it starts; `base` is HEAD then, which its commits are counted from.
export type Workspace =
  | { kind: 'repo'; cwd: string; repo: string; base: string; progress?: GitProgress }
  | { kind: 'outside-repo'; cwd: string }

export type RepoWorkspace = Extract<Workspace, { kind: 'repo' }>

export type GitProgress = {
  branch: Branch
  ahead: number
  latest?: Commit
  changedFiles: number
}

export type Branch = { kind: 'named'; name: string } | { kind: 'detached' }

export type Commit = { subject: string; committedAt: number }

declare module 'claude-code' {
  interface PluginState {
    'subagent-progress': { runs: Shaped<Runs> }
  }
}
