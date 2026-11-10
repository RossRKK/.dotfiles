import type { Item, Source, SourceKind, WaitingOn } from '../types'

export type Update = { upsert: Item[]; remove: string[] }
export type Parsed = { kind: 'valid'; update: Update } | { kind: 'invalid'; problems: string[] }
export type Section = { waitingOn: WaitingOn; heading: string; items: Item[] }

const SECTIONS: readonly { waitingOn: WaitingOn; heading: string }[] = [
  { waitingOn: 'you', heading: 'You' },
  { waitingOn: 'agent', heading: 'Agents' },
  { waitingOn: 'others', heading: 'Others' },
  { waitingOn: 'done', heading: 'Done' },
]
const WAITING_ON: readonly WaitingOn[] = SECTIONS.map((s) => s.waitingOn)
const SOURCE_KINDS: readonly SourceKind[] = ['ticket', 'pr', 'session']
// Long enough for one line in a docked pane; the cap keeps Claude terse.
const MAX_TEXT = 80
// Done items stay only long enough to be seen closing.
const KEPT_DONE = 5

export const UPDATE_SCHEMA = {
  type: 'object',
  properties: {
    upsert: {
      type: 'array',
      description: 'Items to add, or to replace by id.',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'Stable key for the work: its ticket key, else its PR URL, else the session name.' },
          title: { type: 'string', maxLength: MAX_TEXT, description: 'What the work is, in a few words.' },
          waitingOn: { type: 'string', enum: WAITING_ON, description: 'Who has to act next: you (the user), agent (a session is on it), others (reviewer, CI, another team), done.' },
          note: { type: 'string', maxLength: MAX_TEXT, description: 'Why it waits there, in a few words, e.g. "2 new comments".' },
          sources: {
            type: 'array',
            items: {
              type: 'object',
              properties: { kind: { type: 'string', enum: SOURCE_KINDS }, ref: { type: 'string' } },
              required: ['kind', 'ref'],
            },
          },
        },
        required: ['id', 'title', 'waitingOn', 'note', 'sources'],
      },
    },
    remove: { type: 'array', items: { type: 'string' }, description: 'Ids of items to drop.' },
  },
} as const

export function parseUpdate(input: unknown): Parsed {
  const problems: string[] = []
  const { upsert = [], remove = [] } = isRecord(input) ? input : {}
  if (!Array.isArray(upsert)) problems.push('upsert must be an array')
  if (!Array.isArray(remove) || !remove.every((id) => typeof id === 'string')) problems.push('remove must be an array of ids')
  const items = Array.isArray(upsert) ? upsert.map((raw, i) => parseItem(raw, `upsert[${i}]`, problems)) : []
  return problems.length > 0
    ? { kind: 'invalid', problems }
    : { kind: 'valid', update: { upsert: items.filter((item): item is Item => item !== undefined), remove: remove as string[] } }
}

// Updated items move to the end, so each section reads oldest change first.
export function applyUpdate(items: readonly Item[], { upsert, remove }: Update): Item[] {
  const replaced = new Set([...remove, ...upsert.map((item) => item.id)])
  const next = [...items.filter((item) => !replaced.has(item.id)), ...upsert]
  const done = next.filter((item) => item.waitingOn === 'done')
  const expired = new Set(done.slice(0, Math.max(0, done.length - KEPT_DONE)))
  return next.filter((item) => !expired.has(item))
}

export function sections(items: readonly Item[]): Section[] {
  return SECTIONS.map((s) => ({ ...s, items: items.filter((item) => item.waitingOn === s.waitingOn) })).filter(
    (s) => s.items.length > 0,
  )
}

// The board as Claude reads it back, ids included so it can update items.
export function describe(items: readonly Item[]): string {
  if (items.length === 0) return 'The board is empty.'
  return sections(items)
    .map(({ heading, items }) =>
      [`${heading}:`, ...items.map((item) => `- [${item.id}] ${item.title}: ${item.note} (${item.sources.map(sourceLabel).join(', ')})`)].join('\n'),
    )
    .join('\n\n')
}

// A GitHub PR URL reads as owner/repo#123; anything else as given.
export function sourceLabel({ ref }: Source): string {
  const pr = ref.match(/^https:\/\/github\.com\/([^/]+\/[^/]+)\/pull\/(\d+)/)
  return pr ? `${pr[1]}#${pr[2]}` : ref
}

function parseItem(raw: unknown, at: string, problems: string[]): Item | undefined {
  if (!isRecord(raw)) {
    problems.push(`${at} must be an object`)
    return undefined
  }
  const { id, title, waitingOn, note, sources } = raw
  const before = problems.length
  if (typeof id !== 'string' || id === '') problems.push(`${at}.id must be a non-empty string`)
  if (!isShortText(title)) problems.push(`${at}.title must be a string of at most ${MAX_TEXT} characters`)
  if (!isShortText(note)) problems.push(`${at}.note must be a string of at most ${MAX_TEXT} characters`)
  if (!WAITING_ON.includes(waitingOn as WaitingOn)) problems.push(`${at}.waitingOn must be one of ${WAITING_ON.join(', ')}`)
  if (!Array.isArray(sources) || !sources.every(isSource)) problems.push(`${at}.sources must be a list of { kind: ${SOURCE_KINDS.join('|')}, ref }`)
  if (problems.length > before) return undefined
  return {
    id: id as string,
    title: title as string,
    waitingOn: waitingOn as WaitingOn,
    note: note as string,
    sources: (sources as Source[]).map(({ kind, ref }) => ({ kind, ref })),
  }
}

function isShortText(raw: unknown): raw is string {
  return typeof raw === 'string' && raw.length <= MAX_TEXT
}

function isSource(raw: unknown): raw is Source {
  return isRecord(raw) && SOURCE_KINDS.includes(raw.kind as SourceKind) && typeof raw.ref === 'string' && raw.ref !== ''
}

function isRecord(raw: unknown): raw is Record<string, unknown> {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw)
}
