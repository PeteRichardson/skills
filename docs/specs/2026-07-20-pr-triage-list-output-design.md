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
- Distinguish critical vs. non-critical vs. merged/closed visually via color.
- Preserve visibility into "this one used to be critical" even after it merges.
- Make the filename and each PR line clickable where the terminal supports it (OSC 8 hyperlinks), without breaking terminals that don't.
- Keep `list`'s single-`gh`-call-per-invocation principle intact.
- Full-queue repeat runs must surface newly-opened critical PRs, not just reconcile the PRs already in the snapshot.

## Non-goals

- The `view` subcommand (separate, future item).
- Renaming `clean` to `prune` (separate, future item — flagged as an observation below, not part of this change).
- A `--all` / filtering flag — dropped in favor of always showing everything, since the queue size doesn't warrant hiding anything.
- Terminal color/hyperlink fallback logic — OSC 8 and ANSI color codes degrade gracefully in terminals that don't support them (plain text renders), so no conditional branching is needed.

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

### `list` output format

```
PR_TRIAGE-7-8.md  (generated 2026-07-18 14:32)
    #8  Add rate limiting to /api/upload
    #7  Fix login redirect loop
    ---
    #5  ‼ Fix data loss on export bug          merged 2026-07-19
    #9  Old experimental sync flag              closed 2026-07-16
    #3  Add CSV export                          merged 2026-07-15
```

- Filename is an OSC 8 hyperlink to `file://<absolute-path>`, so terminals that support it (iTerm2, WezTerm, Kitty, etc.) can open it directly in the system default `.md` viewer. The per-file count summary (`2 PRs, 0 critical, ...`) is removed; the generation timestamp (from frontmatter `generated`) takes its place on the same line, since the PR list below already conveys the counts at a glance.
- Below the filename, two groups, always both shown in full (no `--all` flag):
  - **Outstanding**, in recommended order (frontmatter array order for entries not yet merged/closed). Critical → red. Non-critical → yellow.
  - A `---` separator line.
  - **Merged/closed**, in reverse-chronological order (most recent first), sorted by `mergedAt` for state `MERGED` and `closedAt` for state `CLOSED`. Always grey. Prefixed with `‼` if the entry's frontmatter `critical` flag is `true` — so a critical fix landing doesn't just disappear into grey.
  - Each line shows its resolution: `merged <date>` or `closed <date>` (GitHub's `state` field distinguishes these — `CLOSED` is "abandoned without merging," not a synonym for merged, so the current skill's practice of lumping both into one "merged" count is being corrected here).
  - If `prs` is empty, print just the filename/timestamp line — no separator, no stray group headers.
- Each `#N Title` line is itself an OSC 8 hyperlink to the PR's GitHub URL.
- Sort order of files (which file's block comes first) is unchanged: newest-generated first, from frontmatter `generated`.

### `gh` call changes

`list` still makes exactly one `gh pr list --state all --json ...` call across the union of every file's PR numbers. Fields grow from `number,state` to `number,state,title,url,mergedAt,closedAt` — titles are fetched live (not stored in frontmatter) so they stay accurate even if a PR is renamed after the report was generated, and no per-PR calls are introduced.

### Repeat-run mode change

Today, repeat-run reconciles only the PRs already present in the snapshot file. This under-serves full-queue snapshots: a critical PR opened after the last run would stay invisible until the user happened to start a fresh (non-repeat) triage.

- **Full-queue repeat runs** (`PR_TRIAGE.md`) now always re-run Phase 1 (re-enumerate all currently-open PRs) rather than trusting the old snapshot's PR list. Any PR not already in the file's `prs` array is new and gets the full Phase 2–4 treatment (diff, overlap, severity check). PRs already in the array whose `updatedAt` hasn't changed since the last run can skip re-diffing. Cost scales with the number of genuinely new PRs, which is expected to be small.
- **Scoped repeat runs** (`PR_TRIAGE-7-8.md`) are unchanged — they stay locked to the PR numbers the user explicitly chose. That's already the "focus and burn down this subset" mode; re-discovering unrelated new PRs there would violate the user's explicit scoping.

## Observations for future work (not part of this change)

- `clean` is really pruning whole files (delete snapshots whose entire PR set has resolved). A future rename to `prune` would make the file-level operation's name distinct from any entry-level cleanup, avoiding the confusion that came up while designing this feature. Deferred — orthogonal to `list`'s output.
- `view` (open the most-recent snapshot in the system default `.md` viewer) remains unimplemented; the OSC 8 filename hyperlink added here covers part of that need for terminals that support it, but `view` is still a separate future subcommand.
