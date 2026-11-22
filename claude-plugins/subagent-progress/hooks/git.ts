import type { EngineInterface } from 'claude-code'
import type { Branch, Commit, GitProgress, RepoWorkspace, Workspace } from '../types'

// The repository <cwd> is in and its HEAD; a repo with no commits yet has nothing to count from, so reads as outside one.
export async function readWorkspace($: EngineInterface, cwd: string): Promise<Workspace> {
  const found = await git($, cwd, ['rev-parse', '--path-format=absolute', '--git-common-dir', 'HEAD'])
  return found === undefined ? { kind: 'outside-repo', cwd } : parseWorkspace(cwd, found)
}

// What has changed in <workspace> since the agent started, or nothing when git could not say.
export async function readProgress($: EngineInterface, { cwd, base }: RepoWorkspace): Promise<GitProgress | undefined> {
  const [status, ahead, latest] = await Promise.all([
    // Without optional locks, so this read never holds the index lock an agent's own commit needs.
    git($, cwd, ['--no-optional-locks', 'status', '--porcelain=v2', '--branch']),
    git($, cwd, ['rev-list', '--count', `${base}..HEAD`]),
    git($, cwd, ['log', '-1', '--format=%ct%x00%s', `${base}..HEAD`]),
  ])
  if (status === undefined || ahead === undefined || latest === undefined) return undefined
  return { ...parseStatus(status), ahead: Number(ahead.trim()), latest: parseLatest(latest) }
}

export function parseWorkspace(cwd: string, revParse: string): Workspace {
  const [commonDir = '', base = ''] = revParse.trim().split('\n')
  return { kind: 'repo', cwd, repo: repoName(commonDir), base }
}

export function parseStatus(porcelain: string): Pick<GitProgress, 'branch' | 'changedFiles'> {
  const lines = porcelain.split('\n').filter((line) => line !== '')
  const head = lines.find((line) => line.startsWith('# branch.head '))?.slice('# branch.head '.length)
  const branch: Branch = head === undefined || head === '(detached)' ? { kind: 'detached' } : { kind: 'named', name: head }
  return { branch, changedFiles: lines.filter((line) => !line.startsWith('#')).length }
}

export function parseLatest(log: string): Commit | undefined {
  const [time, subject] = log.trim().split('\0')
  return time && subject !== undefined ? { subject, committedAt: Number(time) * 1000 } : undefined
}

// A worktree shares its main checkout's git dir, so the repo is named after that: `/src/dotfiles/.git` is `dotfiles`.
function repoName(commonDir: string): string {
  const parts = commonDir.replace(/\/+$/, '').split('/')
  const last = parts.pop() ?? ''
  return last === '.git' ? (parts.pop() ?? last) : last.replace(/\.git$/, '')
}

async function git($: EngineInterface, cwd: string, args: string[]): Promise<string | undefined> {
  const ran = await $.process.run(['git', ...args], { cwd, timeoutMs: 10_000 }).catch(() => undefined)
  return ran?.exitCode === 0 ? ran.stdout : undefined
}
