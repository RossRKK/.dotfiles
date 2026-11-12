#!/usr/bin/env bats

setup() {
  recorded="$BATS_TEST_DIRNAME/../hooks/recorded"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/-w"
  transcript="$CLAUDE_CONFIG_DIR/projects/-w/abc.jsonl"
}

@test "the last title and colour in a transcript win" {
  printf '%s\n' \
    '{"type":"custom-title","customTitle":"calm-otter","sessionId":"abc"}' \
    '{"type":"agent-color","agentColor":"red","sessionId":"abc"}' \
    '{"type":"user","message":"hi"}' \
    '{"type":"custom-title","customTitle":"brave-otter","sessionId":"abc"}' \
    '{"type":"agent-color","agentColor":"cyan","sessionId":"abc"}' \
    '{"type":"user","message":"bye"}' >"$transcript"

  run "$recorded" title abc
  [ "$status" -eq 0 ] && [ "$output" = brave-otter ]
  run "$recorded" colour abc
  [ "$status" -eq 0 ] && [ "$output" = cyan ]
}

@test "a transcript with no title or colour fails" {
  printf '%s\n' '{"type":"user","message":"hi"}' >"$transcript"

  run "$recorded" title abc
  [ "$status" -ne 0 ] && [ "$output" = "" ]
  run "$recorded" colour abc
  [ "$status" -ne 0 ] && [ "$output" = "" ]
}

@test "a session with no transcript yet fails" {
  run "$recorded" title abc
  [ "$status" -eq 1 ] && [ "$output" = "" ]
}

@test "another session's transcript is not read" {
  printf '%s\n' '{"type":"custom-title","customTitle":"calm-otter","sessionId":"xyz"}' \
    >"$CLAUDE_CONFIG_DIR/projects/-w/xyz.jsonl"

  run "$recorded" title abc
  [ "$status" -ne 0 ]
}

@test "the transcript is found in whichever project holds it" {
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/-elsewhere"
  printf '%s\n' '{"type":"agent-color","agentColor":"green","sessionId":"abc"}' \
    >"$CLAUDE_CONFIG_DIR/projects/-elsewhere/abc.jsonl"

  run "$recorded" colour abc
  [ "$status" -eq 0 ] && [ "$output" = green ]
}

@test "an unknown record is refused" {
  run "$recorded" model abc
  [ "$status" -eq 2 ]
}
