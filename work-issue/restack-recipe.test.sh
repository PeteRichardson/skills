#!/usr/bin/env bash
# Verifies the restack recipe used by `/work-issue restack`.
#
# The recipe replays only the CHILD's commits onto the target, using the parent
# head sha recorded in the child PR's <!-- work-issue-stack --> marker:
#
#     git rebase --onto <target> <recorded parent head> <child branch>
#
# Scenarios 1-3 prove it works under every GitHub merge mode. Scenario 4 is a
# negative control proving the naive alternative does NOT, which is the entire
# reason the marker records a sha. See
# docs/specs/2026-07-30-stacked-prs-design.md ("Evidence").
set -uo pipefail

PASSES=0; FAILURES=0
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

# base -> parent (TWO commits, the second revising the first) -> child (one
# commit, a different line). Two parent commits is what breaks naive rebasing;
# a /work-issue PR gets a second commit as soon as review asks for a change.
build() {
  local d="$ROOT/$1"
  mkdir -p "$d"; cd "$d" || exit 1
  git init -q -b main .
  git config user.email test@example.com; git config user.name Test
  printf 'line1\nline2\nline3\nline4\nline5\n' > f.txt
  git add -A; git commit -qm "base"
  git checkout -qb parent
  sed -i.bak 's/line2/line2-parent-attempt1/' f.txt; rm -f f.txt.bak
  git commit -qam "parent attempt 1"
  sed -i.bak 's/line2-parent-attempt1/line2-parent-final/' f.txt; rm -f f.txt.bak
  git commit -qam "parent attempt 2"
  PARENT_HEAD=$(git rev-parse HEAD)   # the value the PR-body marker records
  git checkout -qb child
  sed -i.bak 's/line4/line4-child/' f.txt; rm -f f.txt.bak
  git commit -qam "child fix"
  git checkout -q main
}

ok()  { PASSES=$((PASSES+1));   printf '  ok    %s\n' "$1"; }
bad() { FAILURES=$((FAILURES+1)); printf '  FAIL  %s\n' "$1"; }

# A correct restack leaves exactly one commit ahead of main and both fixes in the file.
assert_restacked() {
  local label=$1 n content
  n=$(git log --oneline main..child | wc -l | tr -d ' ')
  content=$(cat f.txt)
  if [ "$n" != "1" ]; then
    bad "$label: expected 1 commit ahead of main, got $n"; return
  fi
  case "$content" in
    *line2-parent-final*) : ;;
    *) bad "$label: parent's fix missing from working tree"; return ;;
  esac
  case "$content" in
    *line4-child*) : ;;
    *) bad "$label: child's fix missing from working tree"; return ;;
  esac
  ok "$label"
}

echo "restack recipe"

# --- Scenario 1: parent squash-merged ---------------------------------------
build squash
git merge --squash parent >/dev/null 2>&1 && git commit -qm "squashed parent (#68)"
git checkout -q child
if git rebase --onto main "$PARENT_HEAD" child >/dev/null 2>&1; then
  assert_restacked "squash-merged parent"
else
  git rebase --abort >/dev/null 2>&1; bad "squash-merged parent: rebase conflicted"
fi

# --- Scenario 2: parent rebase-merged (commits replayed with NEW shas) -------
# main must move first, otherwise the replay reproduces identical shas and the
# scenario is degenerate.
build rebase
printf 'from another PR\n' > other.txt; git add -A; git commit -qm "unrelated PR merged"
git cherry-pick "$PARENT_HEAD~1" "$PARENT_HEAD" >/dev/null 2>&1
if [ "$(git rev-parse HEAD)" = "$PARENT_HEAD" ]; then
  bad "rebase-merged parent: setup degenerate, shas did not change"
else
  git checkout -q child
  if git rebase --onto main "$PARENT_HEAD" child >/dev/null 2>&1; then
    assert_restacked "rebase-merged parent"
  else
    git rebase --abort >/dev/null 2>&1; bad "rebase-merged parent: rebase conflicted"
  fi
fi

# --- Scenario 3: parent merged with a merge commit --------------------------
build mergecommit
git merge -q --no-ff parent -m "merge parent (#68)"
git checkout -q child
if git rebase --onto main "$PARENT_HEAD" child >/dev/null 2>&1; then
  assert_restacked "merge-commit parent"
else
  git rebase --abort >/dev/null 2>&1; bad "merge-commit parent: rebase conflicted"
fi

# --- Scenario 4: NEGATIVE CONTROL -------------------------------------------
# Naive `git rebase main child` with a squash-merged multi-commit parent must
# CONFLICT. If this ever starts passing, the marker's sha is no longer load
# bearing and the design can be simplified -- but verify that deliberately.
build naive
git merge --squash parent >/dev/null 2>&1 && git commit -qm "squashed parent (#68)"
git checkout -q child
if git rebase main >/dev/null 2>&1; then
  bad "negative control: naive rebase unexpectedly succeeded (recipe may be unnecessary)"
else
  git rebase --abort >/dev/null 2>&1
  ok "negative control: naive rebase conflicts, as expected"
fi

printf '\n%d passed, %d failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
