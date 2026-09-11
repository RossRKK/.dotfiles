#!/usr/bin/env sh
# End-to-end test for ../jj-workspace-clean against a throwaway repo. Needs jj, git.
#   sh .local/bin/tests/jj-workspace-clean_test.sh
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

# A bare origin and a colocated jj clone of it, with .worktrees/ ignored the
# way base.nix's global gitignore does.
git init -q --bare "$tmp/origin.git"
main=$tmp/main
mkdir "$main" && cd "$main"
git init -q -b main
printf '.worktrees/\n' > .gitignore
git add -A && git commit -qm init
git remote add origin "$tmp/origin.git"
git push -q origin main
jj git init --colocate >/dev/null 2>&1
jj bookmark track main@origin >/dev/null 2>&1

# Secondary workspaces under .worktrees/<name>, named for the slug.
ws() { mkdir -p "$main/.worktrees/$1"; jj workspace add --name "$1" "$main/.worktrees/$1" >/dev/null 2>&1; }
ws done       # empty @ on pushed main: finished
ws dirty      # has a file change
ws described  # empty @ but with a description
ws unpushed   # empty @ on a local-only commit
ws elsewhere  # finished, but its directory is not under .worktrees
mv "$main/.worktrees/elsewhere" "$tmp/elsewhere"

echo x > "$main/.worktrees/dirty/x"
(cd "$main/.worktrees/dirty" && jj status >/dev/null)   # snapshot the change
(cd "$main/.worktrees/described" && jj describe -m wip >/dev/null 2>&1)
(cd "$main/.worktrees/unpushed" && jj commit -m local >/dev/null 2>&1)

# Dry run from the main workspace.
cd "$main"
out=$(jj-workspace-clean)
echo "$out" | grep -q '^would remove done ' || fail "dry run should list 'done': $out"
echo "$out" | grep -q '^would remove elsewhere .*forget only' || fail "dry run should list 'elsewhere' as forget only: $out"
echo "$out" | grep -qE 'remove (dirty|described|unpushed) ' && fail "dry run listed an unfinished workspace: $out"
[ -d .worktrees/done ] || fail "dry run must not delete anything"
jj workspace list | grep -q '^done:' || fail "dry run must not forget anything"
pass "dry run lists only the finished workspaces and changes nothing"

# Apply.
out=$(jj-workspace-clean -f)
echo "$out" | grep -q '^removed done ' || fail "force should remove 'done': $out"
[ ! -e .worktrees/done ] || fail "force did not delete .worktrees/done"
jj workspace list | grep -q '^done:' && fail "force did not forget 'done'"
jj workspace list | grep -q '^elsewhere:' && fail "force did not forget 'elsewhere'"
[ -d "$tmp/elsewhere" ] || fail "force must not delete a directory outside .worktrees"
for keep in dirty described unpushed; do
    jj workspace list | grep -q "^$keep:" || fail "force removed unfinished workspace $keep"
    [ -d ".worktrees/$keep" ] || fail "force deleted .worktrees/$keep"
done
pass "force removes the finished workspaces and keeps the rest"

# Running from inside a finished secondary workspace never removes itself.
ws self
cd "$main/.worktrees/self"
out=$(jj-workspace-clean -f)
jj workspace list | grep -q '^self:' || fail "the current workspace was forgotten: $out"
pass "the current workspace is never removed"

# From the main workspace that same workspace is fair game; then nothing is left.
cd "$main"
jj-workspace-clean -f | grep -q '^removed self ' || fail "'self' should be removed from main"
jj-workspace-clean | grep -q '^no finished workspaces' || fail "expected 'no finished workspaces'"
pass "reports when there is nothing to remove"
