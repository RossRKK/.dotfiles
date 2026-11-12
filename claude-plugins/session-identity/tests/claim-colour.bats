#!/usr/bin/env bats
# Runs the claim from inside a stand-in claude process (with an intermediate
# shell), so its walk up the process tree has something to find.

setup() {
  claim="$BATS_TEST_DIRNAME/../hooks/claim-colour"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
  claims="$XDG_RUNTIME_DIR/claude-agents"
  mkdir -p "$claims"
  # nix runs claude from a binary named .claude-unwrapped; the kernel keeps 15 chars of it.
  agent="$BATS_TEST_TMPDIR/.claude-unwrapped"
  ln -s "$(command -v bash)" "$agent"
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

# Runs the claim under the stand-in claude; prints the claude's pid, then the claim's output.
claim_in_claude() {
  "$agent" -c 'echo "$$"; sh -c "\"\$0\"" "$0" </dev/null' "$claim"
}

@test "a session's first claim takes the first colour, keyed by its claude process" {
  run claim_in_claude
  [ "$status" -eq 0 ] && [ "${lines[1]}" = red ]
  [ "$(jq -r .colour "$claims/${lines[0]}.colour")" = red ]
}

@test "a session that already holds a colour keeps it" {
  run "$agent" -c 'printf "{\"colour\":\"pink\",\"pid_start\":%s}\n" "$(cut -d" " -f22 /proc/$$/stat)" >"$1/$$.colour"
    sh -c "\"\$0\"" "$0" </dev/null' "$claim" "$claims"
  [ "$output" = pink ]
}

@test "a colour a live session holds is skipped" {
  live_claim $$ red

  run claim_in_claude
  [ "${lines[1]}" = blue ]
}

@test "with every colour taken, the least used comes next, earliest on a tie" {
  for colour in red blue green yellow purple cyan pink orange red; do
    sleep 600 &
    live_claim $! "$colour"
    pids="${pids-} $!"
  done

  run claim_in_claude
  kill $pids
  [ "${lines[1]}" = blue ]
}

@test "a dead session's claim is ignored and removed" {
  printf '{"colour":"red","pid_start":1}\n' >"$claims/$$.colour"

  run claim_in_claude
  [ "${lines[1]}" = red ]
  [ ! -e "$claims/$$.colour" ]
}

# Runs the claim for <preferred> under the stand-in claude; prints as claim_in_claude.
prefer_in_claude() {
  "$agent" -c 'echo "$$"; sh -c "\"\$0\" \"\$1\"" "$0" "$1" </dev/null' "$claim" "$1"
}

@test "a preferred colour no live session holds is taken" {
  live_claim $$ red

  run prefer_in_claude purple
  [ "${lines[1]}" = purple ]
  [ "$(jq -r .colour "$claims/${lines[0]}.colour")" = purple ]
}

@test "a preferred colour a live session holds gives way to the usual claim" {
  live_claim $$ purple

  run prefer_in_claude purple
  [ "${lines[1]}" = red ]
}

@test "a preferred colour outside the palette gives way to the usual claim" {
  run prefer_in_claude default
  [ "${lines[1]}" = red ]
}

@test "a preferred colour replaces the session's own claim" {
  run "$agent" -c 'printf "{\"colour\":\"pink\",\"pid_start\":%s}\n" "$(cut -d" " -f22 /proc/$$/stat)" >"$1/$$.colour"
    sh -c "\"\$0\" green" "$0" </dev/null' "$claim" "$claims"
  [ "$output" = green ]
}

@test "a session that already holds its preferred colour keeps it" {
  run "$agent" -c 'printf "{\"colour\":\"green\",\"pid_start\":%s}\n" "$(cut -d" " -f22 /proc/$$/stat)" >"$1/$$.colour"
    sh -c "\"\$0\" green" "$0" </dev/null' "$claim" "$claims"
  [ "$output" = green ]
}
