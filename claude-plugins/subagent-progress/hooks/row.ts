import type { AgentRun, GitProgress, Workspace } from '../types'

// The words of one band row: what the agent is doing, then its details in the order shown.
export type Row = {
  isDone: boolean
  description: string
  details: string[]
}

export function describeRun(run: AgentRun, now: number): Row {
  const endedAt = run.phase.kind === 'done' ? run.phase.at : now
  const progress = run.workspace.kind === 'repo' ? run.workspace.progress : undefined
  return {
    isDone: run.phase.kind === 'done',
    description: run.description,
    details: [
      where(run.workspace),
      ...(progress ? [commits(progress, now), changes(progress)] : []),
      formatDuration(endedAt - run.startedAt),
    ],
  }
}

// 42s, 12m, 1h05m: coarse enough that a redraw every few seconds keeps it right.
export function formatDuration(ms: number): string {
  const seconds = Math.max(0, Math.floor(ms / 1000))
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m`
  return `${Math.floor(minutes / 60)}h${String(minutes % 60).padStart(2, '0')}m`
}

function where(workspace: Workspace): string {
  if (workspace.kind === 'outside-repo') return workspace.cwd
  const branch = workspace.progress?.branch
  const name = branch === undefined ? '…' : branch.kind === 'named' ? branch.name : 'detached'
  return `${workspace.repo}:${name}`
}

function commits({ ahead, latest }: GitProgress, now: number): string {
  if (latest === undefined) return 'no commits'
  return `+${ahead} ${latest.subject} (${formatDuration(now - latest.committedAt)} ago)`
}

function changes({ changedFiles }: GitProgress): string {
  return changedFiles === 0 ? 'clean' : `${changedFiles} uncommitted`
}
