#!/usr/bin/env sh
# End-to-end test for ../git-worktree-clean against a throwaway repo. Needs git.
#   sh .local/bin/tests/git-worktree-clean_test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
PATH=$here/..:$PATH
export PATH

tmp=$(mktemp -d)
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home  # isolate from the real git config (signing, hooks)
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }

# A bare origin and a clone of it, with .worktrees/ ignored the way base.nix's
# global gitignore does.
git init -q --bare "$tmp/origin.git"
main=$tmp/main
mkdir "$main" && cd "$main"
git init -q -b main
printf '.worktrees/\nbuild/\n' > .gitignore
git add -A && git commit -qm init
git remote add origin "$tmp/origin.git"
git push -q origin main

wt() { git worktree add -q -b "$1" ".worktrees/$1" main; }
wt done        # on pushed main, clean: finished
wt pushed      # own commit, pushed to origin: finished
wt ignored     # finished, only ignored files on disk
wt dirty       # tracked file modified
wt untracked   # untracked file
wt staged      # staged new file
wt unpushed    # local-only commit
wt locked      # finished but locked
wt gone        # directory deleted behind git's back
git worktree add -q --detach .worktrees/detached main   # detached on pushed commit: finished
git worktree add -q -b elsewhere "$tmp/elsewhere" main  # finished, outside .worktrees

(cd .worktrees/pushed && echo p > p && git add p && git commit -qm p && git push -q origin pushed)
mkdir .worktrees/ignored/build && echo o > .worktrees/ignored/build/o
echo changed >> .worktrees/dirty/.gitignore
echo u > .worktrees/untracked/u
echo s > .worktrees/staged/s && git -C .worktrees/staged add s
(cd .worktrees/unpushed && echo l > l && git add l && git commit -qm local)
git worktree lock .worktrees/locked
rm -rf .worktrees/gone

finished="done pushed ignored detached"
kept="dirty untracked staged unpushed locked"

# Dry run from the main worktree.
out=$(git worktree-clean)
for w in $finished; do
    echo "$out" | grep -q "^would remove $main/.worktrees/$w\$" || fail "dry run should list $w: $out"
done
echo "$out" | grep -q "^would remove $tmp/elsewhere\$" || fail "dry run should list elsewhere: $out"
echo "$out" | grep -q "^would prune $main/.worktrees/gone " || fail "dry run should list gone for pruning: $out"
for w in $kept; do
    echo "$out" | grep -q "/$w\$" && fail "dry run listed unfinished worktree $w: $out"
done
echo "$out" | grep -q "would remove $main\$" && fail "dry run listed the main worktree: $out"
[ -d .worktrees/done ] || fail "dry run must not delete anything"
git worktree list | grep -q '/gone ' || fail "dry run must not prune"
pass "dry run lists only the finished worktrees and changes nothing"

# Apply.
out=$(git worktree-clean -f)
for w in $finished; do
    echo "$out" | grep -q "^removed $main/.worktrees/$w\$" || fail "force should remove $w: $out"
    [ ! -e ".worktrees/$w" ] || fail "force did not delete .worktrees/$w"
done
[ ! -e "$tmp/elsewhere" ] || fail "force did not remove elsewhere"
git worktree list | grep -q '/gone ' && fail "force did not prune gone"
for w in $kept; do
    [ -d ".worktrees/$w" ] || fail "force deleted unfinished worktree $w"
    git worktree list | grep -q "/$w " || fail "force unregistered unfinished worktree $w"
done
[ -f .worktrees/untracked/u ] || fail "untracked file lost"
git rev-parse -q --verify refs/heads/done >/dev/null || fail "the local branch must be kept"
pass "force removes the finished worktrees and keeps the rest"

# Running from inside a finished secondary worktree never removes itself.
wt self
cd "$main/.worktrees/self"
git worktree-clean -f >/dev/null
[ -d "$main/.worktrees/self" ] || fail "the current worktree was removed"
pass "the current worktree is never removed"

# From the main worktree it is fair game; then nothing is left to do.
cd "$main"
git worktree-clean -f | grep -q "^removed $main/.worktrees/self\$" || fail "self should be removed from main"
git worktree-clean | grep -q '^no finished worktrees' || fail "expected 'no finished worktrees'"
pass "reports when there is nothing to remove"
