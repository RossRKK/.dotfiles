#!/usr/bin/env bats
# Runs nvim-open against a stand-in nvim that records the expression it was sent.

setup() {
  open="$BATS_TEST_DIRNAME/../nvim-open"
  export NVIM=/run/nvim.sock
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/repo/src"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/nvim-args"\n' "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/bin/nvim"
  chmod +x "$BATS_TEST_TMPDIR/bin/nvim"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  repo="$BATS_TEST_TMPDIR/repo"
  touch "$repo/src/main.rs" "$repo/a:b.txt"
  cd "$repo"
}

# The argument list nvim-open passed to windows.open.
sent() {
  grep -o '", \[.*\])$' "$BATS_TEST_TMPDIR/nvim-args" | sed 's/^", //; s/)$//'
}

@test "takes a path, line and column apart, the path from the caller's directory" {
  cases=(
    "src/main.rs|[\"$repo/src/main.rs\"]"
    "src/main.rs:12|[\"$repo/src/main.rs\",12]"
    "src/main.rs:12:5|[\"$repo/src/main.rs\",12,5]"
    "$repo/src/main.rs:3|[\"$repo/src/main.rs\",3]"
    "a:b.txt|[\"$repo/a:b.txt\"]"
    "a:b.txt:7|[\"$repo/a:b.txt\",7]"
  )
  for case in "${cases[@]}"; do
    run "$open" "${case%%|*}"
    [ "$status" -eq 0 ] || { echo "$case: $output"; false; }
    [ "$(sent)" = "${case#*|}" ] || { echo "$case: sent $(sent)"; false; }
  done
}

@test "asks nvim to open it through windows.open" {
  run "$open" src/main.rs:1
  grep -qxF -- "--remote-expr" "$BATS_TEST_TMPDIR/nvim-args"
  grep -qF "require('config.windows').open(_A[1], _A[2], _A[3])" "$BATS_TEST_TMPDIR/nvim-args"
}

@test "refuses a file that isn't there, without asking nvim" {
  run "$open" src/missing.rs:4
  [ "$status" -eq 1 ] && [ "$output" = "nvim-open: no such file: $repo/src/missing.rs" ]
  [ ! -e "$BATS_TEST_TMPDIR/nvim-args" ]
}

@test "needs to be inside nvim" {
  unset NVIM
  run "$open" src/main.rs
  [ "$status" -eq 1 ] && [[ $output = *'$NVIM is unset'* ]]
}
