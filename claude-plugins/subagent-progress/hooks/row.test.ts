import { expect, test } from 'claude-code/testing'
import { formatDuration } from './row'

const durations: [number, string][] = [
  [-5_000, '0s'],
  [999, '0s'],
  [59_000, '59s'],
  [60_000, '1m'],
  [59 * 60_000 + 59_000, '59m'],
  [60 * 60_000, '1h00m'],
  [125 * 60_000, '2h05m'],
]

for (const [ms, shown] of durations) {
  test(`${ms}ms reads as ${shown}`, async () => {
    expect(formatDuration(ms)).toBe(shown)
  })
}
