---
name: pr-triage
description: Assess and rank a set of open PRs to determine the merge order that minimizes total rebase/conflict work. Produces a scoped snapshot under .claude/tmp/pr-triage/ with a file-overlap matrix, blast-radius ranking, semantic overlap judgment for colliding PRs, and a recommended merge sequence. Supports `/pr-triage list` (per-file breakdown of outstanding vs. merged/closed PRs, each with title and link), `/pr-triage open`, and `/pr-triage clean` [--all] to find and tidy up past runs. Use when the user has multiple open PRs (especially several based on the same commit) and asks which to merge first, how to order PRs, or to triage/prioritize the PR queue. Does not merge, push, or modify anything — advisory only.
disable-model-invocation: true
---

# PR Triage

A Claude Code skill that looks at the full set of open PRs on a repo and recommends a merge order that minimizes total conflict/rebase work across all authors — rather than optimizing any single PR in isolation.

When invoked via `/pr-triage`, follow the protocol below. Everything from here through the `---` divider is the protocol Claude executes. The section after the divider is documentation for humans installing or maintaining this skill.

---

## Operating principles

The goal is total rework across the whole queue, not the easiest next merge. A "small" PR that touches a hot shared file can cost more than a "big" PR that touches nothing anyone else does. Rank by blast radius (how many other open PRs would need to rebase if this one merges first), not by size or complexity alone.

This skill is advisory. It never merges, pushes, force-pushes, or resolves conflicts on its own — it produces a ranked recommendation and reasoning, and the user decides.

Output is invalidated by the next merge event in the queue — it is not a durable artifact and must never be committed. It's written under `.claude/tmp/pr-triage/`, this project's shared scratch convention for ephemeral skill output, namespaced per-skill so multiple skills' scratch files don't collide or get mistaken for one another (see Phase 5). It persists on disk across sessions for Repeat-run mode, just never enters version control.

## Phase 0: Subcommands

Check the invocation before doing anything else:

* **`/pr-triage list`** — for every file in `.claude/tmp/pr-triage/` (create the directory first if absent — an empty listing isn't an error), read its frontmatter (`prs`, `generated`) rather than the full report. Then make **one** `gh pr list --state all --json number,state,title,url,mergedAt,closedAt` call covering the union of every `prs[].number` across all files, and classify each file's PRs against that single result — don't make a separate API call per file. Titles and URLs come from this live call, not from the report body, so a since-renamed PR still shows its current title.

  For each file, print the filename, its `generated` timestamp, and its resolved absolute path on one line, then two groups below it — always both shown in full, no flag to hide either:

  ```
  PR_TRIAGE-7-8.md  (generated 2026-07-18 14:32)  /Users/pete/project/.claude/tmp/pr-triage/PR_TRIAGE-7-8.md
      #8  ‼ Add rate limiting to /api/upload       https://github.com/org/repo/pull/8
      #7    Fix login redirect loop                https://github.com/org/repo/pull/7
      ---
      #5  ‼ Fix data loss on export bug            merged 2026-07-19  https://github.com/org/repo/pull/5
      #9    Old experimental sync flag             closed 2026-07-16  https://github.com/org/repo/pull/9
      #3    Add CSV export                         merged 2026-07-15  https://github.com/org/repo/pull/3
  ```

  - **Outstanding** (PRs the live result doesn't report as `MERGED` or `CLOSED`): one line per entry, in `prs` array order (the file's recommended-merge order), prefixed with `‼` when that entry's frontmatter `critical` is `true`, unprefixed otherwise. No color — plain text only.
  - A `---` separator line, only if both groups are non-empty.
  - **Merged/closed**: one line per entry, newest resolution first — sort by `mergedAt` for PRs the live result reports as `MERGED`, by `closedAt` for `CLOSED`. Same `‼` prefix convention, driven by the frontmatter `critical` flag, so a PR that was critical keeps that marker after it resolves. Each line ends with `merged <date>` or `closed <date>` per the live result's own `state` field — `CLOSED` is "abandoned without merging," never fold it into a `merged` count.
  - Each `#N Title` line ends with the PR's plain `url` from the live result — plain text, not a rendered hyperlink. (Raw OSC 8 codes in response text render as literal garbage rather than a clickable link, regardless of terminal — see `docs/specs/2026-07-20-pr-triage-list-output-design.md`'s Non-goals section for the tested rationale.)
  - If a file's `prs` array is empty, print just its filename/timestamp/path line — no separator, no empty group headers.

  Sort files newest-generated first (from the frontmatter `generated` timestamp, not file mtime — mtime can be misleading if files are ever copied or touched). If a file has no frontmatter (e.g. hand-edited or from an older version of this skill), fall back to filename and last-modified time only, and note it's missing status. Stop here; don't run a triage.
