#!/usr/bin/env bats
# Runs install-windows-neovide against stand-ins for cmd.exe, wslpath, fc-scan
# and reg.exe, with Windows' C: drive at $BATS_TEST_TMPDIR/c.

setup() {
  installer="$BATS_TEST_DIRNAME/../install-windows-neovide"
  c="$BATS_TEST_TMPDIR/c"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin" "$BATS_TEST_TMPDIR/src"
  export WINDOWS_C="$c"
  stub cmd.exe <<'EOF'
case "$*" in
*%APPDATA%*) printf 'C:\\Users\\me\\AppData\\Roaming\r\n' ;;
*%LOCALAPPDATA%*) printf 'C:\\Users\\me\\AppData\\Local\r\n' ;;
esac
EOF
  stub wslpath <<'EOF'
case "$1" in
-u) path=${2/#C:/$WINDOWS_C} && printf '%s\n' "${path//\\//}" ;;
-w) path=${2/#"$WINDOWS_C"/C:} && printf '%s\n' "${path//\//\\}" ;;
esac
EOF
  stub fc-scan <<'EOF'
case "$3" in
*.otf) printf '%s|CFF\n' "$(basename "$3" .otf)" ;;
*) printf '%s|TrueType\n' "$(basename "$3" .ttf)" ;;
esac
EOF
  stub reg.exe <<<'printf "%s\n" "$*" >>"$BATS_TEST_TMPDIR/reg"'
  PATH="$bin:$PATH"
  printf 'wsl = true\n' >"$BATS_TEST_TMPDIR/src/config.toml"
  printf 'bold glyphs' >"$BATS_TEST_TMPDIR/src/Mono-Bold.ttf"
  printf 'regular glyphs' >"$BATS_TEST_TMPDIR/src/Mono-Regular.ttf"
  printf 'symbol outlines' >"$BATS_TEST_TMPDIR/src/Symbols.otf"
  fonts="$c/Users/me/AppData/Local/Microsoft/Windows/Fonts"
}

# Makes <name> a stand-in command running the script on stdin.
stub() {
  { echo '#!/usr/bin/env bash'; cat; } >"$bin/$1"
  chmod +x "$bin/$1"
}

@test "writes the config to %APPDATA%\\neovide\\config.toml" {
  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml"
  [ "$status" -eq 0 ]
  [ "$(cat "$c/Users/me/AppData/Roaming/neovide/config.toml")" = "wsl = true" ]
}

@test "copies each font into the per-user fonts and registers it by full name" {
  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml" \
    "$BATS_TEST_TMPDIR/src/Mono-Bold.ttf" "$BATS_TEST_TMPDIR/src/Mono-Regular.ttf"
  [ "$status" -eq 0 ]
  [ "$(cat "$fonts/Mono-Bold.ttf")" = "bold glyphs" ]
  [ "$(cat "$fonts/Mono-Regular.ttf")" = "regular glyphs" ]
  [ "$(cat "$BATS_TEST_TMPDIR/reg")" = "\
add HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts /v Mono-Bold (TrueType) /t REG_SZ /d C:\\Users\\me\\AppData\\Local\\Microsoft\\Windows\\Fonts\\Mono-Bold.ttf /f
add HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts /v Mono-Regular (TrueType) /t REG_SZ /d C:\\Users\\me\\AppData\\Local\\Microsoft\\Windows\\Fonts\\Mono-Regular.ttf /f" ]
}

@test "a font already installed isn't rewritten, so one in use doesn't stop the switch" {
  mkdir -p "$fonts"
  cp "$BATS_TEST_TMPDIR/src/Mono-Bold.ttf" "$fonts/"
  chmod a-w "$fonts/Mono-Bold.ttf" "$fonts"

  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml" "$BATS_TEST_TMPDIR/src/Mono-Bold.ttf"
  chmod u+w "$fonts"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  grep -qF '/v Mono-Bold (TrueType)' "$BATS_TEST_TMPDIR/reg"
}

@test "a changed font that can't be replaced is kept with a warning, and the rest still register" {
  mkdir -p "$fonts"
  printf 'old glyphs' >"$fonts/Mono-Bold.ttf"
  cp "$BATS_TEST_TMPDIR/src/Mono-Regular.ttf" "$fonts/"
  chmod a-w "$fonts"

  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml" \
    "$BATS_TEST_TMPDIR/src/Mono-Bold.ttf" "$BATS_TEST_TMPDIR/src/Mono-Regular.ttf"
  chmod u+w "$fonts"
  [ "$status" -eq 0 ]
  [[ "$output" == *"couldn't replace $fonts/Mono-Bold.ttf"* ]]
  [ "$(cat "$fonts/Mono-Bold.ttf")" = "old glyphs" ]
  grep -qF '/v Mono-Regular (TrueType)' "$BATS_TEST_TMPDIR/reg"
}

@test "without Windows interop it warns and changes nothing" {
  stub cmd.exe <<<'echo "cannot execute binary file: Exec format error" >&2; exit 126'

  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml" "$BATS_TEST_TMPDIR/src/Mono-Bold.ttf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Windows interop unavailable"* ]]
  [ ! -e "$c" ] && [ ! -e "$BATS_TEST_TMPDIR/reg" ]
}

@test "a CFF font registers as OpenType, as Windows' installer names it" {
  run "$installer" "$BATS_TEST_TMPDIR/src/config.toml" "$BATS_TEST_TMPDIR/src/Symbols.otf"
  [ "$status" -eq 0 ]
  [ "$(cat "$fonts/Symbols.otf")" = "symbol outlines" ]
  grep -qF '/v Symbols (OpenType) /t REG_SZ /d C:\Users\me\AppData\Local\Microsoft\Windows\Fonts\Symbols.otf' "$BATS_TEST_TMPDIR/reg"
}
