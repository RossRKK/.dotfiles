#!/usr/bin/env bats
# Runs the launcher against a stand-in claude that prints the arguments it was
# exec'd with, one per line, then its own pid.

setup() {
  launch="$BATS_TEST_DIRNAME/../claude-launch"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
  claims="$XDG_RUNTIME_DIR/claude-agents"
  mkdir -p "$claims" "$BATS_TEST_TMPDIR/bin"
  claude="$BATS_TEST_TMPDIR/bin/claude"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@"; echo "pid $$"\n' >"$claude"
  printf '#!/bin/sh\necho calm-otter\n' >"$BATS_TEST_TMPDIR/bin/petname"
  chmod +x "$claude" "$BATS_TEST_TMPDIR/bin/petname"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

start_time() {
  local line
  line=$(cat "/proc/$1/stat")
  printf '%s' "${line##*) }" | cut -d' ' -f20
}

# Claims <colour> for a process that is still running (this test's own shell).
live_claim() {
  printf '{"colour":"%s","pid_start":%s}\n' "$2" "$(start_time "$1")" >"$claims/$1.colour"
}

@test "a new session is named and given the first colour" {
  run "$launch" "$claude"
  [ "${lines[0]}" = --name ]
  [ "${lines[1]}" = calm-otter ]
  [ "${lines[2]}" = "/color red" ]
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
  pid=${lines[3]#pid }
  [ "$(jq -r .colour "$claims/$pid.colour")" = red ]
}

@test "a resumed session keeps its name but is recoloured" {
  run "$launch" "$claude" --resume abc
  [ "${lines[0]}" = "/color red" ]
  [ "${lines[1]}" = --resume ]
  [ "${lines[2]}" = abc ]
}

@test "continuing the last session is recoloured too" {
  run "$launch" "$claude" -c
  [ "${lines[0]}" = "/color red" ]
  [ "${lines[1]}" = -c ]
}

@test "a fork is a new session, so it gets its own name" {
  run "$launch" "$claude" --resume abc --fork-session
  [ "${lines[*]:0:6}" = "--name calm-otter /color red --resume abc --fork-session" ]
}

@test "plugin dirs ahead of the caller's arguments are kept and don't count as arguments" {
  run "$launch" "$claude" --plugin-dir /a --plugin-dir /b --resume abc
  [ "${lines[*]:0:6}" = "--plugin-dir /a --plugin-dir /b /color red --resume" ]
}

@test "any other arguments pass through untouched and claim nothing" {
  run "$launch" "$claude" "fix the tests"
  [ "${lines[0]}" = "fix the tests" ]
  [ "${#lines[@]}" -eq 2 ]
  [ -z "$(ls "$claims")" ]
}
