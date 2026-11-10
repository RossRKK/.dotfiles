import type { Item, Priority, Source, SourceKind, WaitingOn } from '../types'

// A written item; one left without a priority keeps the one it has.
export type Change = Omit<Item, 'priority'> & { priority?: Priority }
export type Update = { upsert: Change[]; remove: string[] }
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
const PRIORITIES: readonly Priority[] = ['high', 'normal', 'low']
// Long enough for one line in a docked pane; the cap keeps Claude terse.
const MAX_TEXT = 80
// Done items stay only long enough to be seen closing.
const KEPT_DONE = 5

export const UPDATE_SCHEMA = {
  type: 'object',
  properties: {
    upsert: {
      type: 'array',
      description:
        'Items to add, or to replace by id. An item keeps its place while it stays in its section; one new to a section joins the end of its priority.',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'Stable key for the work: its ticket key, else its PR URL, else the session name.' },
          title: { type: 'string', maxLength: MAX_TEXT, description: 'What the work is, in a few words.' },
          waitingOn: { type: 'string', enum: WAITING_ON, description: 'Who has to act next: you (the user), agent (a session is on it), others (reviewer, CI, another team), done.' },
          note: { type: 'string', maxLength: MAX_TEXT, description: 'Why it waits there, in a few words, e.g. "2 new comments".' },
          priority: {
            type: 'string',
            enum: PRIORITIES,
            description:
              'Where it sits in its section: high items first, then normal, then low. Leave it out to keep the priority the item has; a new item is normal.',
          },
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
    : { kind: 'valid', update: { upsert: items.filter((item): item is Change => item !== undefined), remove: remove as string[] } }
}

// An item keeps its place while it stays in its section; one arriving in a
// section, new or moved, joins its end. A removed id wins over an upsert of it.
export function applyUpdate(items: readonly Item[], { upsert, remove }: Update): Item[] {
  const removed = new Set(remove)
  const before = new Map(items.map((item) => [item.id, item]))
  const written = new Map(
    upsert
      .filter((change) => !removed.has(change.id))
      .map((change) => [change.id, { ...change, priority: change.priority ?? before.get(change.id)?.priority ?? 'normal' }]),
  )
  const staying = items.flatMap((item) => {
    const now = written.get(item.id) ?? item
    return removed.has(item.id) || now.waitingOn !== item.waitingOn ? [] : [now]
  })
  const arriving = [...written.values()].filter((item) => before.get(item.id)?.waitingOn !== item.waitingOn)
  const next = [...staying, ...arriving]
  const done = next.filter((item) => item.waitingOn === 'done')
  const expired = new Set(done.slice(0, Math.max(0, done.length - KEPT_DONE)))
  return next.filter((item) => !expired.has(item))
}

export function sections(items: readonly Item[]): Section[] {
  return SECTIONS.map((s) => ({ ...s, items: items.filter((item) => item.waitingOn === s.waitingOn).sort(byPriority) })).filter(
    (s) => s.items.length > 0,
  )
}

// The board as Claude reads it back, ids included so it can update items.
export function describe(items: readonly Item[]): string {
  if (items.length === 0) return 'The board is empty.'
  return sections(items)
    .map(({ heading, items }) =>
      [`${heading}:`, ...items.map((item) => `- [${item.id}, ${item.priority}] ${item.title}: ${item.note} (${item.sources.map(sourceLabel).join(', ')})`)].join('\n'),
    )
    .join('\n\n')
}

// A GitHub PR URL reads as owner/repo#123; anything else as given.
export function sourceLabel({ ref }: Source): string {
  const pr = ref.match(/^https:\/\/github\.com\/([^/]+\/[^/]+)\/pull\/(\d+)/)
  return pr ? `${pr[1]}#${pr[2]}` : ref
}

function byPriority(a: Item, b: Item): number {
  return PRIORITIES.indexOf(a.priority) - PRIORITIES.indexOf(b.priority)
}

function parseItem(raw: unknown, at: string, problems: string[]): Change | undefined {
  if (!isRecord(raw)) {
    problems.push(`${at} must be an object`)
    return undefined
  }
  const { id, title, waitingOn, note, priority, sources } = raw
  const before = problems.length
  if (typeof id !== 'string' || id === '') problems.push(`${at}.id must be a non-empty string`)
  if (!isShortText(title)) problems.push(`${at}.title must be a string of at most ${MAX_TEXT} characters`)
  if (!isShortText(note)) problems.push(`${at}.note must be a string of at most ${MAX_TEXT} characters`)
  if (!WAITING_ON.includes(waitingOn as WaitingOn)) problems.push(`${at}.waitingOn must be one of ${WAITING_ON.join(', ')}`)
  if (priority !== undefined && !PRIORITIES.includes(priority as Priority)) problems.push(`${at}.priority must be one of ${PRIORITIES.join(', ')}`)
  if (!Array.isArray(sources) || !sources.every(isSource)) problems.push(`${at}.sources must be a list of { kind: ${SOURCE_KINDS.join('|')}, ref }`)
  if (problems.length > before) return undefined
  return {
    id: id as string,
    title: title as string,
    waitingOn: waitingOn as WaitingOn,
    note: note as string,
    ...(priority === undefined ? {} : { priority: priority as Priority }),
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
