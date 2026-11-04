import { expect, test } from 'claude-code/testing'
import { MARK, markLineEnds } from './register'

const cases: [string, string, string][] = [
  ['marks the end of a paragraph', 'one long paragraph', `one long paragraph${MARK}`],
  ['marks every line of a list', '- a\n- b', `- a${MARK}\n- b${MARK}`],
  ['leaves blank lines alone', 'a\n\nb', `a${MARK}\n\nb${MARK}`],
  ['marks code lines but not their fences', '```lua\nx = 1\n```', `\`\`\`lua\nx = 1${MARK}\n\`\`\``],
  ['leaves tilde fences alone', '~~~\nx\n~~~', `~~~\nx${MARK}\n~~~`],
  ['leaves table rows alone', '| a | b |\n|---|---|', '| a | b |\n|---|---|'],
  ['leaves horizontal rules alone', 'a\n---\n* * *', `a${MARK}\n---\n* * *`],
  ['marks a heading', '## Title', `## Title${MARK}`],
]

for (const [name, input, want] of cases) {
  test(name, async () => {
    expect(markLineEnds(input)).toBe(want)
  })
}

test('the hook hands the marked text on to the engine', async ($, on) => {
  let drawn: string | undefined
  on('ui.render', ($, e) => {
    drawn = (e.props as { text: string }).text
    const { Text } = $.ui.resolve(e)
    return <Text>{drawn}</Text>
  })

  const ui = await $.ui.mount({
    plugin: 'line-end-marks',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: 'a\nb', isFirstOfReply: true },
  })

  expect(drawn).toBe(`a${MARK}\nb${MARK}`)
  await ui.unmount()
})
