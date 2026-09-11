#!/usr/bin/env sh
# End-to-end test for ../jj-lfs against a throwaway repo. Needs jj, git, git-lfs.
#   sh .local/bin/tests/jj-lfs_test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
PATH=$here/..:$PATH
export PATH

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home  # isolate from the real jj/git config (signing, hooks)
mkdir -p "$HOME"
export JJ_USER=t JJ_EMAIL=t@t GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
       GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }

# Main checkout: a git repo with one LFS file, then colocated jj on top.
main=$tmp/main
mkdir "$main" && cd "$main"
git init -q
git lfs install --local >/dev/null
git lfs track '*.bin' >/dev/null
head -c 3000 /dev/urandom > big.bin
echo text > plain.txt
git add -A && git commit -qm lfs
jj git init --colocate >/dev/null 2>&1

# Secondary workspace: no .git, pointer text on disk.
jj workspace add "$tmp/ws" >/dev/null 2>&1
cd "$tmp/ws"
[ ! -e .git ] || fail "workspace unexpectedly has .git"
grep -q '^version https://git-lfs' big.bin || fail "workspace should start with a pointer"

jj-lfs pull 2>/dev/null
cmp -s big.bin "$main/big.bin" || fail "pull did not restore the LFS content"
jj status | grep -q '^M big.bin' || fail "jj should report the smudged file as M"
pass "pull replaces the pointer with content in a secondary workspace"

jj-lfs clean 2>/dev/null
grep -q '^version https://git-lfs' big.bin || fail "clean did not restore the pointer"
jj status | grep -q 'no changes' || fail "jj status should be clean after clean"
pass "clean restores the pointer and jj status is clean"

jj-lfs pull 2>/dev/null
head -c 10 /dev/urandom > big.bin
jj-lfs clean 2>/dev/null
grep -q '^version https://git-lfs' big.bin && fail "clean must not revert a real content change"
pass "clean keeps a file whose content no longer matches the pointer"

# Same commands work in the main (colocated) checkout.
cd "$main"
jj-lfs clean 2>/dev/null   # nothing to do, must not error
jj-lfs pull 2>/dev/null
cmp -s big.bin "$tmp/ws/big.bin" 2>/dev/null && fail "unexpected: ws and main equal after ws edit"
jj-lfs clean 2>/dev/null
grep -q '^version https://git-lfs' big.bin || fail "clean failed in main checkout"
pass "pull and clean run in the main checkout"

echo "all tests passed"
