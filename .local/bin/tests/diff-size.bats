#!/usr/bin/env bats
# Runs diff-size in a throwaway clone with a stacked branch, against a stand-in
# gh that serves one PR from $gh/body and $gh/base and records any edit.

setup() {
  size="$BATS_TEST_DIRNAME/../diff-size"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  gh="$BATS_TEST_TMPDIR/gh"
  mkdir -p "$gh" "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
"pr view")
  # A lookup by branch name, as the review base makes; off for \$NO_BRANCH_LOOKUP.
  [ "\$3" = --json ] || [ -z "\${NO_BRANCH_LOOKUP-}" ] || exit 1
  [ -f "$gh/body" ] || { echo "no pull requests found" >&2; exit 1; }
  jq -n --rawfile body "$gh/body" --arg base "\$(cat "$gh/base")" \
    '{body: \$body, baseRefName: \$base, state: "OPEN", isCrossRepository: false}' ;;
"pr edit") cat >"$gh/body"; echo edit >>"$gh/edits" ;;
*) exit 2 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  # main <- feature (pushed) <- stacked (checked out).
  git init -q --bare -b main "$BATS_TEST_TMPDIR/origin.git"
  git clone -q "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/repo" 2>/dev/null
  cd "$BATS_TEST_TMPDIR/repo"
  commit README.md "hello"
  git push -q origin main
  git checkout -q -b feature
  commit src/feature.rs "fn a() {}" "fn b() {}"
  git push -q origin feature
  git checkout -q -b stacked
  commit src/stacked.rs "fn c() {}"
  commit src/stacked_test.rs "#[test]"
  commit Cargo.lock "lock"
  printf '\x89PNG\x00\x01' >logo.png
  git add logo.png && git commit -q -m logo
}

# Commits <path> holding the remaining arguments as lines.
commit() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "${@:2}" >"$1"
  git add "$1" && git commit -q -m "$1"
}

# Serves an open PR whose base is <base> and body is <body>.
pr() {
  printf '%s' "$1" >"$gh/base"
  printf '%s' "$2" >"$gh/body"
}

@test "prints the size line and the files by tier between markers" {
  run "$size" origin/feature
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  expected=$(printf '%s\n' \
    '<!-- diff-size -->' \
    '**+2 -0** · 1 code · 1 test · 1 generated' \
    '' \
    '<details><summary>Files by review tier</summary>' \
    '' '**code**' '' '- `logo.png` binary' '- `src/stacked.rs` +1 -0' \
    '' '**test**' '' '- `src/stacked_test.rs` +1 -0' \
    '' '**generated**' '' '- `Cargo.lock` +1 -0' \
    '' '</details>' \
    '<!-- /diff-size -->')
  [ "$output" = "$expected" ] || { diff <(echo "$expected") <(echo "$output"); false; }
}

@test "defaults to the review base: the branch it is stacked on, with no PR" {
  run "$size"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ $output = *'src/stacked.rs'* ]]
  [[ $output != *'src/feature.rs'* ]]
}

@test "defaults to the review base: the open PR's base first" {
  pr main ""
  run "$size"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ $output = *'src/feature.rs'* ]]
  [[ $output = *'src/stacked.rs'* ]]
}

@test "--update-pr measures against the PR's own base on origin, not the review base" {
  # The PR targets main, and with no PR found by branch name the review base is
  # the stack's parent, feature.
  pr main "Intro."
  export NO_BRANCH_LOOKUP=1
  run "$size"
  [[ $output != *'src/feature.rs'* ]]
  run "$size" --update-pr
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF 'src/feature.rs' "$gh/body"
  grep -qF 'src/stacked.rs' "$gh/body"

  # A stale local feature is not the PR's base; origin/feature is.
  pr feature "Intro."
  git branch -q -f feature main
  run "$size" --update-pr
  grep -qF 'src/stacked.rs' "$gh/body"
  [ -z "$(grep -F 'src/feature.rs' "$gh/body")" ]
}

@test "--update-pr appends the section below the description when it has none" {
  pr feature $'My description.\r\n'
  run "$size" --update-pr
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(sed -n 1p "$gh/body")" = "My description." ]
  [ -z "$(sed -n 2p "$gh/body")" ]
  [ "$(tail -n 1 "$gh/body")" = '<!-- /diff-size -->' ]
  [ "$(grep -c 'diff-size -->' "$gh/body")" -eq 2 ]
}

@test "--update-pr replaces only the marked section, and leaves a current one alone" {
  pr feature $'Above.\n\n<!-- diff-size -->\nstale\n<!-- /diff-size -->\n\nBelow.'
  run "$size" --update-pr
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(head -n 1 "$gh/body")" = "Above." ]
  [ "$(tail -n 1 "$gh/body")" = "Below." ]
  [ -z "$(grep -x stale "$gh/body")" ]
  grep -qF 'src/stacked.rs' "$gh/body"
  [ "$(wc -l <"$gh/edits")" -eq 1 ]

  run "$size" --update-pr
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$gh/edits")" -eq 1 ]
}

@test "--update-pr refuses a section opened but never closed, editing nothing" {
  pr feature $'Above.\n<!-- diff-size -->\nstale'
  run "$size" --update-pr
  [ "$status" -eq 1 ]
  [[ $output = *'without closing it'* ]]
  [ ! -e "$gh/edits" ]
}

@test "rejects unknown arguments" {
  run "$size" --update-pr 12
  [ "$status" -eq 1 ]
  [[ $output = *usage* ]]
}
