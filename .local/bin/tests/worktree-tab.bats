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
  export ANSWER="{\"path\":\"$wt\"}"
  cd "$BATS_TEST_TMPDIR/repo"
}

# Registers a session <name> in <dir> run by <pid>, started at <ms>, reachable
# unless "nosocket"; $SOURCE is how it got its name (the mod's /rename by default)
# and $PROC_START when <pid> started (by default, when it really did).
session() {
  local socket='"/run/s.sock"' start
  [ "${5-}" != nosocket ] || socket=null
  start=${PROC_START:-$(proc_start "$3")}
  printf '{"pid":%s,"procStart":"%s","name":"%s","nameSource":"%s","cwd":"%s","startedAt":%s,"messagingSocketPath":%s}\n' \
    "$3" "$start" "$1" "${SOURCE:-user}" "$2" "$4" "$socket" >"$sessions/$3.json"
}

proc_start() {
  local stat
  stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 0
  stat=${stat##*) }
  cut -d' ' -f20 <<<"$stat"
}

@test "prints the name of the Claude in the worktree once it can be messaged" {
  session swift-otter "$wt" $$ 100

  run "$tab" --timeout 0 feat/x
  [ "$status" -eq 0 ] && [ "$output" = swift-otter ]
}

@test "of several Claudes in the worktree, the earliest started is terminal 1's" {
  sleep 600 &
  session later-one "$wt" $! 200
  session first-one "$wt" $$ 100

  run "$tab" --timeout 0 feat/x
  kill $!
  [ "$status" -eq 0 ] && [ "$output" = first-one ]
}

@test "asks nvim to open the branch from here, quoting both safely" {
  session swift-otter "$wt" $$ 100

  run "$tab" --timeout 0 "it's \"x\""
  grep -qF "[\"it's \\\"x\\\"\", \"$BATS_TEST_TMPDIR/repo\"]" "$BATS_TEST_TMPDIR/nvim-args"
}

@test "a session that is dead, elsewhere, or not yet listening doesn't count" {
  session dead-one "$wt" 999999999 1
  session elsewhere "$BATS_TEST_TMPDIR/repo" $$ 1
  sleep 600 &
  session deaf-one "$wt" $! 1 nosocket

  run "$tab" --timeout 0 feat/x
  kill $!
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude started in $wt"* ]]
}

@test "a crashed session whose pid now belongs to another process doesn't count" {
  PROC_START=1 session ghost "$wt" $$ 100

  run "$tab" --timeout 0 feat/x
  [ "$status" -eq 1 ]
}

@test "a session still on the name Claude derived isn't printed before the rename lands" {
  SOURCE=derived session feat-x-3f "$wt" $$ 100

  run "$tab" --timeout 0 feat/x
  [ "$status" -eq 1 ]
}

@test "a name the rename suffixed because it was taken still counts" {
  SOURCE=collision session swift-otter-2 "$wt" $$ 100

  run "$tab" --timeout 0 feat/x
  [ "$status" -eq 0 ] && [ "$output" = swift-otter-2 ]
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
