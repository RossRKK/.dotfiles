#!/usr/bin/env bats
# Each case runs on both sources: /proc's, and ps's (macOS's), forced here where /proc exists.

setup() {
  export LIB="$BATS_TEST_DIRNAME/../process"
  agent="$BATS_TEST_TMPDIR/.claude-unwrapped"
  ln -s "$(command -v bash)" "$agent"
  # Prints the ancestry of the process that runs it.
  ancestry="$BATS_TEST_TMPDIR/ancestry"
  printf '#!/usr/bin/env bash\n. "$LIB" && process_ancestry "$PPID"\n' >"$ancestry"
  chmod +x "$ancestry"
}

# Runs <query> <args> with the helper loaded.
query() {
  bash -c '. "$LIB" && "$@"' _ "$@"
}

# Starts a process whose stdout is <file> (its pid in $!), returning once it has opened it.
start_writing_to() {
  mkfifo "$BATS_TEST_TMPDIR/opened"
  ( exec >"$1" 3>"$BATS_TEST_TMPDIR/opened"; exec sleep 600 3>&- ) &
  read -r <"$BATS_TEST_TMPDIR/opened" || true
}

ancestry_names_the_chain_up_to_the_claude_above() {
  export PROCESS_SOURCE=$1
  # `; true` keeps each shell from exec'ing its last command, which would drop it from the chain.
  run "$agent" -c 'echo $$; sh -c "\"\$0\"; true" "$0"; true' "$ancestry"
  [ "$status" -eq 0 ]
  read -r _ sh_name <<<"${lines[1]}"
  read -r agent_pid agent_name <<<"${lines[2]}"
  [ "$sh_name" = sh ]
  [ "$agent_pid" = "${lines[0]}" ]
  query is_claude "$agent_name"
  printf '%s\n' "${lines[@]}" | grep -q "^$$ "
}

ancestry_keeps_a_name_with_spaces_whole() {
  export PROCESS_SOURCE=$1
  ln -s "$(command -v bash)" "$BATS_TEST_TMPDIR/my agent"
  run "$BATS_TEST_TMPDIR/my agent" -c '"$0"; true' "$ancestry"
  [ "${lines[0]#* }" = "my agent" ]
}

started_is_a_number_fixed_for_the_process() {
  export PROCESS_SOURCE=$1
  local pid first
  sleep 600 &
  pid=$!
  first=$(query process_started "$pid")
  run query process_started "$pid"
  kill "$pid"
  [[ $first =~ ^[0-9]+$ ]]
  [ "$output" = "$first" ]
}

# The independent reading: /proc's field 22, or GNU date's parse of ps's lstart.
started_matches_the_kernels_record() {
  export PROCESS_SOURCE=$1
  local pid expected
  sleep 600 &
  pid=$!
  case $1 in
  proc) expected=$(cut -d' ' -f22 "/proc/$pid/stat") ;;
  ps) expected=$(date -u -d "$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$pid")" +%Y%m%d%H%M%S) ;;
  esac
  run query process_started "$pid"
  kill "$pid"
  [ "$output" = "$expected" ]
}

started_is_empty_once_the_process_has_gone() {
  export PROCESS_SOURCE=$1
  run query process_started 999999999
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

outputs_lists_each_childs_stdout() {
  export PROCESS_SOURCE=$1
  local file="$BATS_TEST_TMPDIR/task output" child
  start_writing_to "$file"
  child=$!
  run query process_outputs "$BASHPID"
  kill "$child"
  printf '%s\n' "${lines[@]}" | grep -qxF "$child $file"
}

outputs_is_empty_for_a_process_without_children() {
  export PROCESS_SOURCE=$1
  run query process_outputs 999999999
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

for source in proc ps; do
  bats_test_function --description "$source: ancestry names the chain up to the claude above" -- ancestry_names_the_chain_up_to_the_claude_above "$source"
  bats_test_function --description "$source: ancestry keeps a name with spaces whole" -- ancestry_keeps_a_name_with_spaces_whole "$source"
  bats_test_function --description "$source: start time is a number fixed for the process" -- started_is_a_number_fixed_for_the_process "$source"
  bats_test_function --description "$source: start time matches the kernel's record" -- started_matches_the_kernels_record "$source"
  bats_test_function --description "$source: start time is empty once the process has gone" -- started_is_empty_once_the_process_has_gone "$source"
  bats_test_function --description "$source: outputs lists each child's stdout" -- outputs_lists_each_childs_stdout "$source"
  bats_test_function --description "$source: outputs is empty for a process without children" -- outputs_is_empty_for_a_process_without_children "$source"
done

@test "an unknown source is refused" {
  PROCESS_SOURCE=cgroup run query process_started $$
  [ "$status" -eq 2 ]
  [[ $output == *"must be proc or ps"* ]]
}
