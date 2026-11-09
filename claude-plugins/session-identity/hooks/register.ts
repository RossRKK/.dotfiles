import type { EngineInterface, Register } from 'claude-code'

// Who this session is: the name other sessions address it by, the prompt-bar
// colour fewest live sessions share, and whether it has a role's brief
// (role-brief hands it over: mods can't add to the system prompt).
type Identity = { name?: string; colour?: string; hasBrief: boolean }

const ROLE_STARTED = { plugin: 'session-identity', key: 'isRoleStarted' } as const
// A role's session gets going on its own, before anyone types.
const START_ROLE = 'You have just started. Do what your role says to do at session start.'

export const register: Register = (on) => {
  let identity: Identity = { hasBrief: false }

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    identity = await discover($)
    // A reload runs this again in the same process; only a new process starts the role.
    const isRoleStarting = identity.hasBrief && !(await $.state.get(ROLE_STARTED)).value
    if (isRoleStarting) await $.state.set(ROLE_STARTED, true)
    show($, identity, isRoleStarting)
    return started
  })

  // /clear resets the name and the colour but keeps the process, and so the claim.
  on('command.run', { command: 'clear' }, async ($, e, next) => {
    const cleared = await next(e)
    show($, identity, identity.hasBrief)
    return cleared
  })
}

async function discover($: EngineInterface): Promise<Identity> {
  const role = await output($, ['role-name'])
  return {
    name: await output($, ['session-name', await $.session.id()]),
    colour: await output($, ['claim-colour']),
    hasBrief: role !== undefined && (await $.fs.exists(`${$.plugin.root}/roles/${role}.md`)),
  }
}

// A command can't run from inside another's hook, so after this one returns.
function show($: EngineInterface, { name, colour }: Identity, isRoleStarting: boolean) {
  $.clock.after(0, async () => {
    for (const [command, args] of [['rename', name], ['color', colour]] as const) {
      if (args) await $.command.run({ command, args }).catch((err) => $.ui.log(`/${command} ${args} failed: ${err}`))
    }
    if (isRoleStarting) await $.prompt.submit({ text: START_ROLE }).catch((err) => $.ui.log(`starting the role failed: ${err}`))
  })
}

// What one of this mod's scripts printed, or nothing when it failed.
async function output($: EngineInterface, [script, ...args]: string[]): Promise<string | undefined> {
  const { exitCode, stdout } = await $.process.run([`${$.plugin.root}/hooks/${script}`, ...args])
  const printed = stdout.trim()
  return exitCode === 0 && printed !== '' ? printed : undefined
}
