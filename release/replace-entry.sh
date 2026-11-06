#!/usr/bin/env bash
# Replaces the newest entry of CHANGELOG.md (the first "## " section, which the
# cargo-release hook just wrote with git-cliff) with the approved notes.
#
# Usage: replace-entry.sh vX.Y.Z NOTES_FILE   (from the repository root)
#
# Exits 1, and changes nothing, when the first entry is not for vX.Y.Z.

set -eu
version=$1
notes=$2

first=$(grep -m1 '^## ' CHANGELOG.md || true)
case "$first" in
    "## $version "* | "## $version") ;;
    *) echo "STOP: the first CHANGELOG.md entry is '$first', not $version."; exit 1 ;;
esac

awk -v notes="$notes" '
    BEGIN { while ((getline line < notes) > 0) text = text line "\n" }
    /^## / {
        n++
        if (n == 1) { printf "%s\n", text; skip = 1; next }
        if (n == 2) skip = 0
    }
    !skip
' CHANGELOG.md > CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md
