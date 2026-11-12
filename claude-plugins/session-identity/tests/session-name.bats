#!/usr/bin/env bats
# petname is stubbed to print its seed in both words, so a name shows which id
# it came from.

setup() {
  name="$BATS_TEST_DIRNAME/../hooks/session-name"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/work" "$BATS_TEST_TMPDIR/config"
  printf '#!/bin/sh\necho "adj$4-noun$4"\n' >"$BATS_TEST_TMPDIR/bin/petname"
  chmod +x "$BATS_TEST_TMPDIR/bin/petname"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$HOME/main" "$HOME/.dotfiles"
  printf '%s\n' '~/main overseer' '' "$HOME/.dotfiles dotty" >"$XDG_CONFIG_HOME/claude-roles"
  unset WORKSPACE_TERMINAL
  cd "$BATS_TEST_TMPDIR/work"
}

seed_for() {
  echo $((16#$(printf '%s' "$1" | sha256sum | cut -c1-15)))
}

pet_for() {
  echo "adj$(seed_for "$1")-noun$(seed_for "$1")"
}

@test "a session is named from its id, the same every time" {
  run "$name" 11111111-0000-4000-8000-000000000000
  [ "$output" = "$(pet_for 11111111-0000-4000-8000-000000000000)" ]
}

@test "different sessions get different names" {
  one=$("$name" 11111111-0000-4000-8000-000000000000)
  [ "$("$name" 22222222-0000-4000-8000-000000000000)" != "$one" ]
}

@test "terminal 1 of a listed checkout takes its role's name, ~ or absolute" {
  cd "$HOME/main"
  WORKSPACE_TERMINAL=1 run "$name" abc
  [ "$output" = overseer ]

  cd "$HOME/.dotfiles"
  WORKSPACE_TERMINAL=1 run "$name" abc
  [ "$output" = dotty ]
}

@test "other terminals and unlisted directories keep the name from their id" {
  cd "$HOME/main"
  WORKSPACE_TERMINAL=2 run "$name" abc
  [ "$output" = "$(pet_for abc)" ]

  cd "$BATS_TEST_TMPDIR/work"
  WORKSPACE_TERMINAL=1 run "$name" abc
  [ "$output" = "$(pet_for abc)" ]
}

@test "a worktree of a role's checkout keeps the name from its id" {
  mkdir -p "$HOME/main/.worktrees/feat" && cd "$HOME/main/.worktrees/feat"
  WORKSPACE_TERMINAL=1 run "$name" abc
  [ "$output" = "$(pet_for abc)" ]
}

@test "with no roles file, every session keeps the name from its id" {
  rm "$XDG_CONFIG_HOME/claude-roles"
  cd "$HOME/main"
  WORKSPACE_TERMINAL=1 run "$name" abc
  [ "$output" = "$(pet_for abc)" ]
}
