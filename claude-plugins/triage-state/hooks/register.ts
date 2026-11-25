import { atom, read, update, type EngineInterface, type Register } from 'claude-code'
import type { Review, TriageStatus } from '../types'

const told = atom({ plugin: 'triage-state', key: 'told' } as const, null)

// A big branch can touch hundreds of files; past this many the context names how many more there are.
export const MAX_FILES = 50
// The prompt waits on this, so a busy nvim costs it no more than a moment.
const NVIM_TIMEOUT_MS = 2000

// Most in need of attention first, so a cut list drops approvals before anything still open.
const GROUPS: { status: TriageStatus; label: string }[] = [
  { status: 'rejected', label: 'rejected' },
  { status: 'revised', label: 'rejected, then edited (to re-review)' },
  { status: 'stale', label: 'approved, then edited (to re-review)' },
  { status: 'changed', label: 'not reviewed yet' },
  { status: 'approved', label: 'approved' },
]

export const register: Register = (on) => {
  on('prompt.submit', async ($, e, next) => {
    if (e.command) return next(e)
    // Triage state must never stop a prompt from going.
    const line = await news($).catch(() => undefined)
    return line ? next({ ...e, context: [...(e.context ?? []), line] }) : next(e)
  })
}

/** What changed in the review since Claude was last told, or undefined when nothing did. */
async function news($: EngineInterface): Promise<string | undefined> {
  const server = await $.env.get('NVIM')
  if (!server) return undefined
  const review = await activeReview($, server, await $.session.cwd())
  if (review === 'unknown') return undefined
  const now = review ? JSON.stringify(review) : null
  const before = await read($, told)
  if (now === before) return undefined
  await update($, told, () => now)
  return review ? describe(review) : 'triage: review mode is now off in this repo; the review last reported no longer stands.'
}

/** The review as a header of counts and the files grouped by status. */
export function describe(review: Review): string {
  const against = review.label ? `${review.base} (${review.label})` : review.base
  if (review.files.length === 0) return `triage: reviewing this repo against ${against}; no files changed.`
  const groups = GROUPS.map((g) => ({ ...g, files: review.files.filter((f) => f.status === g.status).map((f) => f.rel) })).filter(
    (g) => g.files.length > 0,
  )
  const counts = groups.map((g) => `${g.files.length} ${g.label}`).join(', ')
  const lines = [`triage: reviewing this repo against ${against}, ${review.files.length} files: ${counts}.`]
  let room = MAX_FILES
  for (const g of groups) {
    const shown = g.files.slice(0, room)
    room -= shown.length
    if (shown.length) lines.push(`${g.label}: ${shown.join(', ')}`)
  }
  const hidden = review.files.length - MAX_FILES
  if (hidden > 0) lines.push(`… and ${hidden} more`)
  return lines.join('\n')
}

/** The active review of the repo holding `dir`, null when there is none, 'unknown' when nvim cannot say. */
async function activeReview($: EngineInterface, server: string, dir: string): Promise<Review | null | 'unknown'> {
  // JSON in a single-quoted vimscript string, where the only escape is a doubled quote; loaded-only, so asking never loads triage.
  const payload = JSON.stringify(dir).replaceAll("'", "''")
  const lua = 'package.loaded.triage and package.loaded.triage.review(_A) or nil'
  const expr = `json_encode(luaeval('${lua}', json_decode('${payload}')))`
  try {
    const ran = await $.process.run(['nvim', '--server', server, '--remote-expr', expr], { timeoutMs: NVIM_TIMEOUT_MS })
    return ran.exitCode === 0 ? parseReview(JSON.parse(ran.stdout)) : 'unknown'
  } catch {
    return 'unknown'
  }
}

const STATUSES: readonly string[] = GROUPS.map((g) => g.status)

function parseReview(value: unknown): Review | null | 'unknown' {
  if (value === null) return null
  const r = value as Partial<Review> | undefined
  const isReview =
    typeof r === 'object' &&
    typeof r.root === 'string' &&
    typeof r.base === 'string' &&
    (r.label === undefined || typeof r.label === 'string') &&
    Array.isArray(r.files) &&
    r.files.every((f) => typeof f?.rel === 'string' && STATUSES.includes(f?.status))
  return isReview ? (r as Review) : 'unknown'
}
