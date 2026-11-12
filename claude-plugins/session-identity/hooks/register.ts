import type { ClassicEventOf, EngineInterface, Register } from 'claude-code'

// Who this session is: the name other sessions address it by and the prompt-bar colour fewest live sessions share.
type Identity = { name?: string; colour?: string }

export const register: Register = (on) => {
  // Claude keeps a /rename title over a resume and a /clear, but never the colour.
  on('classic.SessionStart', async ($, e, next) => {
    const started = await next(e)
    if (e.source !== 'compact') show($, await discover($, e))
    return started
  })
}

async function discover($: EngineInterface, e: ClassicEventOf['classic.SessionStart']): Promise<Identity> {
  // A fork arrives with its parent's title, so it needs a name of its own.
  const named = e.session_title && e.source !== 'fork'
  const forkOf = e.session_title ? ['--fork-of', e.session_title] : []
  return {
    name: named ? undefined : await output($, ['session-name', ...forkOf, e.session_id]),
    colour: await output($, ['claim-colour']),
  }
}

// A command can't run from inside another's hook, so after this one returns.
function show($: EngineInterface, { name, colour }: Identity) {
  $.clock.after(0, async () => {
    for (const [command, args] of [['rename', name], ['color', colour]] as const) {
      if (args) await $.command.run({ command, args }).catch((err) => $.ui.log(`/${command} ${args} failed: ${err}`))
    }
  })
}

// What one of this mod's scripts printed, or nothing when it failed.
async function output($: EngineInterface, [script, ...args]: string[]): Promise<string | undefined> {
  const { exitCode, stdout } = await $.process.run([`${$.plugin.root}/hooks/${script}`, ...args])
  const printed = stdout.trim()
  return exitCode === 0 && printed !== '' ? printed : undefined
}
