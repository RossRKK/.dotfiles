import type { EngineInterface, Register } from 'claude-code'

// Who this session is: the name other sessions address it by and the prompt-bar colour fewest live sessions share.
type Identity = { name?: string; colour?: string }

export const register: Register = (on) => {
  let identity: Identity = {}

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    identity = await discover($)
    show($, identity)
    return started
  })

  // /clear resets the name and the colour but keeps the process, and so the claim.
  on('command.run', { command: 'clear' }, async ($, e, next) => {
    const cleared = await next(e)
    show($, identity)
    return cleared
  })
}

async function discover($: EngineInterface): Promise<Identity> {
  return {
    name: await output($, ['session-name', await $.session.id()]),
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
