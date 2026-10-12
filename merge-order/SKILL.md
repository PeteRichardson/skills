---
name: merge-order
description: Show the open PRs in merge order, with what you need while merging — one line per PR: is it ready (CI, review, draft, conflicts), is it blocked by a stack parent or waiting for a restack, is a rebase likely after an earlier merge, and the next action (merge, restack, rebase, wait). The order itself comes from /fix-order's PR order (it runs that protocol fresh); this skill never makes its own. Writes a snapshot under .claude/tmp/merge-order/. Supports `/merge-order list`, `/merge-order open`, and `/merge-order clean` [--all]. Use when the user has open PRs and asks which to merge first, what is ready to merge, or what to do next with the PR queue. Formerly /pr-triage. Advisory only — never merges, pushes, or rebases.
disable-model-invocation: true
---

# Merge Order

The open PRs, in the order to merge them, with one line per PR that says what to do with it
now. The order is `/fix-order`'s. This skill adds only what you need **while merging**.

When invoked via `/merge-order`, follow the protocol below. Everything from here through the
`---` divider is the protocol Claude executes. The section after the divider is
documentation for humans.

---

## Operating principles

**One source of order.** `/fix-order` Phase 4.6 orders the open PRs (stack constraint,
critical tier, blast radius, staleness, size). This skill runs that protocol fresh and uses
its order as it is. It never re-ranks, never adds a rule of its own, and never shows an
order that differs from `/fix-order`'s. If the order looks wrong, the fix belongs in
`/fix-order`.

**The merge-time view only.** Per PR: ready or not, its stack state, whether a rebase is
likely, and the next action. Nothing that needs a decision about what to work next — that
is `/fix-order`.

**Advisory.** It never merges, pushes, rebases, force-pushes, comments, or resolves a
conflict. It reads (`gh pr list`, `gh pr diff`, `gh pr view`, `git log`) and writes under
`.claude/tmp/merge-order/`. Every merge invalidates the output.

## Phase 0: Subcommands

* **`/merge-order list`** — for every file in `.claude/tmp/merge-order/` (create the
  directory first if absent — an empty listing isn't an error), read its frontmatter (`prs`,
  `generated`), not the body. Make **one** `gh pr list --state all --json
  number,state,title,url,mergedAt,closedAt` call for the union of every `prs[].number`, and
  classify each file's PRs against that one result. For each file, print the filename, its
  `generated` timestamp, and its absolute path on one line, then two groups:

  ```
  MERGE_ORDER.md  (generated 2026-10-12 14:32)  /Users/pete/project/.claude/tmp/merge-order/MERGE_ORDER.md
      #8  ‼ Add rate limiting to /api/upload       https://github.com/org/repo/pull/8
      #7    Fix login redirect loop                https://github.com/org/repo/pull/7
      ---
      #5  ‼ Fix data loss on export bug            merged 2026-10-11  https://github.com/org/repo/pull/5
      #9    Old experimental sync flag             closed 2026-10-09  https://github.com/org/repo/pull/9
  ```

  - **Outstanding** (not `MERGED` or `CLOSED` in the live result): in `prs` array order,
    `‼` when the entry's `critical` is `true`. Plain text, no color.
  - A `---` line, only when both groups are non-empty.
  - **Merged/closed**: newest first, by `mergedAt` or `closedAt`, ending `merged <date>` or
    `closed <date>` from the live `state`. `CLOSED` is abandoned, never counted as merged.
  - Each line ends with the plain `url` (not a rendered hyperlink — raw OSC 8 codes print as
    garbage; see `docs/specs/2026-07-20-pr-triage-list-output-design.md`).

  Sort files newest `generated` first. A file without frontmatter: show filename and mtime,
  and say its status is missing. Stop here.
* **`/merge-order open`** — `open .claude/tmp/merge-order/` (macOS), or print the absolute
  path. Stop here.
* **`/merge-order clean`** — one `gh pr list --state all --json number,state` call for the
  union of every file's `prs[].number`. A file whose every PR is merged or closed is a
  removal candidate. Show the candidates and what is kept (and why), and ask before
  deleting. Stop here.
* **`/merge-order clean --all`** — delete everything in `.claude/tmp/merge-order/`. Show
  what will be deleted and ask first. Stop here.
* **`/merge-order`** — every open PR. Go to Phase 1.
* **`/merge-order #7 #8 #12`** — only those PRs. Go to Phase 1 with the scope noted.

