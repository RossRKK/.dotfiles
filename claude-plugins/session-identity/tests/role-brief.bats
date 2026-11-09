#!/usr/bin/env bats
# Drives the hook as Claude Code does: the SessionStart payload on stdin, with
# a roles file listing one checkout and a stand-in plugin holding its brief.

setup() {
  plugin="$BATS_TEST_TMPDIR/plugin"
  mkdir -p "$plugin/hooks" "$plugin/roles"
  cp "$BATS_TEST_DIRNAME"/../hooks/{role-brief,role-name} "$plugin/hooks/"
  printf '# Overseer\nWatch everything.\n' >"$plugin/roles/overseer.md"
  export HOME="$BATS_TEST_TMPDIR/home" XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$HOME/main" "$HOME/other" "$XDG_CONFIG_HOME"
  printf '%s\n' '~/main overseer' '~/other nobrief' >"$XDG_CONFIG_HOME/claude-roles"
}

# Runs the hook for a session started in <dir>, from terminal <n>.
session_start() {
  jq -nc --arg cwd "$1" '{hook_event_name: "SessionStart", source: "compact", cwd: $cwd}' |
    WORKSPACE_TERMINAL=$2 "$plugin/hooks/role-brief"
}

@test "a role's session is handed its brief as context, even after compaction" {
  run session_start "$HOME/main" 1
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = SessionStart ]
  [ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "$(cat "$plugin/roles/overseer.md")" ]
}

@test "any other terminal of the checkout gets nothing" {
  run session_start "$HOME/main" 2
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "a role with no brief file gets nothing" {
  run session_start "$HOME/other" 1
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "a session outside the listed checkouts gets nothing" {
  run session_start "$BATS_TEST_TMPDIR" 1
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "it finds its own files when run by a relative path" {
  cd "$plugin"
  run bash -c 'jq -nc --arg cwd "$1" "{cwd: \$cwd}" | WORKSPACE_TERMINAL=1 hooks/role-brief' _ "$HOME/main"
  [ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "$(cat "$plugin/roles/overseer.md")" ]
}
