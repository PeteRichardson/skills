# `/pr-triage list` output redesign

Status: approved, not yet implemented.

## Problem

`/pr-triage list` today prints one summary line per snapshot file:

```
PR_TRIAGE-7-8.md   2 PRs, 0 critical, 0 merged, 2 outstanding [#7, #8]
```

This tells you *that* something changed but not *what*. Reading the actual outstanding PRs requires opening the report or running `gh pr view` by hand. In practice the user's workflow is:

1. `/pr-triage`
2. `/pr-triage list` (or the not-yet-built `view`) to see what's outstanding
3. Fix things, close some PRs
4. `/pr-triage list` again
5. Back to step 3

`list` is becoming the primary iteration loop, not just a file-management utility — so it should surface enough per-PR detail to act on without opening the report.

## Goals

- Show, per snapshot file, the outstanding PRs (number + title) in recommended merge order, and the merged/closed PRs in reverse-chronological order — always, no flag needed (queues here run in the 10–20 PR range, not hundreds).
- Distinguish critical vs. non-critical vs. merged/closed via a plain-text marker (no color — see Non-goals).
- Preserve visibility into "this one used to be critical" even after it merges.
- Print the filename as a plain absolute path and each PR line's URL as plain text, so terminals with path/URL auto-detection (iTerm2 semantic history, etc.) can still make them clickable, without depending on OSC 8 support.
- Keep `list`'s single-`gh`-call-per-invocation principle intact.
- Full-queue repeat runs must surface newly-opened critical PRs, not just reconcile the PRs already in the snapshot.

## Non-goals

