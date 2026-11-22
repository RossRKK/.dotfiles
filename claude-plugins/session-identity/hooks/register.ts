import type { EngineInterface, Register } from 'claude-code'

// Who this session is: the name other sessions address it by and the prompt-bar colour fewest live sessions share.
type Identity = { name?: string; colour?: string }

// Engine events, as the guard Claude runs first skips a user mod's classic.* hooks.
export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    show($, await discover($, await $.session.id()))
    return started
  })

  // /clear starts a new session in the same process, which takes a new identity over the title Claude carries across.
  on('command.run', { command: 'clear' }, async ($, e, next) => {
    const cleared = await next(e)
    show($, await fresh($, await $.session.id()))
    return cleared
  })
}

// A new session <id>'s name, and a colour other than the one its process held.
async function fresh($: EngineInterface, id: string): Promise<Identity> {
  return {
    name: await output($, ['session-name', id]),
    colour: await output($, ['claim-colour', '--fresh']),
  }
}

// A title session <id>'s transcript holds is kept, and the colour it last had asked for again.
async function discover($: EngineInterface, id: string): Promise<Identity> {
  const title = await output($, ['recorded', 'title', id])
  const previous = await output($, ['recorded', 'colour', id])
  return {
    name: title ? undefined : await output($, ['session-name', id]),
    colour: await output($, ['claim-colour', ...(previous ? [previous] : [])]),
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
