#!/usr/bin/env bats
# Drives the hook as Claude Code does: the SessionStart payload on stdin.

setup() {
  hook="$BATS_TEST_DIRNAME/../hooks/big-cheese"
}

# Runs the hook for a session titled <title> (none when omitted).
session_start() {
  jq -nc --arg title "${1-}" '{hook_event_name: "SessionStart", source: "startup", cwd: "/w"}
    + if $title == "" then {} else {session_title: $title} end' | "$hook"
}

@test "the session named big-cheese is told to load its skill" {
  run session_start big-cheese

  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = SessionStart ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == *big-cheese:big-cheese* ]]
}

@test "any other session gets nothing" {
  run session_start dotty

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unnamed session gets nothing" {
  run session_start

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
