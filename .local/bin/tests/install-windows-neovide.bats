#!/usr/bin/env bats
# Runs install-windows-neovide against stand-ins for cmd.exe and wslpath, with
# Windows' C: drive at $BATS_TEST_TMPDIR/c.

setup() {
  installer="$BATS_TEST_DIRNAME/../install-windows-neovide"
  c="$BATS_TEST_TMPDIR/c"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin" "$BATS_TEST_TMPDIR/src"
  export WINDOWS_C="$c"
  stub cmd.exe <<'EOF'
case "$*" in
*%APPDATA%*) printf 'C:\\Users\\me\\AppData\\Roaming\r\n' ;;
esac
EOF
  stub wslpath <<'EOF'
[ "$1" = -u ] && path=${2/#C:/$WINDOWS_C} && printf '%s\n' "${path//\\//}"
EOF
  PATH="$bin:$PATH"
  printf 'wsl = true\n' >"$BATS_TEST_TMPDIR/src/config.toml"
  config="$c/Users/me/AppData/Roaming/neovide/config.toml"
}

# Makes <name> a stand-in command running the script on stdin.
stub() {
  { echo '#!/usr/bin/env bash'; cat; } >"$bin/$1"
  chmod +x "$bin/$1"
}

@test "writes the config to %APPDATA%\\neovide\\config.toml" {
  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml"
  [ "$status" -eq 0 ]
  [ "$(cat "$config")" = "wsl = true" ]
}

@test "replaces a config already there" {
  mkdir -p "$(dirname "$config")"
  printf 'old\n' >"$config"

  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml"
  [ "$status" -eq 0 ]
  [ "$(cat "$config")" = "wsl = true" ]
}

@test "without Windows interop it warns and changes nothing" {
  stub cmd.exe <<<'echo "cannot execute binary file: Exec format error" >&2; exit 126'

  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Windows interop unavailable"* ]]
  [ ! -e "$c" ]
}
