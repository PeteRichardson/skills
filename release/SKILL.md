---
name: release
description: Type /release in the main checkout of a Rust repo to check it, propose major/minor/patch, then bump, tag, push and publish a GitHub release with notes.
disable-model-invocation: true
---

# Release

Makes one release of the root package of a Rust repository: the release commit `chore(release): vX.Y.Z`, the annotated tag `vX.Y.Z`, the new `CHANGELOG.md` entry, and a GitHub release with the same notes. The repository holds its own configuration: `release.toml` (cargo-release, including the hook that writes `CHANGELOG.md`) and `cliff.toml` (git-cliff: which commits go in the notes, and the bump rules).

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
  | jq -r '.[0].commits[] | "\(.group | gsub("<[^>]*>"; "")) breaking=\(.breaking)"'
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
3. The notes: `git cliff --unreleased --tag v<proposed> --strip all 2>/dev/null`.

Ask with AskUserQuestion: the proposed level first, marked "(Recommended)", then the other two of major, minor and patch, then "Cancel". The release starts only from the user's answer. On Cancel, end; nothing has changed.

## 3. Release

```bash
cargo release <level> -p "$pkg" --execute --no-confirm --no-push
```

`--no-push` keeps the push in step 4, where it can be retried; `--no-confirm` because the user confirmed in step 2. cargo-release bumps `Cargo.toml` and `Cargo.lock`, runs the hook that writes `CHANGELOG.md`, commits, and makes the tag.

Gate: the command exits 0, `git status --porcelain` is empty, and `git describe --exact-match` gives the new tag `vX.Y.Z`. If not, show the output and end. Tell the user what is left: a bumped `Cargo.toml` that `git restore .` removes, or a local commit and tag that are not pushed.

## 4. Push

```bash
git push --atomic origin <default branch> vX.Y.Z
```

`--atomic` pushes the commit and the tag together or neither. If the push fails with a connection error on port 22 (`Connection refused`, `timed out`, `port 22`), try once more through GitHub's SSH on port 443, for this command only:

```bash
GIT_SSH_COMMAND="ssh -o HostName=ssh.github.com -o Port=443" git push --atomic origin <default branch> vX.Y.Z
```

Gate: the push succeeds. If not, end, and tell the user that the release commit and tag exist only on this machine and give the push command.

## 5. Publish

```bash
git cliff --latest --strip all 2>/dev/null \
  | gh release create vX.Y.Z --title vX.Y.Z --notes-file -
```

The notes are the new `CHANGELOG.md` entry. `gh` prints the URL of the release.

Gate: `gh release view vX.Y.Z --json url` works. Done when you give the user one line: the version, the release URL, and that `Cargo.toml`, the tag, `CHANGELOG.md` and the GitHub release all show `X.Y.Z`.