## Phase 1: Get the order from `/fix-order`

Read `~/.claude/skills/fix-order/SKILL.md` and run its **PR-only sub-protocol** (see its
Phase 0): the open PRs, their linked issues' severity, the PR–PR overlaps, and Phase 4.6.
Do not invoke it through the Skill tool — it sets `disable-model-invocation: true`. Run it
fresh every time; never read an old `.claude/tmp/fix-order/` snapshot, which any merge
invalidates.

For a scoped run, give it only the named PRs. A named PR's stack parent that is outside the
scope stays outside it — name it in the PR's Stack cell instead.

From it, keep for each PR: its position, `critical`, its linked issues and their finding
IDs, its stack parent and whether that parent is open, the files it shares with each other
PR, and the overlap classification (incidental or likely collision).

If `~/.claude/skills/fix-order/SKILL.md` is missing, stop and say so. Do not make an order
here instead — that is the second source of order this skill exists to prevent.

## Phase 2: The merge-time view

One more call, for the state that changes minute to minute:

```bash
gh pr list --state open --limit 200 --json number,title,url,isDraft,reviewDecision,statusCheckRollup,mergeable,mergeStateStatus
```

Per PR, fill four cells:

* **Ready?** — the blockers GitHub knows, joined with `, `, or `ready`:
  - `draft` when `isDraft`,
  - `CI failing` / `CI pending` from `statusCheckRollup` (any `FAILURE`/`ERROR` → failing;
    else any `PENDING`/`IN_PROGRESS`/`QUEUED` → pending; no checks → say nothing),
  - `changes requested` / `review required` from `reviewDecision`,
  - `conflicts` when `mergeable` is `CONFLICTING` (conflicts with the base now, whatever
    the order).
* **Stack** — `—` when unstacked; `on #31 (open)` when the parent is open (blocked);
  `on #31 (merged) — restack` when the parent merged and the marker is not yet `resolved`.
* **Rebase likely?** — `—`, or `after #n` for each PR **earlier in the order** that shares a
  file with it, with `(collision)` after a pair `/fix-order` classified as a likely semantic
  collision. A stacked child is never "rebase likely" because of its own parent; the restack
  covers that.
* **Next** — the first row of this table that applies:

  | Condition | Next |
  |---|---|
  | Parent is open | `wait for #<parent>` |
  | Parent merged, not restacked | `/work-issue restack <n>` |
  | `conflicts` | `rebase` (the author resolves; never this skill) |
  | `draft` | `wait (draft)` |
  | `CI failing` | `fix CI` |
  | `changes requested` | `address review` |
  | `CI pending` | `wait for CI` |
  | No `docs/reviews/code-review_PR<n>_*.md` | `/code-review <n>`, then merge |
  | Otherwise | `merge` |

  Only the **first** PR in the order whose Next is `merge` (or `/code-review <n>, then
  merge`) is the next merge. For a later PR whose Next is also `merge`, write
  `merge after #<that PR>` — every merge can change the rest of the order.

## Phase 3: Deliverable

Before writing:

1. `mkdir -p .claude/tmp/merge-order`
2. Make sure `.claude/tmp/` is ignored **without changing a tracked file**:

   ```bash
   git check-ignore -q .claude/tmp/ || cat >> .git/info/exclude <<'EOF'

   # Added by the Claude Code /merge-order skill.
   # Ephemeral skill output. Excluded here rather than in .gitignore so it never
   # creates a commit diff. `git check-ignore -v <path>` will name this file as
   # the source. Delete this block to un-ignore.
   .claude/tmp/
   EOF
   ```

   Never write to the tracked `.gitignore`. When the fallback fires, say so once, and say
   that `git check-ignore -v .claude/tmp/` explains it later.
3. Filename: `MERGE_ORDER.md` for every open PR, `MERGE_ORDER-<numbers>.md` (ascending) for
   a scoped run.

Write `.claude/tmp/merge-order/<filename>`. The frontmatter keeps the shape `list`,
`clean`, and `pipeline/pipeline-status` read — `prs` first, one `  - number:` entry per PR,
in merge order:

```yaml
---
generated: <ISO 8601 timestamp>
prs:
  - number: 31
    critical: false
    next: merge
    issues:
      - number: 9
        finding: ~
  - number: 29
    critical: false
    next: "wait for #31"
    stack:
      parent_pr: 31
      blocked: true
    issues:
      - number: 8
        finding: F4
  - number: 12
    critical: false
    next: "fix CI"
    issues: []
---
```

