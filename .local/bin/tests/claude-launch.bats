#!/usr/bin/env bats
# Runs the launcher against a stand-in claude that prints the arguments it was
# exec'd with, one per line, then its own pid. petname is stubbed to print its
# seed, so a name shows which id it came from.

setup() {
  launch="$BATS_TEST_DIRNAME/../claude-launch"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  claims="$XDG_RUNTIME_DIR/claude-agents"
  mkdir -p "$claims" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/work"
  claude="$BATS_TEST_TMPDIR/bin/claude"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@"; echo "pid $$"\n' >"$claude"
  printf '#!/bin/sh\necho "pet-$4"\n' >"$BATS_TEST_TMPDIR/bin/petname"
  printf '#!/bin/sh\necho ABCDEF00-0000-4000-8000-000000000001\n' >"$BATS_TEST_TMPDIR/bin/uuidgen"
  chmod +x "$BATS_TEST_TMPDIR"/bin/*
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  new_id=abcdef00-0000-4000-8000-000000000001
  cd "$BATS_TEST_TMPDIR/work"
}

start_time() {
  local line
  line=$(cat "/proc/$1/stat")
  printf '%s' "${line##*) }" | cut -d' ' -f20
}

# Claims <colour> for a process that is still running.
live_claim() {
  printf '{"colour":"%s","pid_start":%s}\n' "$2" "$(start_time "$1")" >"$claims/$1.colour"
}

# Stores a conversation <id> for the current directory, as Claude does.
stored_session() {
  local project
  project="$CLAUDE_CONFIG_DIR/projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$project"
  touch -d "$2" "$project/$1.jsonl"
}

# The name a run passed with --name.
name_of() {
  local i
  for i in "${!lines[@]}"; do
    [ "${lines[$i]}" != --name ] || { echo "${lines[$((i + 1))]}"; return; }
  done
}

@test "a new session gets an id of ours, a name from it, and the first colour" {
  run "$launch" "$claude"
  [ "${lines[*]:2:3}" = "/color red --session-id $new_id" ]
  [ -n "$(name_of)" ]
}

@test "resuming a session gives it the name it was started with" {
  run "$launch" "$claude"
  started=$(name_of)

  run "$launch" "$claude" --resume "$new_id"
  [ "$(name_of)" = "$started" ]
  [ "${lines[*]:2:3}" = "/color red --resume $new_id" ]
}

@test "different sessions get different names" {
  run "$launch" "$claude" --resume 11111111-0000-4000-8000-000000000000
  one=$(name_of)
  run "$launch" "$claude" --resume 22222222-0000-4000-8000-000000000000
  [ "$(name_of)" != "$one" ]
}

@test "a fork is a new session, with its own id and name" {
  run "$launch" "$claude" --resume abc --fork-session
  [ "${lines[*]:2:5}" = "/color red --session-id $new_id --resume abc" ]
  forked=$(name_of)
  run "$launch" "$claude" --resume abc
  [ "$(name_of)" != "$forked" ]
}

@test "continuing resumes this directory's newest conversation by id" {
  stored_session older 2026-01-01
  stored_session newer 2026-01-02

  run "$launch" "$claude" -c
  [ "${lines[*]:2:3}" = "/color red --resume newer" ]
}

@test "continuing with no conversation here starts a new session" {
  run "$launch" "$claude" --continue
  [ "${lines[*]:2:3}" = "/color red --session-id $new_id" ]
  [ "${#lines[@]}" -eq 6 ]
}

@test "the resume picker is recoloured but can't be named" {
  run "$launch" "$claude" -r
  [ "${lines[*]:0:2}" = "/color red -r" ]
}

@test "a colour a live session holds is skipped" {
  live_claim $$ red

  run "$launch" "$claude"
  [ "${lines[2]}" = "/color blue" ]
}

@test "with every colour taken, the least used comes next, earliest on a tie" {
  for colour in red blue green yellow purple cyan pink orange red; do
    sleep 600 &
    live_claim $! "$colour"
    pids="${pids-} $!"
  done

  run "$launch" "$claude"
  kill $pids
  [ "${lines[2]}" = "/color blue" ]
}

@test "a dead session's claim is ignored and removed" {
  printf '{"colour":"red","pid_start":1}\n' >"$claims/$$.colour"

  run "$launch" "$claude"
  [ "${lines[2]}" = "/color red" ]
  [ ! -e "$claims/$$.colour" ]
}

@test "the claim is keyed by the claude process the launcher became" {
  run "$launch" "$claude"
  pid=${lines[-1]#pid }
  [ "$(jq -r .colour "$claims/$pid.colour")" = red ]
}

@test "plugin dirs ahead of the caller's arguments are kept and don't count as arguments" {
  run "$launch" "$claude" --plugin-dir /a --plugin-dir /b --resume abc
  [ "${lines[*]:0:4}" = "--plugin-dir /a --plugin-dir /b" ]
  [ "${lines[*]:6:3}" = "/color red --resume abc" ]
}

@test "any other arguments pass through untouched and claim nothing" {
  run "$launch" "$claude" "fix the tests"
  [ "${lines[0]}" = "fix the tests" ]
  [ "${#lines[@]}" -eq 2 ]
  [ -z "$(ls "$claims")" ]
}

@test "terminal 1 of the main ionics checkout is always the big cheese" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/ionics" && cd "$HOME/ionics"

  WORKSPACE_TERMINAL=1 run "$launch" "$claude"
  [ "$(name_of)" = big-cheese ]

  WORKSPACE_TERMINAL=1 run "$launch" "$claude" --resume abc
  [ "$(name_of)" = big-cheese ]
}

@test "terminal 1 of the dotfiles is always dotty" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.dotfiles" && cd "$HOME/.dotfiles"

  WORKSPACE_TERMINAL=1 run "$launch" "$claude"
  [ "$(name_of)" = dotty ]
}

@test "other terminals and directories keep the name from their id" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/ionics" && cd "$HOME/ionics"

  WORKSPACE_TERMINAL=2 run "$launch" "$claude"
  [ "$(name_of)" = "pet-$((16#$(printf '%s' "$new_id" | sha256sum | cut -c1-15)))" ]

  cd "$BATS_TEST_TMPDIR/work"
  WORKSPACE_TERMINAL=1 run "$launch" "$claude"
  [ "$(name_of)" != big-cheese ] && [ "$(name_of)" != dotty ]
}

# A repo at ./repo with one commit, so worktrees can be added to it.
repo() {
  git init -q -b main repo
  git -C repo -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

@test "a worktree's terminals, its main checkout and a detached worktree keep the name from their id" {
  repo
  git -C repo worktree add -q -b feat/thing .worktrees/feat-thing
  git -C repo worktree add -q --detach .worktrees/detached
  pet="pet-$((16#$(printf '%s' "$new_id" | sha256sum | cut -c1-15)))"

  cd repo/.worktrees/feat-thing
  WORKSPACE_TERMINAL=1 run "$launch" "$claude"
  [ "$(name_of)" = "$pet" ]

  cd ../detached
  WORKSPACE_TERMINAL=1 run "$launch" "$claude"
  [ "$(name_of)" = "$pet" ]

  cd ../..
  WORKSPACE_TERMINAL=1 run "$launch" "$claude"
  [ "$(name_of)" = "$pet" ]
}
