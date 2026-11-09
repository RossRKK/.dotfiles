import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

// /clear as the person types it at the prompt.
const CLEAR = { command: 'clear', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as const

// Stands for the engine: clears, records each /color, and answers the colour
// lookup with <lookup>; the clock is mocked so the queued /color can be let run.
function engine(on: On, lookup: { exitCode: number; stdout: string }) {
  const coloured: string[] = []
  on('command.run', { command: 'clear' }, () => ({ text: '' }))
  on('command.run', { command: 'color' }, (_, e) => {
    coloured.push(e.args)
    return { text: `Session color set to: ${e.args}` }
  })
  on('process.run', () => ({ value: { ...lookup, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  return { coloured, clock: mock.clock(on) }
}

test('after /clear the claimed colour is set again', async ($, on) => {
  const { coloured, clock } = engine(on, { exitCode: 0, stdout: 'blue\n' })

  await $.command.run(CLEAR)
  await clock.settle()
  expect(coloured).toEqual(['blue'])
})

test('a session with no claim is left as /clear leaves it', async ($, on) => {
  const { coloured, clock } = engine(on, { exitCode: 1, stdout: '' })

  await $.command.run(CLEAR)
  await clock.settle()
  expect(coloured).toEqual([])
})
