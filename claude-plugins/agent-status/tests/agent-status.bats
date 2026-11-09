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

# A transcript whose last assistant message is <text>.
transcript_ending() {
  jq -nc --arg text "$1" '{type: "assistant", message: {content: [{type: "text", text: $text}]}}' \
    >"$BATS_TEST_TMPDIR/t.jsonl"
  echo "$BATS_TEST_TMPDIR/t.jsonl"
}

@test "a session that has run no turn yet is new" {
  run_under_agent start '{"session_id":"s1","cwd":"/w","source":"startup"}'

  run jq -r .state "$status_dir/s1.json"
  [ "$output" = new ]
}

@test "clearing a session makes it new again" {
  run_under_agent stop '{"session_id":"s1","cwd":"/w"}'
  run_under_agent start '{"session_id":"s1","cwd":"/w","source":"clear"}'

  run jq -r .state "$status_dir/s1.json"
  [ "$output" = new ]
}

@test "a compaction mid-turn leaves the session busy, not new" {
  run_under_agent busy '{"session_id":"s1","cwd":"/w","prompt":"go"}'
  run_under_agent start '{"session_id":"s1","cwd":"/w","source":"compact"}'

  run jq -r .state "$status_dir/s1.json"
  [ "$output" = busy ]
}

@test "while busy, detail is the prompt's first line" {
  run_under_agent busy '{"session_id":"s1","cwd":"/w","prompt":"\n  fix the flaky test\nand more"}'

  run jq -r .detail "$status_dir/s1.json"
  [ "$output" = "  fix the flaky test" ]
}

@test "a tool starting makes detail the tool and what it is for" {
  run_under_agent tool '{"session_id":"s1","cwd":"/w","tool_name":"Bash","tool_input":{"command":"make","description":"Run the build"}}'

  run jq -c '{state, detail}' "$status_dir/s1.json"
  [ "$output" = '{"state":"busy","detail":"Bash: Run the build"}' ]
}

@test "a tool with no describing input is shown by name alone" {
  run_under_agent tool '{"session_id":"s1","cwd":"/w","tool_name":"TodoWrite","tool_input":{"todos":[]}}'

  run jq -r .detail "$status_dir/s1.json"
  [ "$output" = TodoWrite ]
}

@test "a tool starting while another waits for permission leaves it waiting" {
  run_under_agent notify '{"session_id":"s1","cwd":"/w","message":"Claude needs your permission to use Bash"}'
  run_under_agent tool '{"session_id":"s1","cwd":"/w","tool_name":"Read","tool_input":{"file_path":"/w/a"}}'

  run jq -r .state "$status_dir/s1.json"
  [ "$output" = permission ]
}

@test "at stop, summary is the answer's opening line without markdown" {
  transcript=$(transcript_ending $'## Fixed the flaky test\n\nDetails follow. Shall I push?')
  run_under_agent stop "$(jq -nc --arg t "$transcript" '{session_id: "s1", cwd: "/w", transcript_path: $t}')"

  run jq -c '{state, summary}' "$status_dir/s1.json"
  [ "$output" = '{"state":"asked","summary":"Fixed the flaky test"}' ]
}

@test "every write carries every field" {
  run_under_agent start '{"session_id":"s1","cwd":"/w","source":"startup"}'

  run jq -c 'keys' "$status_dir/s1.json"
  [ "$output" = '["agent_pid","cwd","detail","pids","session","state","summary","transcript"]' ]
}
