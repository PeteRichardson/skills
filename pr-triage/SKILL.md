---
name: pr-triage
description: Assess and rank a set of open PRs to determine the merge order that minimizes total rebase/conflict work. Produces PR_TRIAGE.md with a file-overlap matrix, blast-radius ranking, semantic overlap judgment for colliding PRs, and a recommended merge sequence. Use when the user has multiple open PRs (especially several based on the same commit) and asks which to merge first, how to order PRs, or to triage/prioritize the PR queue. Does not merge, push, or modify anything — advisory only.
disable-model-invocation: true
---

# PR Triage

A Claude Code skill that looks at the full set of open PRs on a repo and recommends a merge order that minimizes total conflict/rebase work across all authors — rather than optimizing any single PR in isolation.

When invoked via `/pr-triage`, follow the protocol below. Everything from here through the `---` divider is the protocol Claude executes. The section after the divider is documentation for humans installing or maintaining this skill.

---

## Operating principles

The goal is total rework across the whole queue, not the easiest next merge. A "small" PR that touches a hot shared file can cost more than a "big" PR that touches nothing anyone else does. Rank by blast radius (how many other open PRs would need to rebase if this one merges first), not by size or complexity alone.

This skill is advisory. It never merges, pushes, force-pushes, or resolves conflicts on its own — it produces a ranked recommendation and reasoning, and the user decides.

## Phase 1: Enumerate the queue

1. Confirm the repo and base branch (default `main`, ask if ambiguous).
2. `gh pr list --state open --json number,title,author,headRefName,baseRefName,createdAt,updatedAt,additions,deletions,changedFiles,mergeable,mergeStateStatus`
3. Filter to PRs targeting the same base branch. Note their base commit — if they're not all based on the same commit, record how far each has diverged (`git log --oneline <base>..<pr-branch>` vs `git log --oneline <pr-branch>..<base>`).
4. Use `TodoWrite` to publish a plan (enumerate → overlap → rank → judge → deliver) so progress is visible on a large queue.

## Phase 2: Build the file-overlap matrix

For each PR, get the changed-file set:

```
gh pr diff <N> --name-only
```

Build a PR × PR overlap table: which pairs of PRs touch at least one file in common. This is pure set intersection — no judgment yet. Also record, per PR, GitHub's own `mergeable` status against the *current* base (`MERGEABLE` / `CONFLICTING` / `UNKNOWN`) — this tells you which PRs already conflict with what's merged so far, independent of the other open PRs.

## Phase 3: Rank by blast radius

For each PR, compute blast radius = count of other open PRs it shares at least one file with. Sort ascending — lowest blast radius merges first, since merging it disturbs the fewest other PRs.

Tiebreakers, in order, when blast radius is equal:

1. **Staleness** — days since `updatedAt`. Older/less-active PRs go earlier: drift compounds whether or not anyone's watching it, so surface it before its rebase gets harder.
2. **Size** — smaller diffs (`additions + deletions`) go earlier, as a last resort only. Don't let size override blast radius; a small PR with a large blast radius still goes later.

## Phase 4: Semantic overlap judgment (only for overlapping pairs)

Raw file overlap over-flags: two PRs can touch the same file without ever touching the same logic. For every pair flagged in Phase 2, read both diffs (`gh pr diff <N>`) and classify:

- **Incidental adjacency** — changes land near each other (e.g., both add functions to the same file) but don't interact. Low risk; likely to auto-merge cleanly or need only a trivial resolution.
- **Likely semantic collision** — both PRs modify the same function, same invariant, or same logic path, especially where one PR's reason for the change isn't visible from the diff alone (bug fix, subtle behavior change). Flag these explicitly — they're the ones where an automated or careless rebase resolution could produce something that merges cleanly but is wrong.

State your confidence and reasoning for each classification. If a pair's overlap is genuinely ambiguous from the diff alone, say so rather than guessing — this goes in Open Questions, not the table.

## Phase 5: Deliverable

Write to `PR_TRIAGE.md` in the repo root:

