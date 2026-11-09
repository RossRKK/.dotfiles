#!/usr/bin/env bats
# Runs worktree-tab against a stand-in nvim that records its arguments and
# answers with $ANSWER, and a session registry the tests write.

setup() {
  tab="$BATS_TEST_DIRNAME/../worktree-tab"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config" NVIM=/run/nvim.sock
  sessions="$CLAUDE_CONFIG_DIR/sessions"
  mkdir -p "$sessions" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/repo/.worktrees/feat-x"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/nvim-args"\nprintf "%%s" "$ANSWER"\n' \
    "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/bin/nvim"
  chmod +x "$BATS_TEST_TMPDIR/bin/nvim"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  wt="$BATS_TEST_TMPDIR/repo/.worktrees/feat-x"
  export ANSWER="{\"agent\":\"feat-x\",\"path\":\"$wt\"}"
  cd "$BATS_TEST_TMPDIR/repo"
}

# Registers a session <name> in <dir> run by <pid>, reachable unless "nosocket".
session() {
  local socket='"/run/s.sock"'
  [ "${4-}" != nosocket ] || socket=null
  printf '{"pid":%s,"name":"%s","cwd":"%s","messagingSocketPath":%s}\n' \
    "$3" "$1" "$2" "$socket" >"$sessions/$3.json"
}

@test "prints the tab's agent once it can be messaged" {
  session feat-x "$wt" $$

  run "$tab" --timeout 0 feat/x
  [ "$status" -eq 0 ] && [ "$output" = feat-x ]
}

@test "asks nvim to open the branch from here, quoting both safely" {
  session feat-x "$wt" $$

  run "$tab" --timeout 0 "it's \"x\""
  grep -qF "[\"it's \\\"x\\\"\", \"$BATS_TEST_TMPDIR/repo\"]" "$BATS_TEST_TMPDIR/nvim-args"
}

@test "a session that is dead, elsewhere, or not yet listening doesn't count" {
  session feat-x "$wt" 999999999
  session feat-x "$BATS_TEST_TMPDIR/repo" $$
  sleep 600 &
  session feat-x "$wt" $! nosocket

  run "$tab" --timeout 0 feat/x
  kill $!
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude named feat-x started in $wt"* ]]
}

@test "nvim's error is passed on" {
  ANSWER='{"error":"not a git repository"}' run "$tab" feat/x
  [ "$status" -eq 1 ] && [ "$output" = "worktree-tab: not a git repository" ]
}

@test "outside nvim it refuses rather than guessing a server" {
  NVIM= run "$tab" feat/x
  [ "$status" -eq 1 ] && [[ "$output" == *'$NVIM is unset'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/nvim-args" ]
}
