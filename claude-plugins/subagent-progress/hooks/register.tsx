import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'
import type { AgentRun, Runs } from '../types'
import { readProgress, readWorkspace } from './git'
import { describeRun } from './row'

export const runs = atom({ plugin: 'subagent-progress', key: 'runs' } as const, {} as Runs, { shape: 'runs-1' })

// Git is read only after an agent's own tool calls, at most once a second each: nothing else changes its tree.
export const REFRESH_DELAY_MS = 1000
// Redraws the elapsed times; runs no git.
export const TICK_MS = 5000
// How long a finished agent's last state stays on show.
export const DONE_LINGER_MS = 5 * 60_000

export const register: Register = (on) => {
  const timers: Timers = { refreshes: new Map(), starting: new Map() }

  // A reload drops the module's timers, so the tick starts again for rows that survived it.
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await keepTicking($, timers)
    return started
  })

  on('turn.start', async ($, e, next) => {
    if (e.agentId !== undefined) await started($, timers, e.agentId)
    return next(e)
  })

  // A spawn nested in one of this mod's hooks hides its turn.start, so a first tool call starts tracking too.
  on('tool.call', async ($, e, next) => {
    if (e.agentId === undefined) return next(e)
    await seen($, timers, e.agentId)
    const result = await next(e)
    refreshSoon($, timers, e.agentId)
    return result
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) await finished($, timers, e.agentId)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const shown = Object.values(await read($, runs)).sort((a, b) => a.startedAt - b.startedAt)
    if (e.props.hasSurvey || shown.length === 0) return next(e)
    const now = await $.clock.now()
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column" width={e.props.bodyColumns}>
        {shown.map((run) => describeRun(run, now)).map(({ isDone, description, details }) => (
          <Text wrap="truncate-end" dimColor={isDone}>
            <Text color={isDone ? 'success' : 'warning'}>{isDone ? '✓ ' : '● '}</Text>
            <Text weight="bold">{description}</Text>
            {` · ${details.join(' · ')}`}
          </Text>
        ))}
      </Box>
    )
  })
}

// This module's timers and the agents it has begun tracking; a reload loses them, the runs in $.state it keeps.
type Timers = {
  refreshes: Map<string, Timer>
  starting: Map<string, Promise<void>>
  tick?: Timer
}

function seen($: EngineInterface, timers: Timers, agentId: string): Promise<void> {
  const pending = timers.starting.get(agentId) ?? begin($, timers, agentId)
  timers.starting.set(agentId, pending)
  return pending
}

// A message that resumes a finished agent starts a new turn of it.
async function started($: EngineInterface, timers: Timers, agentId: string) {
  await seen($, timers, agentId)
  await setRun($, agentId, (run) => ({ ...run, phase: { kind: 'running' } }))
}

async function finished($: EngineInterface, timers: Timers, agentId: string) {
  const at = await $.clock.now()
  await setRun($, agentId, (run) => ({ ...run, phase: { kind: 'done', at } }))
  timers.refreshes.get(agentId)?.cancel()
  timers.refreshes.delete(agentId)
  await refresh($, agentId)
}

function refreshSoon($: EngineInterface, timers: Timers, agentId: string) {
  if (timers.refreshes.has(agentId)) return
  const timer = $.clock.after(REFRESH_DELAY_MS, () => {
    timers.refreshes.delete(agentId)
    void refresh($, agentId)
  })
  timers.refreshes.set(agentId, timer)
}

async function keepTicking($: EngineInterface, timers: Timers) {
  if (timers.tick !== undefined || Object.keys(await read($, runs)).length === 0) return
  timers.tick = $.clock.every(TICK_MS, () => void onTick($, timers))
}

// Inside the agent's own hook $.session.cwd() is the agent's directory, its worktree when isolated.
async function begin($: EngineInterface, timers: Timers, agentId: string) {
  if ((await read($, runs))[agentId] !== undefined) return
  const [cwd, startedAt, agents] = await Promise.all([$.session.cwd(), $.clock.now(), $.agent.list()])
  const run: AgentRun = {
    description: agents.find((agent) => agent.id === agentId)?.description ?? agentId,
    startedAt,
    phase: { kind: 'running' },
    workspace: await readWorkspace($, cwd),
  }
  await update($, runs, (all) => ({ ...all, [agentId]: all[agentId] ?? run }))
  refreshSoon($, timers, agentId)
  await keepTicking($, timers)
}

async function refresh($: EngineInterface, agentId: string) {
  const workspace = (await read($, runs))[agentId]?.workspace
  if (workspace?.kind !== 'repo') return
  const progress = await readProgress($, workspace)
  if (progress === undefined) return
  await setRun($, agentId, (run) => (run.workspace.kind === 'repo' ? { ...run, workspace: { ...run.workspace, progress } } : run))
}

async function onTick($: EngineInterface, timers: Timers) {
  const now = await $.clock.now()
  const lingering = (run: AgentRun) => run.phase.kind === 'running' || now - run.phase.at < DONE_LINGER_MS
  const kept = await update($, runs, (all) => Object.fromEntries(Object.entries(all).filter(([, run]) => lingering(run))))
  for (const id of timers.starting.keys()) if (!(id in kept)) timers.starting.delete(id)
  if (Object.keys(kept).length > 0) return $.ui.invalidate('ui.render')
  timers.tick?.cancel()
  timers.tick = undefined
}

// Changes one run, leaving the rest and any run already pruned alone.
function setRun($: EngineInterface, agentId: string, change: (run: AgentRun) => AgentRun) {
  return update($, runs, (all) => {
    const run = all[agentId]
    return run === undefined ? all : { ...all, [agentId]: change(run) }
  })
}