* **`/pr-triage open`** — run `open .claude/tmp/pr-triage/` (macOS). If `open` isn't available, fall back to printing the absolute path. Stop here; don't run a triage.
* **`/pr-triage clean`** — read every file's frontmatter for its `prs` list, then make one `gh pr list --state all --json number,state` call covering the union (same approach as `list`) rather than one call per file. Any file whose entire `prs` set is now merged or closed is a candidate for removal — there's no Repeat-run continuity value left in a snapshot whose whole queue has resolved. Show the candidate list plus, separately, what's being kept and why (any file referencing at least one still-open PR), and ask for confirmation before deleting. Stop here; don't run a triage.
* **`/pr-triage clean --all`** — unconditional wipe of everything in `.claude/tmp/pr-triage/`, regardless of PR state. Show what will be deleted and ask for confirmation first. Stop here; don't run a triage.
* **`/pr-triage`** (no args) — full-queue run, proceed to Phase 1.
* **`/pr-triage #7 #8 #12`** (PR numbers) — scoped run limited to those PRs, proceed to Phase 1 with the scope noted.

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

### Severity override

Blast radius optimizes engineering cost (total rework across the queue). A linked issue's severity is a different axis — urgency of delay — and the two can conflict. Don't blend them into one score; use a two-tier structure instead:

1. For each PR, check for linked issues: `gh pr view <N> --json closingIssuesReferences` (catches "Fixes #N" / "Closes #N" in the PR body), then `gh issue view <N> --json labels,title` for each linked issue.
2. If any linked issue carries a label indicating critical severity (security, data-loss, crash, or an explicit critical/P0-style label — the exact convention varies by repo, so check what labels this repo actually uses rather than assuming a scheme), that PR is promoted to a **critical tier** ahead of the entire blast-radius-ranked queue, regardless of its own blast radius.
3. Order the critical tier among itself the same way (blast radius, then tiebreakers) if more than one PR qualifies.
4. Everything without a critical-severity linked issue stays in the normal blast-radius-ranked pool, unaffected by lower-priority labels (a "P2" or "enhancement" label is not a promotion signal — only genuine urgency is).
5. If no severity labels exist in the repo at all, say so once and skip this step — don't invent a severity scheme.

When a PR is promoted, state the tradeoff explicitly in the deliverable rather than folding it into a blended number: which PR, which linked issue and severity, and which other PRs now bear increased rebase cost as a result.

## Phase 4: Semantic overlap judgment (only for overlapping pairs)

Raw file overlap over-flags: two PRs can touch the same file without ever touching the same logic. For every pair flagged in Phase 2, read both diffs (`gh pr diff <N>`) and classify:

- **Incidental adjacency** — changes land near each other (e.g., both add functions to the same file) but don't interact. Low risk; likely to auto-merge cleanly or need only a trivial resolution.
- **Likely semantic collision** — both PRs modify the same function, same invariant, or same logic path, especially where one PR's reason for the change isn't visible from the diff alone (bug fix, subtle behavior change). Flag these explicitly — they're the ones where an automated or careless rebase resolution could produce something that merges cleanly but is wrong.