* **Summary table** — columns: `PR # | Title | Author | Files Changed | Overlaps With | Blast Radius | Staleness (days) | Size (+/-) | Mergeable? | Suggested Order`.
* **Recommended merge sequence** — numbered list, one line of rationale per PR (e.g., "merge 3rd: overlaps only with #8, which is already stale and low-priority").
* **Overlap detail** — for each overlapping pair, the Phase 4 classification and reasoning. Incidental-adjacency pairs can be one line; likely-collision pairs get a short explanation of what's actually colliding and why it matters.
* **Already-conflicting PRs** — any PR GitHub already reports as `CONFLICTING` against the current base, called out separately since these need author action regardless of queue position.
* **Open questions** — overlaps you couldn't classify confidently, PRs with unclear base commits, or anything needing the maintainer's judgment.

## Rules

* Never merge, push, rebase, or force-push anything — this skill only reads (`gh pr list`, `gh pr diff`, `git log`) and writes `PR_TRIAGE.md`.
* Base blast-radius and overlap claims on the actual file/diff data, not assumption. If `gh` or `git` calls fail (rate limit, auth), say so and stop rather than guessing at PR contents.
* Keep size and staleness as tiebreakers only — never let them override blast radius in the primary ranking.
* Label semantic-collision judgments as judgment calls, not certainty. "Likely collision" and "confirmed collision" are different claims — don't collapse them.
* Don't pad the overlap detail section with pairs that have zero file overlap; only overlapping pairs get an entry.

## Repeat-run mode

If `PR_TRIAGE.md` already exists, read it first. Mark PRs no longer open as `MERGED` or `CLOSED`, re-rank the remaining queue against the current base, and note which recommendations changed since the last run and why (usually: a merge happened, or a PR was updated).

---

# Project documentation

Everything below is for humans installing, using, or contributing to this skill. It is not part of the triage protocol.

## Installation

Personal install (available across all your projects):

```bash
mkdir -p ~/.claude/skills/pr-triage
# copy this file to ~/.claude/skills/pr-triage/SKILL.md
```

Or project-only:

```bash
mkdir -p .claude/skills/pr-triage
cp /path/to/this/SKILL.md .claude/skills/pr-triage/SKILL.md
```

Requires the `gh` CLI, authenticated (`gh auth status`) with access to the target repo.

## Usage

In Claude Code, in the repo whose PR queue you want triaged:

```
/pr-triage
```

Output goes to `PR_TRIAGE.md` in the repo root. On a queue of 5–10 PRs this should take a few minutes; it scales roughly with the number of overlapping pairs, since those are the ones that need a real diff read in Phase 4.

Scope to a subset if you only want to reason about some of the queue:

```
/pr-triage #7 #8 #12
```

## How this fits with your other skills

Run `/pr-triage` first when you're facing more than 2–3 open PRs and want a merge order, before touching any individual PR. Once you've picked the next PR to merge per its recommendation, use `/code-review` on that specific PR for the actual line-level review. If a PR the triage flags as a "likely semantic collision" ends up needing conflict resolution after an earlier merge, that's a good candidate for a future `/resolve-conflicts` skill (mechanical rebase + test run, escalating to you for anything flagged low-confidence) rather than doing it free-form.

## Why blast radius instead of size or complexity

Ranking by size ("merge small ones first") or by complexity ("get the big one out of the way") both optimize the wrong unit — the PR being merged, not the total work left in the queue. A small PR that happens to touch a file every other open PR also touches will force a rebase on all of them; a large PR touching a file nobody else is in costs nothing to merge first. Blast radius is a direct measure of what actually happens to the rest of the queue, which is the thing you're trying to minimize. Size and staleness only break ties among PRs that disturb the queue equally.

## Limitations

File-level overlap is a necessary but not sufficient signal — Phase 4 exists because two PRs can touch the same file without conflicting, and two PRs can touch different files and still conflict semantically (e.g., one renames a function the other calls, with no textual proximity at all). This skill catches the former reliably; the latter requires the author or reviewer to catch behaviorally, since it won't show up as a git conflict at all until the calling code is exercised.

This skill doesn't run tests or builds — it's a queue-ordering tool, not a merge-validation tool. Always run the test suite after any actual merge or rebase, regardless of what this skill recommends.

## License

Original, written for Peter's personal skills ecosystem. Freely modifiable.
