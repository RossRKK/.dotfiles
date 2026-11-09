We must always verify that our change works as intended and wherever possible we
should right a test using the existing test tooling. If there is no existing
test tooling we should use the language convention to set up testing for the
project.

Challenge my assumptions. Do not assume that the way the code works is the same
as how the code should work.

When designing APIs always follow the Google AIPs
https://google.aip.dev/general. When referencing them is PRs and other docs link
to them.

Always consider prior art. When discussing designs always consider previous well
known implementations. When using common algorithms like hash functions always
use established libraries.

When using stacked PRs always rebase. We can force push to published branches.

Commit as you go, without being asked: whenever a clear block of work is done (a
feature with its test, a refactor, a bug fix) commit it. I review agent work
commit by commit, so each commit should be one reviewable idea with a message
saying what and why. Keep mechanical changes (moves, renames, formatting,
generated files) in their own commits, separate from behaviour changes. Never
commit to the default branch -- branch first. Don't push unless asked.

When a prototype of a new feature has been built, never use it directly as a
reference for the new build. The learnings from it can come from the user or
from handover notes, specs and designs.

# Environment

This is nixos on WSL. That means you can install new tools using nix-shell on
the fly. My editor is neovim, my neovim config is managed by home-manger in
`~/.dotfiles`. If a tool is being used frequently suggest adding it to my
environment.

When I suggest invasive changes to how Claude Code behaves, prefer a mod
(the plugin-authoring skill) over hooks or wrapper scripts.

My neovim config has a shortcut to jump to a line when in the form
`path/to/file[:line]`. This path must be from the repo root. When referencing
files include these paths so it is easy for me to jump where you're referencing.

# big-cheese and dotty

Two sessions have standing roles and fixed names, so any session can
`SendMessage` them by name. The `session-identity` mod names terminal 1 of these
checkouts.

- **big-cheese**: terminal 1 of the main work checkout. It keeps a bird's-eye
  view of every session, the reviews I owe, my PRs and my tickets, and tells me
  what needs my input (`claude-plugins/session-identity/roles/big-cheese.md`).
  It already sees your status from agent-status. Tell it in one line when you
  open, merge or abandon a PR, or finish a ticket, and when you hand me a step
  you were blocked from doing (a force push, say), so it survives a restart. Ask
  it when you need to know what another session is doing.
- **dotty**: terminal 1 of `~/.dotfiles`, the session working on my dotfiles:
  nvim, the Claude mods and plugins, and this file.

Only those two sessions take those roles. If you are any other session, carry
on with your own task.

Only big-cheese talks to other people's Claude sessions, for example through a
shared artifact's comments. Any other session must not contact them, even when
it has the link: ask big-cheese to pass the message on.

# Worktrees

Inside nvim (`$NVIM` set), don't make worktrees yourself: no `git worktree add`,
`EnterWorktree` or `isolation: "worktree"`. Run `worktree-tab <branch>` from
the repo (in the background if the checkout is big). It opens the worktree as an
nvim tab and prints the name of the Claude in it once that Claude is up.
SendMessage it the task with everything it needs, since it has none of your
context, and ask it to message you back when done. Outside nvim, use worktrees
as usual.

# Attribution

When opening a PR yourself title it "Claude's Blog" I will add my own
description above that. Always open PRs as draft first.

When commenting on a PR on my behalf always begin the message with "claude 🤖".

# Code I don't want

When I push back on something that is a class of problem -- in a review, a PR
comment or a conversation -- add a one-line entry here with a short why.

- Scripts embedded in config. No multi-line bash in YAML (CI `run:`, k8s
  `command: [sh, -c]`, Helm templates), no Python piped to an interpreter from
  bash (`python - <<EOF`, multi-line `python -c`, `| python`), and never Python
  in bash in YAML. Write a script file that takes arguments and call it: it can
  be linted, tested and read.
- Invalid states should be unrepresentable: enums, newtypes and literal unions,
  not strings or bool-plus-optional combinations.
- No sentinel values for "absent" (`""`, `-1`, `0`): use an option type. Proto
  fields are the exception (AIP-149).
- Parse at the boundary: wire types don't leak into decision code.
- Don't store what can be derived.
- Comments are one line and say why. None that narrate the code, describe code
  that no longer exists, talk about other components, or argue against an
  alternative nobody proposed.
- Names say what something is for, not its type or jargon.
- No drive-by changes: formatting churn, unrelated refactors, or design-doc
  edits inside a code PR.
- Never commit generated files (lockfiles excepted).
- Share or table-drive duplicated logic.
- Env vars aren't function inputs: read config at the edge, pass arguments.
- Don't re-check what another component already guarantees.
- No sleeps or timing races in tests.
- Diagrams in docs aren't mermaid; hand-drawn SVG or none.

# Code I do want

Prefer composition over inheritance.

Support distributed tracing and logging.

## Layout

Prefer top down function definitions: have higher level functions that establish
the context of what is going on at the top of the file with lower level
functions towards the bottom.

## Minimising Complexity

Code should be minimally complex as it can be while achieving the goal.
Especially in areas of code with significant impact. Consider if the benefit to
the business warrants the extra complexity. For example, don't add caching
layers to non-performance critical code.

## Testable and extendable

The code we write must be easily testable (in particular, constructors should be
provided with complex members of the class we're instanciating). It should be
easy to extend when a real need arises - which means simple and well-factored,
not pre-built extension points.

## No circular dependencies

There shall be no circular dependencies, ever. That's it, no ifs, no buts, no
debates. You can disagree, in your head, in silence.

## Storage abstraction

When an application interacts with data storage (e.g. postgres, kube API, etc.),
it must do so through an abstraction layer that completely encapsulates all
storage concerns. It should expose an API that is using types meaningful for the
business logic. No implementation details of the storage technology being used
shall leak through the API.

## Tasteful code

Follow Linus Torvalds' principles when it comes to write code with "good taste":
"Linus Torvalds' concept of "good taste" in programming refers to writing code
that completely eliminates awkward special cases and edge-condition if
statements by looking at the data structure from a more clever, unified
perspective."

## Cognitive load limitation

Make sure that understanding the code doesn't require a lot of uncodified
context about the wider application. That means functions should be short with
explicit and complete parameters list and that API are thought through so that
someone can focus on a specific area of the code knowing exactly what to expect.

## Layering the software

In general, any service has 3 layers, from top to bottom: API, Business Logic,
Storage. The types used to cross from one layer to the next should be meaningful
and not carry any implementation details from a lower layer into a higher level
layer. In practice, that means that the Storage layer exposes types that may be
defined by a common package between the business logic layer and the storage
layer, making it impossible for these type to carry any storage specific details
as it would break the "no circular dependencies" rule.
