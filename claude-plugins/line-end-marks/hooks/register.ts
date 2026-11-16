import type { Register } from 'claude-code'

// A plain pilcrow: a zero-width mark spoils the glyph before it, and the renderer refuses SGR to dim one.
export const MARK = '\u00B6'

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
