# Unified issue workflow — design

Status: designed, not yet implemented. Touches `/issue-triage`, `/make-issues`,
`/work-issue`, `/code-review`, `/pr-triage`, `/pipeline` (and `pipeline-status`),
`WORKFLOW.md`, and this repo's `AGENTS.md`. Adds `/fix-order`. Renames `/pr-triage` to
`/merge-order`.

Keeps the `STACK` model of `2026-07-30-stacked-prs-design.md`. It moves from
`/issue-triage` to `/fix-order` with no change.

## Problem

Two sets of skills are installed side by side, and they describe two different workflows:

- **This repo** (linked one skill at a time into `~/.claude/skills/`): review → `/make-issues`
  → `/issue-triage` → `/work-issue` → `/pr-triage` → merge.
- **Matt Pocock's skills** (installed by `npx skills`, tracked in `~/.agents/.skill-lock.json`,
  and partly as the `mattpocock-skills:` plugin): grill → `/to-spec` / `/to-tickets` →
  `/triage` → `/implement`.

The overlap causes four problems:

1. **Name collision.** Both sets have a `code-review`. The installer copied Matt's into
   `~/.claude/skills/code-review/` first. The link for this repo's skill then landed *inside*
   that folder (`ln -s` into an existing directory does that, with no error). So
   `/code-review` runs Matt's skill, and its report has a format that `/make-issues` cannot read.
2. **Two "triage" ideas.** `/issue-triage` decides order and grouping. Matt's `/triage` moves
   one issue at a time through state labels and verifies it. The user cannot easily say which
   one to run.
3. **Hand-filed issues are second-class.** Labels, a summary and a fingerprint come only from
   `/make-issues`. The fix for a hand-filed issue (`/make-issues backfill`) is hidden inside the
   skill that *files* issues. Issues from `/to-tickets` get none of them.
4. **The ordering and merge stages are hard to use.** `/issue-triage` mixes ordering with
   grouping and stacking (`GROUP`, `STACK`). The user does not use the `/pr-triage` output
   well, because the stack model is hard to keep in mind.

Also, `WORKFLOW.md` has no link in `~/.claude/skills/`, but seven skills point at
`~/.claude/skills/WORKFLOW.md`. `AGENTS.md` still says `~/.claude/skills` is a link to this
repo. That stopped being true on 2026-10-06.

## Goals

- One workflow. Matt's skills fit into it at clear points.
- **Never edit Matt's skills.** He updates them often, and an update must need no follow-up
  edit. His skills are used as they are, uninstalled, or called by name.
- Every issue, from every source, passes through one gate that makes it complete.
- Ordering needs only the issues. No review report must exist.
- Fewer ideas to learn at the merge stage.

## Non-goals

- Not automatic merging. Merge stays a manual step.
- Not a replacement for Matt's `/triage` when the user wants its full one-issue treatment
  (questions, grilling, an agent brief). The user can still type `/triage #n` by hand.
- Not a closed set of review engines. `/code-review` takes new engines later.

## The workflow

```
            Source code
           /           \
  /project-review    /code-review  ──(engine: open-code-review-delegate,
     (architecture)        |          this repo's own review, or
           \               |          mattpocock-skills:code-review)
  you ──► /grill-with-docs ──► spec
   |           \               |
   |            /make-issues  or  /to-spec + /to-tickets
   |                   |
   └──(by hand)──►  ISSUES  ◄──►  /issue-triage   (summary, labels, fingerprint; --verify)
                       |
                       ├──►  /fix-order   ──►  .claude/tmp/fix-order/FIX_ORDER.md
                       |
                       ▼
          /work-issue (one issue or one group → one PR)
          /implement-spec (one big spec → one integration branch)
                       |
                       ▼
                      PRs  ──►  /code-review <pr>  (findings go back to ISSUES)
                       |
                       ├──►  /merge-order ──►  .claude/tmp/merge-order/MERGE_ORDER.md
                       ▼
                     merge (manual)
```

## Decisions

### D1. This repo's skill owns the name `code-review`, and it is pluggable

- Remove Matt's `code-review` from the installer (`npx skills remove code-review`, or remove
  its entry from `~/.agents/.skill-lock.json` if the command also deletes the folder).
  This is an uninstall, not an edit. Matt's version stays available as
  `mattpocock-skills:code-review` (plugin), with a prefix that cannot collide.
- Replace the folder `~/.claude/skills/code-review/` with a link to this repo's
  `code-review/`.
- `/code-review` becomes a wrapper. It runs one **engine** and always writes **one report
  format**: the current `code-review_*.md` format that `/make-issues` already parses. Engines:
  - `open-code-review-delegate` (the new default),
  - the current review protocol in this skill,
  - `mattpocock-skills:code-review` (for its Standards + Spec check of a PR against its issue).
- The skill must **not** set `disable-model-invocation: true`. Matt's `/implement` calls the
  skill `code-review` by name when it finishes. That call then runs this wrapper.

### D2. `/issue-triage` becomes the gate that completes issues