- The `view` subcommand (separate, future item).
- Renaming `clean` to `prune` (separate, future item — flagged as an observation below, not part of this change).
- A `--all` / filtering flag — dropped in favor of always showing everything, since the queue size doesn't warrant hiding anything.
- ANSI color codes and OSC 8 hyperlinks in `list`'s output — tested directly (2026-07-20) and dropped. `list`'s output is assistant response text, and raw escape sequences in response text render as literal garbage regardless of terminal (Claude Code sanitizes model-generated text so it can't inject terminal control codes). Routing the output through a Bash call instead does render escape codes correctly in a real terminal, but Claude Code's TUI collapses Bash tool output to a one-line summary by default, and reaching the expanded view requires the user to press Ctrl+O — a toggle that resets on every subsequent tool call and cannot be forced open at generation time. That per-invocation manual step is worse than just not styling the output.

## Design

### Frontmatter schema change

`prs` changes from a flat array of numbers to an ordered array of objects. Order = recommended merge sequence for whatever was outstanding at last-write time (irrelevant for merged/closed entries, which `list` re-sorts live by merge/close date):

```yaml
---
generated: 2026-07-20T14:32:00Z
prs:
  - number: 7
    critical: false
  - number: 8
    critical: true
---
```

The top-level `critical: <count>` field is dropped — it's now derivable by scanning `prs`, and the count summary line it fed is being removed from `list`'s output anyway.

Entries are **never removed** from `prs` once added, even after the PR merges or closes. This keeps the critical flag available indefinitely so `list` can still flag "this merged PR used to be critical." Pruning resolved entries is a file-level concern (`clean`), not something a repeat run does silently to an entry within a file — see the `clean`/`prune` naming note below.

There is exactly one existing report file using the old flat-array format; the user will delete it rather than have this design carry backward-compatibility logic for it.

**Later additive change (not part of this design's `list` work):** each `prs` entry also carries an `issues` array (`{number, finding?}` per linked issue, `[]` when none) so the report body's tables can show PR number, issue number, and finding ID as separate columns, and so repeat runs can reuse them for unchanged PRs without re-querying. `list` ignores the field — its output shape below is unchanged.

### `list` output format

```
PR_TRIAGE-7-8.md  (generated 2026-07-18 14:32)  /Users/pete/project/.claude/tmp/pr-triage/PR_TRIAGE-7-8.md
    #8  ‼ Add rate limiting to /api/upload       https://github.com/org/repo/pull/8
    #7    Fix login redirect loop                https://github.com/org/repo/pull/7
    ---
    #5  ‼ Fix data loss on export bug            merged 2026-07-19  https://github.com/org/repo/pull/5
    #9    Old experimental sync flag             closed 2026-07-16  https://github.com/org/repo/pull/9
    #3    Add CSV export                         merged 2026-07-15  https://github.com/org/repo/pull/3
```

- Filename line is followed by the plain absolute path to the file, so terminals with path auto-detection (iTerm2 semantic history, etc.) can still open it directly — no OSC 8 involved (see Non-goals). The per-file count summary (`2 PRs, 0 critical, ...`) is removed; the generation timestamp (from frontmatter `generated`) takes its place on the same line, since the PR list below already conveys the counts at a glance.
- Below the filename, two groups, always both shown in full (no `--all` flag):
  - **Outstanding**, in recommended order (frontmatter array order for entries not yet merged/closed). Prefixed with `‼` if the entry's frontmatter `critical` flag is `true`; unmarked otherwise (no color — see Non-goals).
  - A `---` separator line.
  - **Merged/closed**, in reverse-chronological order (most recent first), sorted by `mergedAt` for state `MERGED` and `closedAt` for state `CLOSED`. Same `‼` marker convention as the outstanding group, so a PR that was critical doesn't lose that signal once it resolves.
  - Each line shows its resolution: `merged <date>` or `closed <date>` (GitHub's `state` field distinguishes these — `CLOSED` is "abandoned without merging," not a synonym for merged, so the current skill's practice of lumping both into one "merged" count is being corrected here).
  - If `prs` is empty, print just the filename/timestamp/path line — no separator, no stray group headers.
- Each `#N Title` line ends with the PR's plain GitHub URL as text, relying on the same terminal auto-detection as the file path — no OSC 8.
- Sort order of files (which file's block comes first) is unchanged: newest-generated first, from frontmatter `generated`.

### `gh` call changes

`list` still makes exactly one `gh pr list --state all --json ...` call across the union of every file's PR numbers. Fields grow from `number,state` to `number,state,title,url,mergedAt,closedAt` — titles are fetched live (not stored in frontmatter) so they stay accurate even if a PR is renamed after the report was generated, and no per-PR calls are introduced.

### Repeat-run mode change

Today, repeat-run reconciles only the PRs already present in the snapshot file. This under-serves full-queue snapshots: a critical PR opened after the last run would stay invisible until the user happened to start a fresh (non-repeat) triage.

- **Full-queue repeat runs** (`PR_TRIAGE.md`) now always re-run Phase 1 (re-enumerate all currently-open PRs) rather than trusting the old snapshot's PR list. Any PR not already in the file's `prs` array is new and gets the full Phase 2–4 treatment (diff, overlap, severity check). PRs already in the array whose `updatedAt` hasn't changed since the last run can skip re-diffing. Cost scales with the number of genuinely new PRs, which is expected to be small.
- **Scoped repeat runs** (`PR_TRIAGE-7-8.md`) are unchanged — they stay locked to the PR numbers the user explicitly chose. That's already the "focus and burn down this subset" mode; re-discovering unrelated new PRs there would violate the user's explicit scoping.

## Observations for future work (not part of this change)

- `clean` is really pruning whole files (delete snapshots whose entire PR set has resolved). A future rename to `prune` would make the file-level operation's name distinct from any entry-level cleanup, avoiding the confusion that came up while designing this feature. Deferred — orthogonal to `list`'s output.
- `view` (open the most-recent snapshot in the system default `.md` viewer) remains unimplemented; the plain absolute path added to `list`'s filename line covers part of that need for terminals with path auto-detection, but `view` is still a separate future subcommand.