State your confidence and reasoning for each classification. If a pair's overlap is genuinely ambiguous from the diff alone, say so rather than guessing — this goes in Open Questions, not the table.

## Phase 5: Deliverable

This project uses `.claude/tmp/` as the shared convention for ephemeral skill output — never `.claude/` broadly, since `.claude/skills/` and `.claude/settings.json` may be intentionally tracked. Each skill gets its own subdirectory so scratch files stay findable and don't collide. Before writing anything:

1. `mkdir -p .claude/tmp/pr-triage`
2. Check `.gitignore` for a `.claude/tmp/` entry. If absent, append one line: `.claude/tmp/` with a comment noting it's the shared scratch dir for ephemeral Claude Code skill output. This single directory-level entry covers `pr-triage` and every other skill that adopts the convention — don't add per-skill or per-file entries.
3. Determine the filename: `PR_TRIAGE.md` for a full-queue run, or `PR_TRIAGE-<numbers>.md` (PR numbers sorted ascending, e.g. `PR_TRIAGE-7-8-12.md`) for a scoped run — so `list` output and the filename itself communicate what each run covered without opening the file.

Then write `.claude/tmp/pr-triage/<filename>`, starting with a YAML frontmatter block so `list` can report status without re-parsing the whole report:

```yaml
---
generated: <ISO 8601 timestamp>
prs:
  - number: 7
    critical: false
  - number: 8
    critical: true
  - number: 12
    critical: false
---
```

`prs` is an ordered array covering every PR this snapshot tracks, one entry per PR, in the Phase 3/severity-override recommended merge order (order is irrelevant for entries that later merge or close — `list` re-sorts those by resolution date instead, see Phase 0). `critical` on each entry records whether Phase 3's severity override promoted that PR — set it once at write time from Phase 3's own determination, never recomputed from anything else. Entries are never removed from `prs`, even after the PR merges or closes — see Repeat-run mode below for why. Then the body:

