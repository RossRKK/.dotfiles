import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, ToolCallInput } from 'claude-code'
import type { Report, Step, Tour, TourState } from '../types'

export const current = atom({ plugin: 'tour', key: 'current' } as const, { kind: 'none' } as TourState, { shape: 'tour-1' })

export const PANE = 'tour'
export const SHOW = 'mcp__tour__show'
export const END = 'mcp__tour__end'

const SHOW_DESCRIPTION = [
  'Lead the user through several places in the code, in order: a walkthrough of a change, or everywhere something happens.',
  'Each step is a file, an optional 1-based line and a markdown note on what to see there. The first step opens at once and the',
  'user steps through the rest; each prompt then says which step they are on. A new tour replaces the current one. For a single',
  'place, open it with nvim-open instead.',
].join(' ')

const END_DESCRIPTION = 'End the current tour once its walkthrough is done, closing its list.'

const SHOW_SCHEMA = {
  type: 'object',
  properties: {
    title: { type: 'string', description: 'What the tour is of' },
    steps: {
      type: 'array',
      minItems: 1,
      items: {
        type: 'object',
        properties: {
          file: { type: 'string', description: 'Relative to the working directory, or absolute' },
          line: { type: 'integer', minimum: 1 },
          description: { type: 'string', description: 'Markdown: what to see here' },
        },
        required: ['file', 'description'],
      },
    },
  },
  required: ['title', 'steps'],
}

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.tool.register({ name: 'show', description: SHOW_DESCRIPTION, inputSchema: SHOW_SCHEMA, isDeferred: false })
    await $.tool.register({ name: 'end', description: END_DESCRIPTION, inputSchema: { type: 'object' }, isDeferred: false })
    return started
  })

  on('tool.call', { tool: SHOW }, ($, e) => show($, e).catch((err) => ({ deny: `The tour failed: ${String(err)}` })))

  on('tool.call', { tool: END }, ($, e) => end($, e).catch((err) => ({ deny: `Ending the tour failed: ${String(err)}` })))

  on('prompt.submit', async ($, e, next) => {
    if (e.command) return next(e)
    // A tour must never stop a prompt from going.
    const line = await progress($).catch(() => undefined)
    return line ? next({ ...e, context: [...(e.context ?? []), line] }) : next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const state = await read($, current)
    if (state.kind !== 'shown') return <Text dimColor>No tour.</Text>
    const cwd = await $.session.cwd()
    return (
      <Box flexDirection="column">
        {state.tour.steps.map((step, i) => (
          <Text>
            {i + 1}. {stepLabel(step, cwd)} — {step.description}
          </Text>
        ))}
        <Button key="dismiss" role="dismiss" label="Dismiss" onPress={() => dismissPane($, state.tour.title)} />
      </Box>
    )
  })
}

type ToolAnswer = { result: string } | { deny: string }

/** Show the tour a show call asks for, in nvim when inside one, else in the pane. */
async function show($: EngineInterface, e: ToolCallInput): Promise<ToolAnswer> {
  // A subagent's tour would be drawn for nobody: its parent is the one the user talks to.
  if (e.agentId !== undefined) return { deny: 'Only the main agent can show a tour: hand these steps to your parent instead.' }
  const asked = parseShow(e)
  if (typeof asked === 'string') return { deny: asked }
  const steps = await resolveSteps($, asked.steps)
  if (typeof steps === 'string') return { deny: steps }
  const tour: Tour = { id: e.tool_use_id ?? `${await $.clock.now()}`, title: asked.title, steps }
  const server = await $.env.get('NVIM')
  if (server) {
    const refusal = await callNvim($, server, 'show', { ...tour, session: await $.session.id(), report: await reportPath($) })
    if (refusal) return { deny: `nvim could not show the tour: ${refusal}` }
    await setTour($, { kind: 'shown', tour, drawer: 'nvim' })
  } else {
    await setTour($, { kind: 'shown', tour, drawer: 'pane' })
    await $.ui.open({ id: PANE, title: tour.title })
  }
  return { result: `Showing tour "${tour.title}", ${steps.length} steps; step 1 is open.` }
}

/** End the session's tour wherever it is drawn. */
async function end($: EngineInterface, e: ToolCallInput): Promise<ToolAnswer> {
  if (e.agentId !== undefined) return { deny: 'Only the main agent has a tour to end.' }
  const state = await read($, current)
  await setTour($, { kind: 'none' })
  if (state.kind !== 'shown') return { result: 'No tour was showing.' }
  if (state.drawer === 'nvim') {
    const server = await $.env.get('NVIM')
    if (server) await callNvim($, server, 'finish', { session: await $.session.id() })
    await $.process.run(['rm', '-f', await reportPath($)])
  } else {
    await $.ui.close({ id: PANE })
  }
  return { result: `Ended tour "${state.tour.title}".` }
}

/** The line a prompt carries about the tour, or undefined when there is nothing to say. */
async function progress($: EngineInterface): Promise<string | undefined> {
  const state = await read($, current)
  if (state.kind === 'dismissed') {
    await setTour($, { kind: 'none' })
    return dismissedLine(state.title)
  }
  if (state.kind !== 'shown' || state.drawer !== 'nvim') return undefined
  const report = await readReport($, state.tour.id)
  if (report?.status === 'dismissed') {
    await setTour($, { kind: 'none' })
    await $.process.run(['rm', '-f', await reportPath($)])
    return dismissedLine(state.tour.title)
  }
  return describe(state.tour, report)
}

