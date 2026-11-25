#!/usr/bin/env bash
# The pull requests of a release, as GitHub records them. One line for each:
#
#   IN      #n title    merged, and its merge commit is in from..to
#   OPEN    #n title    open against the default branch: not in the release
#   UNKNOWN #n title    merged, but its merge commit is not in this clone
#
# The release skill quotes these lines. It never states the state of a pull
# request from memory: a PR that is open in one session can be merged before
# the next.
#
# Usage: prs.sh [from] [to]   (defaults: the last vX.Y.Z tag, HEAD)

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

from=${1:-$(git describe --tags --abbrev=0 --match 'v[0-9]*')}
to=${2:-HEAD}
default=$(git symbolic-ref --short -q refs/remotes/origin/HEAD | sed 's#^origin/##')
default=${default:-main}
# A merged PR with no commit in this clone is UNKNOWN only when it merged after
# `from`: an older one cannot be in the release.
since=$(git log -1 --format=%ct "$from")

gh pr list --state merged --base "$default" --limit 200 \
    --json number,title,mergeCommit,mergedAt \
    --jq '.[] | "\(.mergeCommit.oid // "")\t\(.mergedAt | fromdate)\t\(.number)\t\(.title)"' |
while IFS=$'\t' read -r oid merged number title; do
    if [ -z "$oid" ] || ! git cat-file -e "$oid^{commit}" 2>/dev/null; then
        if [ "$merged" -ge "$since" ]; then echo "UNKNOWN #$number $title"; fi
    elif git merge-base --is-ancestor "$oid" "$to" &&
        ! git merge-base --is-ancestor "$oid" "$from"; then
        echo "IN      #$number $title"
    fi
done | sort -k2,2 -t'#' -n

gh pr list --state open --base "$default" --limit 200 \
    --json number,title,isDraft \
    --jq '.[] | "OPEN    #\(.number) \(.title)\(if .isDraft then " (draft)" else "" end)"'