The old `/issue-triage` job (order and grouping) moves to `/fix-order` (D3). The name
`/issue-triage` now means: *make each issue complete*. For each issue in scope, it fills
only what is missing:

| Item | Source |
|---|---|
| `**SUMMARY:**` block | Moved from `/make-issues backfill` 5c, unchanged rules |
| `severity:`, `category:`, `effort:` labels | Moved from `/make-issues backfill` 5b, unchanged rules |
| Fingerprint marker | Moved from `/make-issues backfill` 5a, unchanged rules |
| Verification | New, **only with `--verify`**, see below |

Scope: every open issue, or `#n ...`. It works on issues from any source, with no exceptions,
including issues that `/to-tickets` filed with `ready-for-agent`. It shows one confirmation
table and applies nothing before the user answers (same as `backfill` now).

`/make-issues backfill` is removed. `/make-issues` only files issues, then **calls
`/issue-triage`** on the issues it just filed. So the summary rules, the label
vocabulary, the label seeding, and the category resolution live only in `/issue-triage`.

`/make-issues` still applies the labels that the **report states** (`severity:`, `source:`,
and `effort:` when the report has it). They are facts from the report, not inferred values.
`/issue-triage` then fills only the namespaces that are still empty. Example: a `/code-review`
finding has no effort, so `/issue-triage` adds `effort:`.

#### Verification (opt-in: `/issue-triage --verify`)

Verification is **off by default**, on every path. Nothing runs it automatically: not
`/issue-triage`, not `/make-issues`, not `/work-issue`. The user runs
`/issue-triage --verify [#n ...]` when they want it. This is a trial. After some use, the user
decides whether a path should verify by default. Good candidates, recorded for that decision:

- hand-filed issues (they have no evidence yet), and
- `/work-issue`, just before it codes (the freshest moment).

A review finding already has evidence (`file:line`, a snippet) from the `HEAD` it was found at,
so `/make-issues` is the weakest candidate.

The idea comes from Matt's `/triage` step 3. The text is written here, not copied from his
file, so his updates never conflict with it.

1. **Bug:** reproduce the claim from the issue's own steps, or from a minimal case that the
   issue describes. **Enhancement, refactor, test gap:** confirm that the gap is still there
   (the code still does what the issue says).
2. Result is one of: `confirmed` (with the code path and the commands that showed it),
   `not-reproduced` (what was tried), `not-enough-detail` (the questions that block it),
   `already-fixed` (where the fix is).
3. **Write the result into the issue, once.** A new comment with a visible section and a
   hidden marker:

   ```markdown
   ## Verification

   **Result:** confirmed at `<short sha>`

   **Steps to reproduce:**
   1. ...

   **Code path:** `src/filelist.rs:66` (`read_filelist`) → `src/options.rs:89` (`resolve`)

   <!-- issue-verification
   result: confirmed
   sha: <full sha>
   -->
   ```

4. **Never verify the same issue again.** `--verify` skips an issue that has an
   `issue-verification` marker. It verifies again only when:
   - the user asks for it (`/issue-triage --reverify #n`), or
   - the issue body or a comment by a person changed after the marker's comment.

   A new commit alone is **not** a reason. Old results stay useful, and the `sha:` field shows
   how old they are.
5. When a marker exists, `/work-issue` reads the **Steps to reproduce** back and uses them as
   its first failing test (with `/tdd`). It does not make them again. When there is no marker,
   `/work-issue` works as it does now.

`already-fixed` and `not-enough-detail` are reported. They never close an issue or add a label.
`/fix-order` uses them (D3).

#### Labels from Matt's skills

`/to-spec` and `/to-tickets` add `ready-for-agent`. `/issue-triage` leaves that label alone.
It adds no `bug`/`enhancement`/state labels of its own: the `severity:`/`category:`/`effort:`
set is the one vocabulary. Matt's `/triage` stays installed for manual use, and
`docs/agents/triage-labels.md` stays in each repo, because `/to-spec` and `/to-tickets` need it.

### D3. New `/fix-order` ranks the issues and finds groups

Input: the open issues (labels, fingerprints, verification markers) and the **open PRs**
(diffs, linked issues). **Nothing else.** No review report needs to exist. If an issue has no
fingerprint or no labels, `/fix-order` lists it as "run `/issue-triage` first" and ranks it
last. It does not guess.

**A PR is an issue with a known fix.** Issues and PRs are one stream of changes, and an order
can make a PR's fix wrong (another change lands first and moves the code under it). So
`/fix-order` puts open PRs in the same graph as issues:

