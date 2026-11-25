#!/usr/bin/env bats
# Runs nvim-qf against a real headless nvim serving this config's config.quickfix, started in a throwaway repo.

setup() {
  qf="$BATS_TEST_DIRNAME/../nvim-qf"
  config="$BATS_TEST_DIRNAME/../../../.config/nvim"
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/src"
  printf 'one\ntwo\nthree\n' >"$repo/src/main.rs"
  cd "$repo"
}

teardown() {
  [ -z "${server_pid-}" ] || kill "$server_pid" 2>/dev/null || true
}

# A headless nvim listening on $NVIM, returning once it has started; with no argument it loads config.quickfix.
start_nvim() {
  local init=${1-"set rtp^=$config | lua require('config.quickfix').setup()"}
  export NVIM="$BATS_TEST_TMPDIR/nvim.sock"
  mkfifo "$BATS_TEST_TMPDIR/ready"
  nvim --clean --headless --listen "$NVIM" -c "$init" \
    -c "call writefile(['up'], '$BATS_TEST_TMPDIR/ready')" &
  server_pid=$!
  read -r _ <"$BATS_TEST_TMPDIR/ready"
}

@test "sets a titled list from path:line[:col]: note lines, paths from the caller's directory" {
  start_nvim
  printf 'src/main.rs:2: why it matters\n\nsrc/main.rs:3:4: and the column\n' | "$qf" set "Ross's walk"

  run "$qf" state
  [ "$status" -eq 0 ]
  [ "$(jq -r .title <<<"$output")" = "Ross's walk" ]
  [ "$(jq -c '[.entries[] | [.path, .line, .text]]' <<<"$output")" = '[["src/main.rs",2,"why it matters"],["src/main.rs",3,"and the column"]]' ]
  [ "$(jq -c '[.current, .visited]' <<<"$output")" = '[1,[]]' ]
}

@test "states null for an empty list" {
  start_nvim
  run "$qf" state
  [ "$status" -eq 0 ] && [ "$output" = null ]
}

@test "reports nvim's error when it lacks config.quickfix" {
  start_nvim ""
  run "$qf" state
  [ "$status" -eq 1 ] && [[ $output = "nvim-qf: nvim refused: "*"config.quickfix"* ]]
}

@test "refuses a line that is not path:line: note, without asking nvim" {
  export NVIM=/nonexistent.sock
  run "$qf" set walk <<<"src/main.rs is interesting"
  [ "$status" -eq 1 ] && [ "$output" = 'nvim-qf: line 1 is not `path:line[:col]: note`: src/main.rs is interesting' ]
}

@test "refuses a file that isn't there" {
  export NVIM=/nonexistent.sock
  run "$qf" set walk <<<"src/missing.rs:4: gone"
  [ "$status" -eq 1 ] && [ "$output" = "nvim-qf: no such file: $repo/src/missing.rs" ]
}

@test "needs to be inside nvim" {
  unset NVIM
  run "$qf" state
  [ "$status" -eq 1 ] && [[ $output = *'$NVIM is unset'* ]]
}