* **Summary table** — columns: `PR # | Title | Author | Linked Issue (severity) | Files Changed | Overlaps With | Blast Radius | Staleness (days) | Size (+/-) | Mergeable? | Suggested Order`.
* **Recommended merge sequence** — numbered list, one line of rationale per PR (e.g., "merge 3rd: overlaps only with #8, which is already stale and low-priority").
* **Severity overrides** — any PR promoted ahead of blast-radius order due to a critical-severity linked issue, naming the issue and which other PRs now bear increased rebase cost as a result. Omit this section entirely (don't write "none") if the repo has no severity-labeled issues linked to any open PR.
* **Overlap detail** — for each overlapping pair, the Phase 4 classification and reasoning. Incidental-adjacency pairs can be one line; likely-collision pairs get a short explanation of what's actually colliding and why it matters.
* **Already-conflicting PRs** — any PR GitHub already reports as `CONFLICTING` against the current base, called out separately since these need author action regardless of queue position.
* **Open questions** — overlaps you couldn't classify confidently, PRs with unclear base commits, or anything needing the maintainer's judgment.

## Rules

* Never merge, push, rebase, or force-push anything — this skill only reads (`gh pr list`, `gh pr diff`, `git log`) and writes under `.claude/tmp/pr-triage/`.
* `clean` and `clean --all` are the only operations that delete anything, and both require showing the candidate list and getting explicit confirmation first — never delete silently, even though these are scratch files.
* Base blast-radius and overlap claims on the actual file/diff data, not assumption. If `gh` or `git` calls fail (rate limit, auth), say so and stop rather than guessing at PR contents.
* Keep size and staleness as tiebreakers only — never let them override blast radius in the primary ranking.
* Label semantic-collision judgments as judgment calls, not certainty. "Likely collision" and "confirmed collision" are different claims — don't collapse them.
* Don't pad the overlap detail section with pairs that have zero file overlap; only overlapping pairs get an entry.

## Repeat-run mode

If a file matching the current invocation's scope already exists in `.claude/tmp/pr-triage/` (`PR_TRIAGE.md` for a full run, `PR_TRIAGE-<numbers>.md` for a scoped run), read it first. Mark PRs no longer open as `MERGED` or `CLOSED`, re-rank the remaining queue against the current base, and note which recommendations changed since the last run and why (usually: a merge happened, or a PR was updated). A full-queue run and a scoped run are tracked separately — don't treat one as a substitute for the other's history.

**Full-queue repeat runs** (`PR_TRIAGE.md`) always re-run Phase 1 in full — re-enumerate every currently-open PR rather than trusting the existing file's `prs` array, since a critical PR opened after the last run must not stay invisible until the next fresh (non-repeat) triage. Any PR Phase 1 returns that isn't already in the file's `prs` array is new: give it the full Phase 2–4 treatment (diff, overlap, severity check). For a PR already in `prs`, compare its live `updatedAt` (from this same Phase 1 call) against the file's own frontmatter `generated` timestamp — if `updatedAt` is not later than `generated`, nothing about that PR has changed since this snapshot was written, so skip re-diffing it in Phase 2/4 and reuse its last-known overlap and severity classification. Cost scales with the number of genuinely new or since-updated PRs, not the full queue.

**Scoped repeat runs** (`PR_TRIAGE-<numbers>.md`) stay locked to the PR numbers already in the file's `prs` array — this mode exists specifically so the user can burn down a chosen subset without new PRs jumping the queue. Don't re-enumerate beyond those numbers.

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

Output goes to `.claude/tmp/pr-triage/PR_TRIAGE.md` for a full-queue run — this project's shared scratch convention for ephemeral skill output, namespaced per-skill (`pr-triage/`) so it's obvious which skill produced which file when you're browsing `.claude/tmp/`. The skill creates the directory and adds a single `.claude/tmp/` line to `.gitignore` on first run if it's not already there; every skill that adopts this convention shares that one gitignore entry rather than each appending its own. The file persists on disk between sessions, so a repeat `/pr-triage` run picks up where the last one left off (see Repeat-run mode) without ever showing up in `git status` or your commit history.

On a queue of 5–10 PRs this should take a few minutes; it scales roughly with the number of overlapping pairs, since those are the ones that need a real diff read in Phase 4.

Scope to a subset if you only want to reason about some of the queue:

```
/pr-triage #7 #8 #12
```

That writes a separately-tracked `.claude/tmp/pr-triage/PR_TRIAGE-7-8-12.md`, distinct from any full-queue run's history.

Find or open past runs without digging through `.claude/` by hand:

```
/pr-triage list
/pr-triage open
```

`list` shows each snapshot's outstanding and merged/closed PRs at a glance — title, critical marker, and link — without opening the file:

```
PR_TRIAGE-7-8.md  (generated 2026-07-18 14:32)  /Users/pete/project/.claude/tmp/pr-triage/PR_TRIAGE-7-8.md
    #8  ‼ Add rate limiting to /api/upload       https://github.com/org/repo/pull/8
    #7    Fix login redirect loop                https://github.com/org/repo/pull/7
    ---
    #5  ‼ Fix data loss on export bug            merged 2026-07-19  https://github.com/org/repo/pull/5
    #9    Old experimental sync flag             closed 2026-07-16  https://github.com/org/repo/pull/9
    #3    Add CSV export                         merged 2026-07-15  https://github.com/org/repo/pull/3
```

`open` opens the folder in Finder (macOS). This exists specifically so you don't have to remember the skill name or go spelunking through `.claude/tmp/` the way you'd hunt for an Xcode build product in DerivedData.

Clean up old snapshots when you're done with them:

```
/pr-triage clean
/pr-triage clean --all
```

Plain `clean` only removes snapshots whose entire referenced PR set has since merged or closed — those have no Repeat-run value left. It'll show you the candidates and what it's keeping (anything still referencing an open PR) before deleting. `clean --all` wipes the whole directory unconditionally. Both ask for confirmation first.

**Not yet implemented:** a `view` subcommand (opens the most-recently-generated snapshot in the system default `.md` viewer, for "I just ran this and closed the window, let me look again" — no rerun, no state check) and a `pick` subcommand (list + choose, for when `view`'s most-recent guess isn't the one you want). Until these exist, `open` + double-click covers the same need.

## How this fits with your other skills

Run `/pr-triage` first when you're facing more than 2–3 open PRs and want a merge order, before touching any individual PR. Once you've picked the next PR to merge per its recommendation, use `/code-review` on that specific PR for the actual line-level review. If a PR the triage flags as a "likely semantic collision" ends up needing conflict resolution after an earlier merge, that's a good candidate for a future `/resolve-conflicts` skill (mechanical rebase + test run, escalating to you for anything flagged low-confidence) rather than doing it free-form.

## Why blast radius instead of size or complexity

Ranking by size ("merge small ones first") or by complexity ("get the big one out of the way") both optimize the wrong unit — the PR being merged, not the total work left in the queue. A small PR that happens to touch a file every other open PR also touches will force a rebase on all of them; a large PR touching a file nobody else is in costs nothing to merge first. Blast radius is a direct measure of what actually happens to the rest of the queue, which is the thing you're trying to minimize. Size and staleness only break ties among PRs that disturb the queue equally.

## Why severity is a tier, not a weight in the score

Blast radius measures engineering cost; issue severity measures urgency of delay. They're different axes and can point opposite directions — a critical fix can easily be the PR with the *worst* blast radius, if the bug lives in commonly-touched code. Folding both into one weighted number would hide that tension behind an opaque score. Tiering makes the tradeoff explicit instead: critical-severity fixes jump the queue, and the deliverable says outright who pays for that in extra rebase work. That's a decision worth seeing, not one worth automating away.

## The `.claude/tmp/<skill-name>/` convention

This skill writes to `.claude/tmp/pr-triage/` rather than the repo root, and only ever appends one `.gitignore` line (`.claude/tmp/`) for the whole directory rather than one per output file or per skill. This is meant to be a shared convention across your skills ecosystem, not specific to `pr-triage` — any future audit-style skill that generates ephemeral, quickly-stale output can adopt the same boilerplate (`mkdir -p .claude/tmp/<skill-name>`, check-and-append the single shared gitignore line) instead of inventing its own output path and gitignore handling. Worth writing this down once in a `CONVENTIONS.md` in your `claude-skills` repo so it's copy-paste consistent rather than reinvented per skill.

The per-skill subdirectory exists specifically so the output is findable without already knowing what you're looking for — a flat `.claude/tmp/` shared across many skills would eventually become exactly the kind of "where did that file go" problem the convention is meant to solve. `list` and `open` subcommands are the other half of that: rather than requiring you to remember the skill name or `cd` into `.claude/tmp/` by hand, the skill can surface its own scratch output on request. If you adopt this pattern elsewhere, consider giving other scratch-producing skills the same two subcommands for the same reason.

`tech-debt-audit`, `project-review`, and `code-review` are candidates to migrate their transient working files to this same path if you want their scratch output out of the repo tree too — separate from the question of whether their *durable* findings belong in GitHub Issues instead.

## Limitations

File-level overlap is a necessary but not sufficient signal — Phase 4 exists because two PRs can touch the same file without conflicting, and two PRs can touch different files and still conflict semantically (e.g., one renames a function the other calls, with no textual proximity at all). This skill catches the former reliably; the latter requires the author or reviewer to catch behaviorally, since it won't show up as a git conflict at all until the calling code is exercised.

This skill doesn't run tests or builds — it's a queue-ordering tool, not a merge-validation tool. Always run the test suite after any actual merge or rebase, regardless of what this skill recommends.

## License

Original, written for Peter's personal skills ecosystem. Freely modifiable.
