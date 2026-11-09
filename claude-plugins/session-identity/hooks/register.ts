import type { EngineInterface, Register } from 'claude-code'

// Who this session is: the name other sessions address it by, the prompt-bar
// colour fewest live sessions share, and for a standing role its brief.
type Identity = { name?: string; colour?: string; role?: string }

const ROLE_STARTED = { plugin: 'session-identity', key: 'isRoleStarted' } as const
// A role's session gets going on its own, before anyone types.
const START_ROLE = 'You have just started. Do what your role says to do at session start.'

export const register: Register = (on) => {
  let identity: Identity = {}

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    identity = await discover($)
    // A reload runs this again in the same process; only a new process starts the role.
    const isRoleStarting = !!identity.role && !(await $.state.get(ROLE_STARTED)).value
    if (isRoleStarting) await $.state.set(ROLE_STARTED, true)
    show($, identity, isRoleStarting)
    return started
  })

  // /clear resets the name and the colour but keeps the process, and so the claim.
  on('command.run', { command: 'clear' }, async ($, e, next) => {
    const cleared = await next(e)
    show($, identity, !!identity.role)
    return cleared
  })

  // In the system prompt, not a skill or a message, so compaction can't drop it.
  on('prompt.compose', async ($, e, next) => {
    const composed = await next(e)
    if (!identity.role) return composed
    return { sections: [...composed.sections, { id: 'session-identity:role', text: identity.role, scope: 'session' }] }
  })
}

async function discover($: EngineInterface): Promise<Identity> {
  const name = await output($, ['session-name', await $.session.id()])
  return { name, colour: await output($, ['claim-colour']), role: name && (await roleBrief($, name)) }
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

async function roleBrief($: EngineInterface, name: string): Promise<string | undefined> {
  const path = `${$.plugin.root}/roles/${name}.md`
  return (await $.fs.exists(path)) ? $.fs.read(path) : undefined
}
