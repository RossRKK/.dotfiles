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

# Like run_under_agent, but the agent first starts a stand-in background task
# whose stdout is <output>, as Claude Code's own background Bash is. The fifo
# holds the hook back until the task has opened its output. Echoes the task's
# pid and start time.
run_with_background_task() {
  local task_output=$1 event=$2 payload=$3
  mkfifo "$BATS_TEST_TMPDIR/opened"
  "$agent" -c '
    ( exec >"$0" 3>"$1"; exec sleep 600 3>&- ) &
    read -r <"$1" || true
    echo "$! $(cut -d" " -f22 /proc/$!/stat)"
    sh -c "\"\$0\" \"\$1\"; true" "$2" "$3" <<<"$4"
    kill $!' "$task_output" "$BATS_TEST_TMPDIR/opened" "$hook" "$event" "$payload"
}

background_bash() {
  jq -nc --arg id "$1" '{session_id: "s1", cwd: "/w", tool_name: "Bash",
    tool_input: {command: "cargo test", description: "Run the tests", run_in_background: true},
    tool_response: {backgroundTaskId: $id}}'
}

@test "a backgrounded Bash call records its task: what it is, its pid and its output" {
  task_output="$BATS_TEST_TMPDIR/claude-1000/-w/s1/tasks/b1.output"
  mkdir -p "$(dirname "$task_output")"

  read -r task_pid _ <<<"$(run_with_background_task "$task_output" ran "$(background_bash b1)")"

  run jq -c '{session, id, description, command, output, pid}' "$status_dir/s1.b1.task"
  [ "$output" = "$(jq -nc --arg output "$task_output" \
    --argjson pid "$task_pid" '{session: "s1", id: "b1", description: "Run the tests",
      command: "cargo test", output: $output, pid: $pid}')" ]
}

@test "the task records its pid's start time, so a reused pid isn't mistaken for it" {
  task_output="$BATS_TEST_TMPDIR/s1/tasks/b1.output"
  mkdir -p "$(dirname "$task_output")"

  read -r _ task_start <<<"$(run_with_background_task "$task_output" ran "$(background_bash b1)")"

  run jq -r .pid_start "$status_dir/s1.b1.task"
  [ "$output" = "$task_start" ]
}

@test "a foreground tool call records no task" {
  run_under_agent ran '{"session_id":"s1","cwd":"/w","tool_name":"Bash","tool_response":{"stdout":"hi"}}'

  run jq -r .state "$status_dir/s1.json"
  [ "$output" = busy ]
  [ -z "$(compgen -G "$status_dir/*.task")" ]
}

@test "ending the session removes its tasks and leaves other sessions' alone" {
  mkdir -p "$status_dir"
  touch "$status_dir/s1.b1.task" "$status_dir/s2.b2.task"

  run_under_agent end '{"session_id":"s1","cwd":"/w"}'

  [ ! -e "$status_dir/s1.b1.task" ]
  [ -e "$status_dir/s2.b2.task" ]
}
