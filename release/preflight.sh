#!/usr/bin/env bash
# The release checks. Prints one "STOP:" line for each check that fails and
# exits 1 if any fail. Repairs nothing; the only change it makes is a
# `git fetch` of the default branch.
#
# Usage: preflight.sh   (from anywhere inside the repository)

set -u
failed=0
stop() { echo "STOP: $*"; failed=1; }

top=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "STOP: not inside a git repository."
    exit 1
}
cd "$top" || exit 1

for file in Cargo.toml release.toml cliff.toml; do
    [ -f "$file" ] || stop "$file is missing in $top. This repository is not set up for releases."
done
for tool in cargo-release git-cliff gh; do
    command -v "$tool" >/dev/null || stop "$tool is not installed."
done

# 1. The main checkout, on the default branch.
# In a worktree the git directory is not the common one.
git_dir=$(cd "$(git rev-parse --git-dir)" && pwd -P)
common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
if [ "$git_dir" != "$common_dir" ]; then
    main_checkout=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
    stop "this is a worktree. Run the release from the main checkout: $main_checkout"
fi
default=$(git symbolic-ref --short -q refs/remotes/origin/HEAD | sed 's#^origin/##')
default=${default:-main}
branch=$(git symbolic-ref --short -q HEAD)
[ "$branch" = "$default" ] || stop "HEAD is on ${branch:-a detached commit}, not on $default."

# 2. A clean tree. Untracked files count: the release commit must contain
# only what the release changes.
if [ -n "$(git status --porcelain)" ]; then
    stop "the tree has changes that are not committed, or untracked files:"
    git status --short | sed 's/^/      /'
fi

# 3. The same commit as origin, after a fetch.
if git fetch -q origin "$default" 2>/dev/null; then
    read -r behind ahead < <(git rev-list --left-right --count "origin/$default...HEAD")
    if [ "$ahead" != 0 ] || [ "$behind" != 0 ]; then
        stop "$default is $ahead commit(s) ahead of and $behind behind origin/$default. Push or pull first."
    fi
else
    stop "cannot fetch origin/$default."
fi

# 4. CI passed for HEAD: every workflow run for this commit is complete and
# successful.
head=$(git rev-parse HEAD)
if runs=$(gh run list --commit "$head" --json status,conclusion,url \
    --jq '.[] | "\(.status) \(.conclusion) \(.url)"' 2>&1); then
    if [ -z "$runs" ]; then
        stop "no CI run exists for HEAD ($(git rev-parse --short HEAD))."
    else
        while read -r status conclusion url; do
            if [ "$status" != completed ]; then
                stop "CI for HEAD is still running: $url"
            elif [ "$conclusion" != success ]; then
                stop "CI for HEAD did not pass ($conclusion): $url"
            fi
        done <<<"$runs"
    fi
else
    stop "cannot read the CI runs for HEAD: $runs"
fi

[ "$failed" = 0 ] && echo "OK: all release checks passed."
exit "$failed"
