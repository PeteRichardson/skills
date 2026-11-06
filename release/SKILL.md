---
name: release
description: Type /release in the main checkout of a Rust repo to check it, propose major/minor/patch, write user-focused notes from the fixed issues, then bump, tag, push and publish a GitHub release with those notes.
disable-model-invocation: true
---

# Release

Makes one release of the root package of a Rust repository: the release commit `chore(release): vX.Y.Z`, the annotated tag `vX.Y.Z`, the new `CHANGELOG.md` entry, and a GitHub release with the same notes. The repository holds its own configuration: `release.toml` (cargo-release, including the hook that writes `CHANGELOG.md`) and `cliff.toml` (git-cliff: which commits go in the notes, and the bump rules).

git-cliff gives the list of commits. The notes are written from that list for a user: what the user gets, from the summaries of the issues that the commits fix. The approved notes replace the entry that the hook writes.

Each step has a gate. When a gate fails, stop and report what failed and the state the repository is in now. Repair nothing on your own.

## 1. Check

Run `~/.claude/skills/release/preflight.sh` from the repository.

- Exit 0: continue.
- Exit 1: show the `STOP:` lines to the user, word for word, and end. The user fixes the cause and runs `/release` again.

## 2. Propose a level

Collect, from the repository root:

```bash
pkg=$(cargo metadata --no-deps --format-version 1 \
  | jq -r --arg m "$PWD/Cargo.toml" '.packages[] | select(.manifest_path == $m) | .name')
last=$(git describe --tags --abbrev=0 --match 'v[0-9]*')
bumped=$(git cliff --bumped-version 2>/dev/null)
git cliff --unreleased --context 2>/dev/null \
  | jq -r '.[0].commits[] | "\(.id[0:7]) \(.group | gsub("<[^>]*>"; "")) breaking=\(.breaking)"'
total=$(git rev-list --count "$last"..HEAD)
```

`pkg` empty means the root `Cargo.toml` has no `[package]`: stop and say so. No `vX.Y.Z` tag means the repository has no baseline: stop, and say that the first tag is made by hand.

The level comes from comparing `bumped` with `last`:

| `bumped` compared with `last` | Proposed level |
|---|---|
| major changed | major — but `minor` when `last` is `v0.*`: before 1.0, never propose major |
| minor changed | minor |
| patch changed | patch |
| the same | patch: only commits that the notes leave out (docs, test, ci, ...) |

Show the user, in this order:

1. `last` → the proposed version.
2. The reason, counted from the context lines, which list only the commits that go in the notes: for example "1 breaking, 3 features, 7 fixes, 4 left out of the notes". The left-out count is `total` minus the number of context lines.
3. The commit list: `git cliff --unreleased --tag v<proposed> --strip all 2>/dev/null`.

Ask with AskUserQuestion: the proposed level first, marked "(Recommended)", then the other two of major, minor and patch, then "Cancel". The release starts only from the user's answer. On Cancel, end; nothing has changed.

## 3. Write the notes

The context lines from step 2 are the commits that go in the notes. For each one, collect:

- The commit message: `git show -s --format=%B <id>`. The body holds the concrete facts: the old limit, the new option or key, the measured number.
- Each issue it closes (`Fixes #n`, `Closes #n`, `Resolves #n`): `gh issue view <n> --json title,body`. Take the `**SUMMARY:**` and the `**IMPACT:**` tier from the top of the body.

Write the notes to `release-notes-vX.Y.Z.md` outside the repository (your scratchpad directory, or a `mktemp` file): the tree must stay clean for step 4.

The file has this shape:

```markdown
## vX.Y.Z — YYYY-MM-DD

<One sentence: the main theme of this release, from its largest entries.>

### Features

- **<Heading.>** <Body.> ([#n](<repo url>/issues/n))
```

- Heading line: the first line of the commit list from step 2. Repo URL: `gh repo view --json url -q .url`.
- Sections: the git-cliff groups of the commits, in the same order (Breaking changes, Features, Fixes, Performance). Leave out a section with no entries. With no entries at all, the body is `No changes that affect the user.`
- One entry for each user-visible change. Several commits for one issue give one entry. Leave out an issue with tier `Maintainer-only`, or whose summary says the user sees no change.
- In a section, order the entries by tier: Breakage, Headline, Improvement, Irritant, Shortcut, then entries with no tier.
- **Heading**: what the user gets, in plain words, ending with a period: "Large command output goes to a file, with no cap." A commit subject or issue title is rarely a heading a user understands.
- **Body**: the before and the now. Write the old behavior in the past tense ("Before, a command view kept only the first 10 MiB.") and the new behavior in the present. A summary that says "today …" describes the old behavior. For a fix, say what went wrong for the user and what is true now.
- Give the concrete facts: numbers, limits, config keys, CLI flags, keys to press. They are in the commit body more often than in the summary. Names inside the code (functions, types, files) stay out.
- Each sentence is complete and correct grammar. Use the summary as raw material, and write each sentence again for the reader of the notes.

Show the whole file to the user, then ask with AskUserQuestion: "Use these notes (Recommended)", "Use the git-cliff list", "Cancel". When the user answers with changes ("Other"), revise the file and ask again. On "Use the git-cliff list", write that list (step 2, item 3) to the notes file. On Cancel, end; nothing has changed.

## 4. Release

```bash
cargo release version <level> -p "$pkg" --execute --no-confirm
cargo release hook -p "$pkg" --execute --no-confirm
~/.claude/skills/release/replace-entry.sh vX.Y.Z <notes file>
git add -A
git commit -m "chore(release): vX.Y.Z"
cargo release tag -p "$pkg" --execute --no-confirm
```

The steps run one at a time so that the notes go in the release commit. `version` bumps `Cargo.toml` and `Cargo.lock`. `hook` runs the repository's hook, which writes the git-cliff entry in `CHANGELOG.md`. `replace-entry.sh` puts the approved notes in place of that entry. `git commit` makes the release commit: `cargo release commit` writes `v{{version}}` in a workspace. `tag` makes the annotated tag from `release.toml`.

Gate: each command exits 0, `git status --porcelain` is empty, and `git describe --exact-match` gives the new tag `vX.Y.Z`. If not, show the output and end. Tell the user what is left: a bumped `Cargo.toml` and `CHANGELOG.md` that `git restore .` removes, or a local commit (and tag) that is not pushed.

## 5. Push

```bash
git push --atomic origin <default branch> vX.Y.Z
```

`--atomic` pushes the commit and the tag together or neither. If the push fails with a connection error on port 22 (`Connection refused`, `timed out`, `port 22`), try once more through GitHub's SSH on port 443, for this command only:

```bash
GIT_SSH_COMMAND="ssh -o HostName=ssh.github.com -o Port=443" git push --atomic origin <default branch> vX.Y.Z
```

Gate: the push succeeds. If not, end, and tell the user that the release commit and tag exist only on this machine and give the push command.

## 6. Publish

```bash
gh release create vX.Y.Z --title vX.Y.Z --notes-file <notes file>
```

The notes are the new `CHANGELOG.md` entry. `gh` prints the URL of the release.

Gate: `gh release view vX.Y.Z --json url` works. Done when you give the user one line: the version, the release URL, and that `Cargo.toml`, the tag, `CHANGELOG.md` and the GitHub release all show `X.Y.Z`.
