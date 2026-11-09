import type { Register } from 'claude-code'

// /clear resets the prompt-bar colour but keeps the process, whose launcher
// claim still names it; fishmonger colours the tab from the same claim.
export const register: Register = (on) => {
  on('command.run', { command: 'clear' }, async ($, e, next) => {
    const cleared = await next(e)
    const { exitCode, stdout } = await $.process.run([`${$.plugin.root}/hooks/claimed-colour`])
    const colour = stdout.trim()
    if (exitCode === 0 && colour !== '') {
      // A command can't run from inside another's hook, so after this one returns.
      $.clock.after(0, () => {
        $.command.run({ command: 'color', args: colour }).catch((err) => $.ui.log(`/color ${colour} failed: ${err}`))
      })
    }
    return cleared
  })
}