`critical` is copied from `/fix-order`. `issues` is `[]` for a PR with no linked issue;
`finding: ~` means no recorded finding ID — never guess one. `stack` is absent on an
unstacked PR. Entries stay after a PR merges or closes, so `list` can show them.

Then the body, and print the same table to the console:

```markdown
| # | PR | Title | Ready? | Stack | Rebase likely? | Next |
|---|----|-------|--------|-------|----------------|------|
| 1 | #31 | Retry backoff | ready | — | — | merge |
| 2 | #29 | Option parsing | ready | on #31 (open) | — | wait for #31 |
| 3 | #12 | CSV export | CI failing | — | after #31 (collision) | fix CI |
```

Under the table, only when they apply:

* **Stack chains** as executable steps: `merge #31 → /work-issue restack 29 → merge #29`.
* **Critical-tier promotions**: which PR, which issue and severity, and which PRs now get
  more rebase work — copied from `/fix-order`'s rationale.
* **Likely collisions**: for each `(collision)` cell, one line on what both PRs change, so
  the person who rebases knows where a clean merge can still be wrong.

## Next in the pipeline

This is stage 5 of the review → issue → PR → merge pipeline (`~/.claude/skills/WORKFLOW.md`).
The merge itself is manual and is not this skill's to run. End with one line, naming the
actual PR:

> Next: merge #31 yourself, then re-run `/merge-order` — every merge changes the rest of this order.

Vary it only for these cases:

* **The next merge needs `/code-review <n>` first** — say that first.
* **The top PR needs a restack** — `/work-issue restack <n>` is the next step, not a merge.
  Merging first gives a PR diff that contains its parent's changes.
* **Nothing is ready** — name the first PR's Next (for example `fix CI on #12`) and say no
  PR can merge yet.
* **One open PR** — say it is the only one, give its Next, and skip the re-run half.

## Rules

* Never merge, push, rebase, force-push, comment, or resolve a conflict. Only read, and
  write under `.claude/tmp/merge-order/`.
* Never make or change the order. Use `/fix-order`'s Phase 4.6 order exactly; stop if that
  protocol is missing.
* `clean` and `clean --all` are the only deletes, and both show the candidates and wait for a
  yes first.
* Never infer an issue number or finding ID. `—` and `~` are correct for "none".
* A `(collision)` is a judgment call from `/fix-order` — present it as "likely", never as
  certain.
* If a `gh` call fails (auth, rate limit), stop and say so. Do not guess a PR's state.

## Repeat runs

Every run is fresh: the order is recomputed and the state re-read. If a file for the same
scope exists, read it first, and say what changed since then — which PRs merged or closed,
and which PRs' Next changed. A full run and a scoped run are tracked in separate files.

---

# Project documentation

Everything below is for humans. It is not part of the protocol.

## Usage

```
/merge-order                 # every open PR
/merge-order #7 #8 #12       # only these
/merge-order list            # past snapshots, live merged/closed state
/merge-order open            # the snapshot folder (macOS)
/merge-order clean [--all]   # remove old snapshots
```

Installed like every skill in this repo: a symlink `~/.claude/skills/merge-order ->
~/projects/skills/merge-order`. It needs `gh`, authenticated, and `/fix-order` installed
next to it.

## Why the order comes from `/fix-order`

This skill used to be `/pr-triage`, which made its own PR order from blast radius, a
severity override, and the stack constraint. `/fix-order` also had to know about open PRs,
because an issue that touches a PR's files must be placed around that PR. Two skills that
order the same PRs can give two different orders, and then neither can be trusted. So the
ranking rules moved into `/fix-order` Phase 4.6, unchanged, and this skill kept only the part
that changes minute to minute and matters at the moment you merge: is it ready, is it
blocked, will it need a rebase, and what do I do now.

## Why every merge needs a re-run

The order depends on which PRs share files with which. A merge changes the base for every
other PR: one that shared a file with the merged PR may now conflict, and a stacked child is
now waiting for its restack. A list you work down without re-running assumes none of that
happened.

## Limitations

- File overlap is necessary but not sufficient. Two PRs can change different files and
  still conflict in behavior (one renames a function the other calls). Run the tests after
  every merge and rebase.
- The Ready cell is GitHub's state at the moment of the run. CI and reviews change quickly.
- No tests or builds run here — it is an ordering view, not a merge check.

## License

Original, written for Peter's personal skills ecosystem. Freely modifiable.
