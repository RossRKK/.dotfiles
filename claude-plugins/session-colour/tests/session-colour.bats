#!/usr/bin/env bats
# Runs the hook as Claude Code does, from inside a stand-in claude process (with
# an intermediate shell) so its walk up the process tree has something to find.

setup() {
  hook="$BATS_TEST_DIRNAME/../hooks/session-colour"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
  claims="$XDG_RUNTIME_DIR/claude-agents"
  mkdir -p "$claims"
  # nix runs claude from a binary named .claude-unwrapped; the kernel keeps 15 chars of it.
  agent="$BATS_TEST_TMPDIR/.claude-unwrapped"
  ln -s "$(command -v bash)" "$agent"
}

# Under the stand-in claude, claims <colour> for it (unless empty) and runs the hook.
run_in_claude() {
  "$agent" -c '[ -z "$2" ] || echo "{\"colour\":\"$2\",\"pid_start\":1}" >"$1/$$.colour"
    sh -c "\"\$0\"; true" "$0" </dev/null' "$hook" "$claims" "$1"
}

@test "re-sends the colour claimed for the claude process it runs under" {
  run run_in_claude blue
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.initialUserMessage <<<"$output")" = "/color blue" ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = SessionStart ]
}

@test "a claude with no claim gets nothing, even if a process between holds one" {
  run "$agent" -c 'sh -c "echo {\\\"colour\\\":\\\"red\\\"} >\"$1/\$\$.colour\"; \"$0\"; true" "$0" "$1" </dev/null' "$hook" "$claims"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}
