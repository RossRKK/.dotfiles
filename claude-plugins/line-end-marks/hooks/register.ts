import type { Register } from 'claude-code'

// Zero-width non-joiner: Claude's renderer keeps it (it strips U+2060) and
// nvim's terminal stores it without giving it a cell.
export const MARK = '\u200C'

export const register: Register = (on) => {
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    return next({ ...e, props: { ...e.props, text: markLineEnds(e.props.text) } })
  })
}

// A character after a fence, a rule or a table row changes what markdown reads
// it as, so those lines stay unmarked; blank lines need no mark to be seen.
export function markLineEnds(text: string): string {
  return text
    .split('\n')
    .map((line) => (line.trim() === '' || /^\s*(```|~~~|\||([-*_]\s*){3,}$)/.test(line) ? line : line + MARK))
    .join('\n')
}
