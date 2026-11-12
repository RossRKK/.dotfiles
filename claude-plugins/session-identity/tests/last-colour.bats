#!/usr/bin/env bats

setup() {
  last="$BATS_TEST_DIRNAME/../hooks/last-colour"
  transcript="$BATS_TEST_TMPDIR/session.jsonl"
}

@test "the last /color in a transcript wins" {
  printf '%s\n' \
    '{"type":"agent-color","agentColor":"red","sessionId":"abc"}' \
    '{"type":"user","message":"hi"}' \
    '{"type":"agent-color","agentColor":"cyan","sessionId":"abc"}' \
    '{"type":"user","message":"bye"}' >"$transcript"

  run "$last" "$transcript"
  [ "$status" -eq 0 ] && [ "$output" = cyan ]
}

@test "a transcript with no /color fails" {
  printf '%s\n' '{"type":"user","message":"hi"}' >"$transcript"

  run "$last" "$transcript"
  [ "$status" -ne 0 ] && [ "$output" = "" ]
}

@test "a transcript that is not there yet fails" {
  run "$last" "$transcript"
  [ "$status" -ne 0 ]
}
