import { expect, test } from 'claude-code/testing'
import { parseLatest, parseStatus, parseWorkspace } from './git'

const workspaces: [string, string, string][] = [
  ['a main checkout is named after its folder', '/src/dotfiles/.git\nabc\n', 'dotfiles'],
  ['a git dir given with a trailing slash names the same repo', '/src/dotfiles/.git/\nabc\n', 'dotfiles'],
  ['a bare repository drops its .git suffix', '/srv/tools.git\nabc\n', 'tools'],
]

for (const [name, revParse, repo] of workspaces) {
  test(name, async () => {
    expect(parseWorkspace('/w', revParse)).toEqual({ kind: 'repo', cwd: '/w', repo, base: 'abc' })
  })
}

test('status names the branch and counts every changed, staged, renamed and untracked path', async () => {
  const porcelain = [
    '# branch.oid 1234',
    '# branch.head rkk/parser',
    '# branch.upstream origin/rkk/parser',
    '1 .M N... 100644 100644 100644 a b src/a.ts',
    '2 R. N... 100644 100644 100644 a b R100 src/new.ts\tsrc/old.ts',
    '? notes.md',
    '',
  ].join('\n')
  expect(parseStatus(porcelain)).toEqual({ branch: { kind: 'named', name: 'rkk/parser' }, changedFiles: 3 })
})

test('a detached HEAD has no branch name', async () => {
  expect(parseStatus('# branch.oid 1234\n# branch.head (detached)\n')).toEqual({ branch: { kind: 'detached' }, changedFiles: 0 })
})

test('the latest commit keeps a subject with spaces and separators in it', async () => {
  expect(parseLatest('1700000000\0fix: a · b\n')).toEqual({ subject: 'fix: a · b', committedAt: 1_700_000_000_000 })
})

test('no commits since the start is no latest commit', async () => {
  expect(parseLatest('')).toBeUndefined()
})