- A PR's files come from its diff. An issue's files come from its fingerprint.
- An issue that `OVERLAPS` or `COLLIDES` with an open PR gets a `DEPENDS-ON` edge to that PR
  (merge the PR first), or a `STACK` on it (build on the PR's branch). It never gets a free
  position that ignores the PR.
- An issue that an open PR already closes is excluded, as now.
- Small projects have few open PRs, so the extra cost is small.

It is the old `/issue-triage` Phases 1–4.5 (eligible set, relationship graph, dispositions,
order, stacks), with these changes:

- **`STACK` stays.** Phase 4.5 moves over unchanged. `/work-issue` keeps `restack`.
- **Blast radius** joins the ranking: the number of other open issues and open PRs that touch
  the same files. A fix that touches less goes first when severity is equal, so later work
  stays easy to merge.
- **Verification result** joins the dispositions: `already-fixed` → `CLOSE-MOOT` proposal,
  `not-enough-detail` → `NEEDS-DECISION`, `not-reproduced` → `NEEDS-DECISION`.
- Order of the rules: `DEPENDS-ON` (hard) → severity → blast radius → effort.
- Dispositions: `WORK`, `GROUP`, `STACK`, `NEEDS-DECISION`, `DEFER`, `CLOSE-MOOT`.
  Backlog-type labels exclude an issue, as now.
- An unverified issue is not ranked lower. Most issues are unverified while verification is
  opt-in.
- Output: `.claude/tmp/fix-order/FIX_ORDER.md`. It is temporary and made again on each run.

`/work-issue` batch mode reads `/fix-order`'s protocol where it now reads `/issue-triage`'s.

### D4. `/work-issue` for one issue or one group; `/implement-spec` for a big spec

- `/work-issue`: one `WORK` issue or one `GROUP` → one worktree, one branch, one PR. All
  branches start from the base branch (or from the parent, for a `STACK`). It reads the
  issue's **Verification** section first, when one exists.
- Matt's `/implement-spec`: a spec from `/to-spec` with its `/to-tickets` tickets → one
  integration branch. Used as it is.
- Matt's `/implement`: a small piece of work on the current branch. Used as it is.

### D5. `/pr-triage` becomes `/merge-order`

Renamed so that the name says what it gives. **It no longer decides an order.** `/fix-order`
is the one source of order for issues and PRs together, so two tools never give two different
orders for the same PRs (Q5).

`/merge-order` takes the PR order from `/fix-order` (it runs `/fix-order`'s protocol, as
`/work-issue` batch mode does) and adds only what the user needs **while merging**, one line
per PR:

- **Ready?** CI state, review state, draft or not.
- **Stack:** is its parent merged? If not, it is blocked. If the parent merged, the PR needs
  `/work-issue restack` first.
- **Rebase likely?** Does it overlap a PR earlier in the order? Then it may need a rebase after
  that merge.
- **Next action:** one command or one click (merge, restack, rebase, wait).

The blast-radius ranking, the severity override, and the stack constraint move from
`/pr-triage` into `/fix-order`.

A guided lesson on the dispositions (`WORK`, `GROUP`, `STACK`, …), on stacked PRs and
`restack`, and on how to read `/merge-order`, comes after steps 3 and 5. The user then decides
whether stacks stay.

## Risks

- **`/issue-triage` changes meaning.** Old snapshots, `WORKFLOW.md`, `pipeline-status`, and
  the "Next in the pipeline" lines of six skills all use the old meaning. They must all change
  in the same commit series, or a user follows a stale hand-off.
- **Matt's skills can change.** If `/implement` stops calling `code-review` by name, or
  `/to-tickets` changes its labels, the fit changes. Nothing breaks, because no skill here
  depends on his text. But check the fit after a large update.

## Implementation order

1. **Fix the install** (no behavior change in the skills): D1's uninstall and link, a link
   for `WORKFLOW.md`, and a correct description of the install in `AGENTS.md`.
2. **`/issue-triage` as the gate** (D2), with `backfill` removed from `/make-issues` and
   `/make-issues` calling `/issue-triage`. `--verify` and `--reverify` are part of this step.
3. **`/fix-order`** (D3), and `/work-issue` batch mode pointed at it (D4). `/work-issue` reads
   a Verification section when one exists.
4. **`/code-review` as a wrapper** (D1) with `open-code-review-delegate` as the default engine.
5. **`/merge-order`** (D5): `/pr-triage` renamed and reduced to the merge-time view.
6. **`WORKFLOW.md`, `/pipeline`, `pipeline-status`**, and every "Next in the pipeline" line.
7. **Lesson** on dispositions, stacks, `restack`, and `/merge-order` output.

Each step is one PR in this repo, and leaves the workflow usable.

## Open questions

- **Q1.** `open-code-review-delegate` output to the fixed report format: does the wrapper
  convert its output, or does it give the engine the format as an instruction? Needs a look at
  what the engine writes.
- **Q6.** After the verification trial: should any path verify by default (hand-filed
  issues, `/work-issue` before it codes)?

### Answered

- **Q2.** `/make-issues` calls `/issue-triage`. Verification is opt-in only
  (`/issue-triage --verify`), as a trial. No path verifies by default (D2).
- **Q3.** `STACK` and `/work-issue restack` stay. The lesson (step 7) comes first; the user
  decides after it.
- **Q4.** `/fix-order` reads open PRs. A PR is an issue with a known fix, and the order can make
  that fix wrong (D3).
- **Q5.** `/fix-order` is the one source of order. `/merge-order` takes that order and adds
  only the merge-time view (D5).