/** Where I am on `tour`, as nvim last reported it. */
export function describe(tour: Tour, report: Report | undefined): string {
  if (report?.current === undefined) return `tour "${tour.title}": no step opened yet, ${tour.steps.length} steps.`
  const visited = report.visited.length ? `visited ${ranges(report.visited)}` : 'none visited yet'
  return `tour "${tour.title}": on step ${report.current} of ${tour.steps.length}, ${visited}.`
}

function dismissedLine(title: string): string {
  return `The user dismissed tour "${title}".`
}

async function dismissPane($: EngineInterface, title: string): Promise<void> {
  await setTour($, { kind: 'dismissed', title })
  await $.ui.close({ id: PANE })
}

/** The report nvim wrote for tour `id`, or undefined when there is none for it. */
async function readReport($: EngineInterface, id: string): Promise<Report | undefined> {
  const text = await $.fs.read(await reportPath($)).catch(() => undefined)
  if (typeof text !== 'string') return undefined
  const report = parseReport(text)
  // A report of an earlier tour says nothing of this one.
  return report?.id === id ? report : undefined
}

function parseReport(text: string): Report | undefined {
  try {
    const value = JSON.parse(text) as Partial<Report>
    const isReport =
      typeof value.id === 'string' &&
      (value.status === 'active' || value.status === 'dismissed') &&
      (value.current === undefined || typeof value.current === 'number') &&
      Array.isArray(value.visited) &&
      value.visited.every((n) => typeof n === 'number')
    return isReport ? (value as Report) : undefined
  } catch {
    return undefined
  }
}

/** This session's report file: named by its own id, so no session reads another's. */
async function reportPath($: EngineInterface): Promise<string> {
  const stateHome = (await $.env.get('XDG_STATE_HOME')) || `${await $.env.get('HOME')}/.local/state`
  return `${stateHome}/claude-tour/${await $.session.id()}.json`
}

type AskedStep = { file: string; line?: number; description: string }

/** The show call's arguments, or why they are not a tour. */
function parseShow(e: object): { title: string; steps: AskedStep[] } | string {
  const { title, steps } = e as { title?: unknown; steps?: unknown }
  if (typeof title !== 'string' || title === '') return 'A tour needs a title.'
  if (!Array.isArray(steps) || steps.length === 0) return 'A tour needs at least one step.'
  for (const [i, step] of steps.entries()) {
    const s = step as Partial<AskedStep>
    const isStep =
      typeof s.file === 'string' &&
      typeof s.description === 'string' &&
      (s.line === undefined || (Number.isInteger(s.line) && s.line >= 1))
    if (!isStep) return `Step ${i + 1} needs a file, a description and, if any, a line of 1 or more.`
  }
  return { title, steps: steps as AskedStep[] }
}

/** `steps` with absolute paths, or which files are missing. */
async function resolveSteps($: EngineInterface, steps: AskedStep[]): Promise<Step[] | string> {
  const cwd = await $.session.cwd()
  const resolved = steps.map(({ file, line, description }) => ({
    path: file.startsWith('/') ? file : `${cwd}/${file}`,
    ...(line === undefined ? {} : { line }),
    description,
  }))
  const missing: string[] = []
  for (const step of resolved) {
    const stat = await $.fs.stat(step.path).catch(() => undefined)
    if (stat?.kind !== 'file') missing.push(step.path)
  }
  return missing.length ? `No such file: ${[...new Set(missing)].join(', ')}` : resolved
}

/** Call fishmonger.tour's `fn` in the nvim at `server`; the error it gives, or undefined on success. */
async function callNvim($: EngineInterface, server: string, fn: 'show' | 'finish', argument: object): Promise<string | undefined> {
  // JSON in a single-quoted vimscript string, where the only escape is a doubled quote.
  const payload = JSON.stringify(argument).replaceAll("'", "''")
  const expr = `luaeval('require("fishmonger.tour").${fn}(_A) or ""', json_decode('${payload}'))`
  const ran = await $.process.run(['nvim', '--server', server, '--remote-expr', expr])
  if (ran.exitCode !== 0) return ran.stderr.trim() || `nvim exited ${ran.exitCode}`
  return ran.stdout.trim() || undefined
}

function stepLabel(step: Step, cwd: string): string {
  const path = step.path.startsWith(`${cwd}/`) ? step.path.slice(cwd.length + 1) : step.path
  return step.line === undefined ? path : `${path}:${step.line}`
}

/** Ascending indices as runs: [1, 2, 3, 5] reads "1-3, 5". */
function ranges(indices: readonly number[]): string {
  const runs: [number, number][] = []
  for (const index of [...indices].sort((a, b) => a - b)) {
    const last = runs.at(-1)
    if (last && index === last[1] + 1) last[1] = index
    else runs.push([index, index])
  }
  return runs.map(([from, to]) => (from === to ? `${from}` : `${from}-${to}`)).join(', ')
}

function setTour($: EngineInterface, state: TourState): Promise<TourState> {
  return update($, current, () => state)
}
