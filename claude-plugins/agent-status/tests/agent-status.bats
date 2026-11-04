#!/usr/bin/env bats
# Drives the hook as Claude Code does: event as $1, payload on stdin, run from
# inside a stand-in agent process so its ancestor walk has something to find.

setup() {
  hook="$BATS_TEST_DIRNAME/../hooks/agent-status"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
  status_dir="$XDG_RUNTIME_DIR/claude-agents"
  # nix runs claude from a binary named .claude-unwrapped; the kernel keeps 15 chars of it.
  agent="$BATS_TEST_TMPDIR/.claude-unwrapped"
  ln -s "$(command -v bash)" "$agent"
}

# Runs `hook <event>` with <payload> on stdin, under the stand-in agent and one
# intermediate shell, and echoes the agent's pid.
run_under_agent() {
  "$agent" -c 'echo $$; sh -c "\"\$0\" \"\$1\"; true" "$0" "$1" <<<"$2"; true' "$hook" "$1" "$2"
}

@test "records the claude process as the agent, not the hook's parent" {
  agent_pid=$(run_under_agent busy '{"session_id":"s1","cwd":"/w"}')

  run jq -r .agent_pid "$status_dir/s1.json"
  [ "$output" = "$agent_pid" ]
}
