# Agent tabs: requirements

Only what Ross has asked for directly.

## Goal

- Agents are fishmonger's first tab. That is the goal, not a separate command.
- fishmonger has a keybind to open a new agent.
- No `:AgentChat` command.

## Client

- Use agentic.nvim. Switching to it is the fix; CodeCompanion isn't to be fixed.
- Archive the CodeCompanion work.
- Start with agentic.nvim's normal experience.

## Must have

- An indication that inference is happening, like the Claude Code spinner.
- Session identity works: the session's name and colour are shown.
- The identity sits near the prompt, but not in it.

## Not needed

- A reachable Claude Code TUI tab. `claude` in a terminal tab covers that.

## Background

- The Claude Code TUI's vim mode shows a block cursor in both normal and
  insert mode; Neovim switches to a line in insert mode.
