---
name: fix-order
description: >-
  Assess a set of open GitHub issues, together with the open PRs, and recommend what to work, in
  what order, what to combine into a single PR, what to close as moot, and what needs a human
  decision first. Needs only the issues and PRs — no review report. Produces a relationship graph
  (file/symbol overlap, declared dependencies, supersession), a disposition per issue, an ordered
  work plan ranked by dependency, severity, blast radius, then effort, and a merge order for the
  open PRs. It is the one source of order: /merge-order reads its PR order, and /work-issue batch
  mode runs this protocol to order its queue. Subcommands: `list`, `open`, `clean` [--all], and
  `label`, which puts a `status: needs-decision` label on GitHub for UI visibility. Use when the
  user has several open issues and asks which to fix first, how to order the backlog, or to
  prioritize the issue queue. Advisory only — creates, closes and modifies nothing; `label` is the
  sole mutation, and it asks first.
disable-model-invocation: true
---

# Fix Order

A Claude Code skill that looks at a set of open issues and recommends a **fix plan** — not merely an order. Some issues shouldn't be worked at all because another issue moots them; some shouldn't be worked *separately* because they rewrite the same function; some can't be worked yet because they need a decision only the maintainer can make.

When invoked via `/fix-order`, follow the protocol below. Everything from here through the `---` divider is the protocol Claude executes. The section after the divider is documentation for humans installing or maintaining this skill.

---

## Operating principles

**The output is a disposition per issue, not a ranking.** A linear order cannot express "don't work this one at all" or "work these two as one change," which are the two highest-value things this skill produces. Ranking is the last step, applied only to what survives.

**A PR is an issue with a known fix.** Open PRs and open issues are one stream of changes. An order that ignores a PR can make its fix wrong: another change lands first and moves the code under it. So open PRs go into the same graph as the issues (Phase 1.5, Phase 2), and an issue that touches a PR's files never gets a position that ignores the PR.

**Ordering needs only the issues and the PRs.** No review report must exist. What an issue contributes comes from its labels, its fingerprint, and its verification result — the things `/issue-triage` makes complete. An issue without them is not guessed at; it is listed as "run `/issue-triage` first" and ranked last.

**A fix-order run is advisory.** It never creates, closes, labels, comments on, or edits an issue; never creates a branch, worktree, or PR. It reads (`gh issue list`, `gh issue view`, `gh pr list`, `gh pr diff`, `git log`, source files) and writes under `.claude/tmp/fix-order/`. Every disposition is a recommendation the user or `/work-issue` acts on — in particular `CLOSE-MOOT` and `DEFER` are proposals requiring confirmation, never actions.

The single exception is the **`label` subcommand**, which the user invokes separately and which syncs exactly one label (`status: needs-decision`) after showing what it will change. A fix-order run never applies it; typing `/fix-order label` does.

**Deferral is the maintainer's call, not this skill's.** Proposing that an issue be deferred is useful; applying a `backlog` label is a priority decision belonging to the user. This skill proposes; it never applies a deferral label, and `label` won't either — see "Why `status: needs-decision` is labelled but `backlog` isn't" below for why those two aren't the same act.

**Axes stay separate.** Dependency order, severity, blast radius, and effort are four different things. Never blend them into a score — tier them, and state the tradeoff in prose when they conflict. (Same reasoning as Phase 4.6's critical tier for PRs.)

## Phase 0: Subcommands

Check the invocation before doing anything else:

* **`/fix-order list`** — for every file in `.claude/tmp/fix-order/` (create the directory first if absent — an empty listing isn't an error), read its frontmatter (`units`, `generated`) rather than the full report. Then make **one** `gh issue list --state all --json number,state,title,url,closedAt` call covering the union of every issue number across all files, and classify each file's issues against that single result — don't make a separate API call per file.

  For each file, print the filename, its `generated` timestamp, and its resolved absolute path on one line, then two groups below it:

  ```
  FIX_ORDER.md  (generated 2026-07-26 15:04)  /Users/pete/project/.claude/tmp/fix-order/FIX_ORDER.md
      1  #18, #19  ‼ set_field: precedence + agreement      https://github.com/org/repo/issues/18
      2  #11, #15    SPARQL retry set + Retry-After         https://github.com/org/repo/issues/11
      ?  #12         Rating priority (NEEDS-DECISION)       https://github.com/org/repo/issues/12
      ---
      #20    Sloop-of-war era filter    closed 2026-07-26   https://github.com/org/repo/issues/20
  ```

  - **Outstanding** (issues the live result doesn't report as `CLOSED`): one line per work unit, in `units` array order, prefixed with its order number — or `?` for a unit whose disposition is `HOLD`, `NEEDS-DECISION` or `DEFER`, which have no position in the sequence. Prefix with `‼` when the unit's frontmatter `critical` is `true`. No color — plain text only.
  - A `---` separator line, only if both groups are non-empty.
  - **Closed**: one line per issue, newest `closedAt` first, ending with `closed <date>`.
  - Each line ends with the issue's plain `url` from the live result — plain text, not a rendered hyperlink.

  Sort files newest-generated first (from frontmatter `generated`, not file mtime). Stop here; don't run the ranking.
* **`/fix-order open`** — run `open .claude/tmp/fix-order/` (macOS). If `open` isn't available, print the absolute path. Stop here.
* **`/fix-order clean`** — read every file's frontmatter issue numbers, make one `gh issue list --state all --json number,state` call covering the union. Any file whose entire issue set is now closed is a removal candidate. Show candidates plus what's being kept and why, and ask for confirmation before deleting. Stop here.
* **`/fix-order clean --all`** — unconditional wipe of `.claude/tmp/fix-order/`. Show what will be deleted, ask for confirmation. Stop here.
* **`/fix-order label`**, or **`/fix-order label #11 #15`** — sync the `status: needs-decision` label against an existing snapshot so the queue's blocked issues are visible in the GitHub UI. **This is the only subcommand that mutates GitHub.** See "The `label` subcommand" below. Stop here; don't run the ranking.
* **Executed as a PR-only sub-protocol by `/merge-order`** — `/merge-order` reads this file and runs only what the PR order needs: Phase 1.5 step 5 (the open PRs), the linked issues' `severity:` labels, the PR–PR `OVERLAPS` edges of Phase 2, and Phase 4.6. No issue is ranked, and no snapshot is written here — `/merge-order` writes its own. This keeps one source of order without paying for the issue analysis on every merge.
* **`/fix-order`** (no args) — full-queue run, proceed to Phase 1.
* **`/fix-order #11 #15 #18`** (issue numbers) — scoped run limited to those issues, proceed to Phase 1 with the scope noted.
* **Executed as a sub-protocol by `/work-issue` batch mode** — not via the Skill tool (`disable-model-invocation: true` puts this skill out of reach of it), but by `/work-issue` reading this file and running Phases 1.5–5, including Phase 4.5, directly. The caller supplies an already-filtered candidate set: skip Phase 1, use the supplied set verbatim, proceed to Phase 1.5, and still write the snapshot. Phase 1.5 is not skipped — the open PRs and the verification results are inputs to the graph, not filters.

## Phase 1: Enumerate the eligible set

1. Confirm the repo.
2. `gh issue list --state open --limit 200 --json number,title,body,comments,labels,createdAt,updatedAt,url`
3. **Exclude already-deferred issues.** Any issue carrying `backlog`, `icebox`, `someday`, `someday-maybe`, `future`, `deferred`, `on hold`, `wontfix`, or a `priority/backlog`-style namespaced equivalent is out of scope — that decision is already made. List them once as excluded, with the label that fired, so a mislabelled issue stays visible. This vocabulary is shared with `/work-issue`'s Phase 1 deferral check; keep the two lists in sync.
4. **Exclude already-addressed issues** using `/work-issue`'s Phase 2 checks: an open PR whose `closingIssuesReferences` names it, a PR `headRefName` matching `(^|-)I?<n>(-|$)`, or a local/remote branch matching the same pattern. Report each with which check fired.

## Phase 1.5: Gather the evidence

`/work-issue` batch mode runs this phase too. It reads; it filters nothing.

1. **Fingerprint.** For each issue, scan the body and every comment for `<!-- project-review-finding ... -->` (written by `/make-issues` or `/issue-triage`) and extract `file:`, `category:`, `keywords:`, and `finding_id:` if present. `finding_id` is absent on every fingerprint `/issue-triage` wrote — that is normal. Never infer a `finding_id` that isn't recorded.
2. **Labels.** Read the `severity:`, `effort:`, and `category:` labels.
3. **Completeness.** An issue is **incomplete** when it has no fingerprint, or no `severity:` label, or no `effort:` label — the three things Phases 2 and 4 rank on. Mark it `incomplete` and do not fill the gap: no file guessed from the prose, no severity guessed from the title. `/issue-triage` owns those values. An incomplete issue still goes through Phase 3 (its own text can make it `NEEDS-DECISION` or `DEFER`), but Phase 2 gives it only the edges its fingerprint supports, and Phase 4 ranks it after every complete unit.
4. **Verification result.** Scan the comments for `<!-- issue-verification ... -->` (written by `/issue-triage --verify`). When there is more than one, use the newest comment's. Record `result:` and `sha:`. No marker is normal — verification is opt-in — and an unverified issue is **not** ranked lower for it.
5. **Open PRs.** One call:

   ```bash
   gh pr list --state open --limit 200 --json number,title,headRefName,baseRefName,isCrossRepository,isDraft,closingIssuesReferences,files,body
   ```

   A PR's files come from `files` (the paths in its diff). Also note:
   - its linked issues (`closingIssuesReferences`) and their `severity:` labels,
   - whether the body has a `<!-- work-issue-stack` marker without `resolved: true` — then it is already a stacked child, at depth (its parent's depth + 1). Follow `parent_pr` to count. Otherwise a PR is depth 1.
   - `isCrossRepository: true` — its branch is not on `origin`, so nothing can stack on it.

   Phase 1 step 4 already excluded the issues these PRs close. The rest of the PRs are nodes in the Phase 2 graph.

## Phase 2: Build the relationship graph

Nodes are the surviving issues and the open PRs. For every pair, determine which of these edges hold. Each requires different evidence; don't collapse them. A pair of two PRs gets only `OVERLAPS` here, from their diffs; Phase 4.6 classifies those pairs and orders the PRs.

* **`OVERLAPS`** — both change the same file. An issue's files come from its fingerprint `file:` field; a PR's from its diff. An incomplete issue without a fingerprint has no files and gets no `OVERLAPS` edge. Verify an issue's path still exists; an issue filed against a since-renamed file is stale, and the *current* path is what matters. Pure set intersection, no judgment yet.
* **`COLLIDES`** — both change the same *function or symbol*, not merely the same file. This requires actually opening the source and locating what each issue proposes to change — and, for a PR, reading `gh pr diff <n>` to see which symbols it changes. `OVERLAPS` without `COLLIDES` is incidental adjacency (two issues adding separate functions to one module) and does **not** justify grouping.
* **`DEPENDS-ON`** — issue A cannot be correctly implemented before issue B lands. Two sources: declared (scan issue bodies and comments for "depends on #N", "blocks #N", "prerequisite", "should land before #N") and semantic (A's fix is only well-defined given B's design decision). Declared dependencies are facts; semantic ones are judgment calls and must be labelled as such.
* **`MOOTS`** — fixing B makes A unnecessary, not merely easier. A high bar: B must remove the condition A describes, not just touch the same code. If B merely makes A smaller, that is `COLLIDES`, not `MOOTS`.
* **`DUPLICATES`** — A and B describe the same defect, filed twice.

**Edges to an open PR.** An issue that `OVERLAPS` or `COLLIDES` with an open PR never gets a free position:

* **`COLLIDES` with a PR** → the issue `DEPENDS-ON` that PR. It waits until the PR merges, then it is worked on the new code. It is not stacked: two PRs that rewrite one function hand the reviewer two half answers (the same reason Phase 4.5 never stacks a `COLLIDES` pair).
* **`OVERLAPS` (without `COLLIDES`) a PR** → a stack candidate. Phase 4.5 stacks the issue on the PR's branch.
* **`MOOTS` or `DUPLICATES` from a PR** → the PR's fix removes the condition the issue describes, but the PR does not link it. The issue is `CLOSE-MOOT`, naming the PR, with the same high bar as between issues.

Record the evidence for each edge. An edge asserted without evidence is the failure mode this phase exists to prevent.

## Phase 3: Assign a disposition

Every issue gets exactly one. Apply in this order — earlier dispositions win:

| Disposition | Assign when | Effect |
|---|---|---|
| `CLOSE-MOOT` | A `MOOTS` or `DUPLICATES` edge points at it (from an issue or an open PR), or its verification result is `already-fixed` | Recommend closing with a comment naming the superseding issue or PR, or the fix the verification found. **Never worked.** |
| `NEEDS-DECISION` | The issue's own text says a policy/domain decision is required, or its fix has materially different valid outcomes the issue doesn't choose between, or its verification result is `not-enough-detail` or `not-reproduced` | Pulled out of the sequence. The user decides before any code is written. For a verification result, the question is the one the verification comment recorded: answer the blocking questions, or say whether a bug that did not reproduce is still real. |
| `GROUP` | It `COLLIDES` with one or more other issues | Combined with them into **one** work unit → one branch, one PR closing all of them. |
| `DEFER` | It is genuinely speculative, blocked on absent data, or scoped as a future idea | Proposed as a `backlog` candidate. **Never labelled by this skill.** |
| `WORK` | Everything else | Worked on its own, in sequence position n. |

`NEEDS-DECISION` outranks `GROUP` deliberately: a decision issue must not be silently absorbed into a grouped PR where the decision gets made as an implementation detail.

A verification result is evidence, never an action. `already-fixed` gives a `CLOSE-MOOT` **proposal**; the issue stays open until the user closes it. A verification `confirmed` changes no disposition.

`GROUP` is between issues only. An issue that `COLLIDES` with an open PR is not grouped into that PR — the PR already exists, and adding to it is its author's call. Phase 4 holds the issue until the PR merges.

A **work unit** is one `WORK` issue or one `GROUP` set. Units, not issues, are what Phase 4 orders and what `/work-issue` turns into branches.

## Phase 4: Order the work units

Rank only `WORK` and `GROUP` units. `NEEDS-DECISION`, `DEFER`, `CLOSE-MOOT`, and `HOLD` have no position.

0. **Units that wait on an open PR.** A unit with a `DEPENDS-ON` edge to an open PR (from a `COLLIDES`, or declared in the issue text) cannot be worked until that PR merges. It becomes `HOLD`, with `held_for: "PR #<n> must merge first"`, and has no position. A unit that depends on a held unit is held too, for the same PR.
1. **Dependency order first.** Topologically sort the rest on `DEPENDS-ON`. This is a hard constraint, not a preference — it outranks everything below. Report a cycle rather than breaking it arbitrarily.
2. **Severity tier.** Within what the dependency order leaves free, `severity: Critical` then `High` before `Medium`/`Low`. For a `GROUP`, use its highest severity. Read severity from labels; if the repo has no severity labels, say so once and skip this step rather than inventing a scheme.
3. **Blast radius.** Within one severity tier, the unit that touches less goes first, so later work stays easy to merge. A unit's blast radius = the number of *other* open issues (outside the unit) and open PRs that share at least one file with it — its `OVERLAPS` edges, counted once per node. Ascending.
4. **Effort tiebreaker.** `effort: S` before `M` before `L`, so the queue shrinks fastest. Never let effort override severity, blast radius, or dependency.
5. **Incomplete units last.** A unit with any incomplete issue (Phase 1.5) goes after every complete unit, in issue-number order. Its severity and files are unknown, so any position above that would be a guess. The deliverable lists each one with "run `/issue-triage` first".

When the axes conflict — a High-severity issue that must wait on a Medium one, or a Critical fix with the worst blast radius — state it in prose in the deliverable rather than hiding it in the ordering.

## Phase 4.5: Form stacks

Phase 4 produced an order. This phase reads it and decides which units branch from the base
and which branch from the unit before them.

Walk the ordered list from position 1, considering only units Phase 3 dispositioned `WORK`.
`GROUP` units are skipped — a `GROUP` can be a parent, but is never itself converted. For
each `WORK` unit, look for an `OVERLAPS` edge (from Phase 2) to any unit ranked **earlier**
in this same order:

* **No earlier overlap** → stays `WORK`. Branches from the base, as today.
* **An earlier overlap** → becomes `STACK`, parented to the **nearest** such unit. It gets
  branched from that unit's branch and its PR is based on it.
* **Would be the 4th link in a chain** → becomes `HOLD` instead. Not worked this batch.

Chains form transitively: if #15 stacks on #11 and #18 overlaps #15, then #18 stacks on #15,
giving a depth-3 chain #11 → #15 → #18. A 4th overlapping unit is `HOLD`.

**Stacking on an open PR.** An open PR is earlier than every unit in this order — its fix
already exists. So a `WORK` unit with an `OVERLAPS` edge (without `COLLIDES`) to an open PR
is a stack candidate too:

* An overlap with an earlier-ranked **unit** wins over an overlap with a PR: the nearest
  earlier unit is the parent, as above.
* Only PRs overlap → the parent is the PR that shares the most files with the unit, then the
  lowest PR number. The unit becomes `STACK` with `parent_pr:` instead of `parent_order:`.
  Its depth is the PR's depth (Phase 1.5) + 1, under the same cap.
* The PR is from a fork (`isCrossRepository: true`) → its branch is not on `origin`, so the
  unit cannot branch from it. The unit becomes `HOLD`, `held_for: "PR #<n> (from a fork) must
  merge first"`.
* A unit that overlaps more than one branch can stack on only one. Name the others in the
  Stack detail as "rebase likely after #<n> merges".

`STACK` is deliberately **not** in Phase 3's precedence table, and that table is unchanged.
Phase 3 can't assign it: whether a unit stacks depends on which units rank ahead of it, which
isn't known until Phase 4 has run. This phase only ever converts a `WORK` unit into `STACK`
or `HOLD` — it never touches `GROUP`, `NEEDS-DECISION`, `DEFER`, or `CLOSE-MOOT`. An
incomplete unit is never stacked and never a parent: it has no fingerprint files to base the
overlap on.

A `GROUP` unit can *be* a parent — its branch is a branch like any other — but is never
itself converted.

| Disposition | Assigned when | Effect |
|---|---|---|
| `STACK` | `OVERLAPS` (without `COLLIDES`) an earlier-ranked unit or an open PR, within the depth cap | Branched from that unit's or PR's branch; PR based on it; merges after it. |
| `HOLD` | Would be the 4th link in a chain, or would stack on a PR from a fork, or (Phase 4 step 0) waits on an open PR | Skipped this batch, reported for the next. `order: ~`. |

**Why `COLLIDES` is excluded:** those are already `GROUP`ed into one PR by Phase 3, which is
strictly better — two stacked PRs that rewrite the same function hand the reviewer two half
answers. Stacking is for the `OVERLAPS` band only, which Phase 2 deliberately leaves
ungrouped (see "Why file overlap alone doesn't justify grouping").

**Why depth 3:** a PR rejected at the bottom of a chain forces a restack of everything above
it. That cost grows with depth; the benefit doesn't.

## Phase 4.6: Order the open PRs

The open PRs get a merge order here, so one skill gives one order for issues and PRs
together. `/merge-order` reads this order; it never makes its own. The PRs are ranked
among themselves, as their own list: a PR already exists, so it never waits behind an issue,
and the issue units were already placed around the PRs (Phase 4 step 0, Phase 4.5).

For PRs the rules are those that cost the least rebase work, in this order:

1. **Stack constraint (hard).** For each PR with an unresolved `work-issue-stack` marker
   (Phase 1.5), the parent merges before the child. A chain (the parent plus every PR
   stacked on it, directly or transitively) moves as **one block**, at its root's rank, and
   unpacks in link order. A marker whose `parent_pr` already merged is a child waiting for
   its restack, not a stack member: it is unblocked, and the restack is outstanding. A
   marker with `resolved: true` is ignored — that PR is an ordinary one.
2. **Critical tier.** A PR whose linked issue has `severity: Critical` (or the repo's own
   critical/P0, security, data-loss, or crash label — check what this repo uses) goes ahead
   of every other PR, whatever its blast radius. Order the critical tier among itself by the
   rules below. A chain with a critical PR anywhere in it promotes as one block, parent
   first. Lower labels (`High`, `P2`, `enhancement`) promote nothing: the fix exists, so the
   cost of a short wait is small, and only genuine urgency is worth extra rebase work for
   the rest of the queue. If the repo has no severity labels, say so once and skip.
3. **Blast radius**, ascending: the number of *other open PRs* that share at least one file
   with it. Merging it forces a rebase on each of them. A stacked child's files are only its
   own: `/work-issue` bases its PR on the parent's branch, so its diff never contains the
   parent's files — no correction is needed.
4. **Staleness**, older `updatedAt` first: drift gets worse whether or not anyone watches
   the PR.
5. **Size**, smaller `additions + deletions` first, last resort only.

When a PR jumps the queue by the critical tier, say in the deliverable which PR, which
issue and severity, and which other PRs now get more rebase work for it.

For every pair of PRs that share a file, read both diffs and classify the overlap, as
Phase 2 does for issues: **incidental adjacency** (near each other, no interaction) or
**likely semantic collision** (the same function, invariant, or logic path). A likely
collision is a judgment call — label it so. It is what a careless rebase resolves into
something that merges cleanly and is wrong, so the deliverable names it.

## Phase 5: Deliverable

This project uses `.claude/tmp/` as the shared convention for ephemeral skill output, namespaced per-skill. Before writing anything:

1. `mkdir -p .claude/tmp/fix-order`
2. Ensure `.claude/tmp/` is ignored — **without modifying any tracked file**:

   ```bash
   git check-ignore -q .claude/tmp/ || cat >> .git/info/exclude <<'EOF'

   # Added by the Claude Code /fix-order skill.
   # Ephemeral skill output. Excluded here rather than in .gitignore so it never
   # creates a commit diff. `git check-ignore -v <path>` will name this file as
   # the source. Delete this block to un-ignore.
   .claude/tmp/
   EOF
   ```

   `.git/info/exclude` is per-repo and untracked, so seeding it never appears in `git status` or a commit — that's the whole point. Never write to the tracked `.gitignore`.

   The probe is a silent no-op for anyone with `**/.claude/tmp/` in their global excludes (`git config --global core.excludesFile`), which is the preferred setup.

   **When the fallback actually fires, say so once in the run output** — name the file written and mention that `git check-ignore -v .claude/tmp/` explains the exclusion later. `.git/info/exclude` is an obscure corner of git, and a file that's silently ignored with nothing in either `.gitignore` to explain it is a genuinely confusing thing to hand someone.

   One directory-level entry covers every skill adopting the convention — never add per-skill entries.
3. Filename: `FIX_ORDER.md` for a full run, or `FIX_ORDER-<numbers>.md` (issue numbers ascending) for a scoped run.

Write `.claude/tmp/fix-order/<filename>` with YAML frontmatter so `list` can report status without parsing the body:

```yaml
---
generated: <ISO 8601 timestamp>
prs:
  - number: 31
    order: 1
    critical: false
    blast_radius: 0
  - number: 29
    order: 2
    critical: false
    blast_radius: 1
    stack:
      parent_pr: 31
      blocked: true
units:
  - order: 1
    disposition: GROUP
    critical: false
    issues:
      - number: 18
        finding: F7
      - number: 19
        finding: ~
  - order: 2
    disposition: WORK
    critical: false
    issues:
      - number: 14
        finding: ~
  - order: 3
    disposition: STACK
    critical: false
    stack:
      parent_order: 2
      parent_issue: 14
      depth: 2
    issues:
      - number: 15
        finding: F9
  - order: 4
    disposition: STACK
    critical: false
    stack:
      parent_order: 3
      parent_issue: 15
      depth: 3
    issues:
      - number: 20
        finding: ~
  - order: 5
    disposition: STACK
    critical: false
    stack:
      parent_pr: 31
      depth: 2
    issues:
      - number: 16
        finding: ~
  - order: 6
    disposition: WORK
    critical: false
    incomplete: true
    issues:
      - number: 23
        finding: ~
  - order: ~
    disposition: HOLD
    critical: false
    held_for: "#14 -> #15 -> #20 chain"
    issues:
      - number: 21
        finding: ~
  - order: ~
    disposition: HOLD
    critical: false
    held_for: "PR #29 must merge first"
    issues:
      - number: 17
        finding: ~
  - order: ~
    disposition: NEEDS-DECISION
    critical: false
    issues:
      - number: 12
        finding: ~
---
```

`prs` is the Phase 4.6 merge order, one entry per open PR. `stack` is present only on a PR with an unresolved `work-issue-stack` marker; `blocked` is `true` while its parent is open. `units` is ordered by `order`, with unordered dispositions (`HOLD`, `NEEDS-DECISION`, `DEFER`, `CLOSE-MOOT`) last, carrying `order: ~`. `finding: ~` means no recorded finding ID — never guess one. A `STACK` on a unit carries `parent_order` and `parent_issue`; a `STACK` on an open PR carries `parent_pr` only. `incomplete: true` is written only on an incomplete unit, and omitted otherwise. Entries are never removed after an issue closes; see Repeat-run mode.

Then the body:

* **Work plan** — one row per unit, in order:

  ```markdown
  | Order | Issues | Finding | Disposition | Blast | Title | Rationale |
  |-------|--------|---------|-------------|-------|-------|-----------|
  | 1 | #18, #19 | F7, — | GROUP | 1 | set_field precedence + agreement | both rewrite set_field; #19 undefined without #18's precedence |
  | 2 | #14 | — | WORK | 0 | Stable ship ids | severity High, no overlap with anything open |
  | 5 | #16 | — | STACK on PR #31 | 1 | Retry jitter | shares `src/net/retry.rs` with PR #31 |
  | 6 | #23 | — | WORK (incomplete) | — | Log noise on startup | run `/issue-triage` first: no fingerprint, no `effort:` |
  | — | #17 | — | HOLD | — | Rename parse_opts | rewrites `parse_opts`, which PR #29 also changes; PR #29 must merge first |
  | — | #12 | — | NEEDS-DECISION | — | Rating priority | issue says "a real domain decision"; not codeable as filed |
  ```

  `Blast` is the Phase 4 blast radius. `—` for a unit with no position or no known files.

  Identifier formatting, since conflating the three spaces is the failure mode this table prevents: issue numbers keep `#`; finding IDs stay bare (`F3`, or a bare ordinal from `/code-review`); use `—` for absent, never a blank cell, never a guess.
* **PR merge order** — one row per open PR, in Phase 4.6 order:

  ```markdown
  | Order | PR # | Issue # | Finding | Title | Blast | Rationale |
  |-------|------|---------|---------|-------|-------|-----------|
  | 1 | #31 | #9 | — | Retry backoff | 0 | shares no file with another open PR |
  | 2 | #29 | #8 | F4 | Option parsing | 1 | stacked on #31; merges after it, restack in between |
  ```

  Then the critical-tier promotions with who pays for them, the stack chains written as
  executable steps (`merge #31 → /work-issue restack → merge #29`), and the PR–PR overlap
  classifications. Omit any of these three when it has nothing to say.
* **Grouping detail** — for each `GROUP` unit, what specifically collides (file, function, why separate PRs would conflict) and the suggested combined branch slug.
* **Stack detail** — for each chain, the order of its links, which file overlap put each
  child on its parent, and the explicit note that a child cannot merge before its parent.
* **Held units** — every `HOLD` unit, what holds it (the chain it overlaps, or the open PR it
  waits on and the symbol they both change), and that it is a candidate for the next batch
  rather than a deferral. `HOLD` is a scheduling consequence, not a judgment about the
  issue — keep it out of the `DEFER` section, which is a judgment.
* **Run `/issue-triage` first** — every incomplete issue, with what is missing (fingerprint,
  `severity:`, `effort:`). Omit the section when there are none.
* **Open PRs** — each open PR that has an edge to an issue: its files, and which issues stack
  on it, wait on it, or are mooted by it. Omit PRs with no edge.
* **Decisions needed** — for each `NEEDS-DECISION`, the question stated plainly and the options the issue itself names. This section is the one the user acts on first; make it answerable without opening the issue.
* **Proposed deferrals** — each `DEFER` with its reason, phrased as a recommendation. State explicitly that no label has been applied.
* **Proposed closures** — each `CLOSE-MOOT`, naming the superseding issue or PR and the evidence — or, for a verification `already-fixed`, the fix its comment found. State explicitly that nothing has been closed.
* **Relationship graph** — the Phase 2 edges with their evidence. Skip pairs with no edge; don't pad.
* **Open questions** — edges you couldn't classify confidently, ambiguous dependencies, anything needing maintainer judgment.

## The `label` subcommand

Puts `status: needs-decision` on the issues this queue is blocked on, so they're filterable in the GitHub UI instead of only visible in a snapshot under `.claude/tmp/`. It is a **sync**, not an apply — it removes the label as readily as it adds it, because a label left behind after a decision was answered is worse than no label at all.

1. **Resolve the snapshot**, don't generate one. `/fix-order label` → `FIX_ORDER.md`; `/fix-order label #11 #15` → `FIX_ORDER-11-15.md`. Missing → say so, tell the user to run `/fix-order` first, and stop. **Never run the ranking implicitly here.** A sync against dispositions the user hasn't read is a mutation they didn't agree to.
2. **Staleness check.** `gh issue list --state all --json number,state,title,updatedAt` over the snapshot's issue numbers. Warn — once, listing them — about any issue whose `updatedAt` is later than the snapshot's `generated` timestamp, or that has closed since. Offer re-running `/fix-order` first. Advisory, not blocking; the user may know the update was cosmetic.
3. **Compute two sets, scoped strictly to issue numbers present in this snapshot's `units`:**
   - **Add** — issues in a unit whose `disposition` is `NEEDS-DECISION`, that don't already carry the label.
   - **Remove** — issues in this snapshot carrying the label whose disposition is now anything else.

   Issues absent from the snapshot are never touched, **even if they carry the label**. A scoped run covers three issues; it has no basis for an opinion about the other thirty, and stripping a label off an issue it never looked at is the failure this scoping rule exists to prevent.
4. **Ensure the label exists** — `gh label list`; if absent, `gh label create "status: needs-decision" --color "d876e3" --description "Blocked on a maintainer decision (from /fix-order)"`. This is the `status:` namespace in `/make-issues`' vendored label baseline; reuse its exact name and color rather than minting a variant.
5. **Show both lists and confirm** — issue number and title per line, adds and removals grouped separately, with the removals explained (decision answered, disposition changed, issue closed). Ask before touching anything, **even when one list is empty**. Skipping the prompt because "it's only two labels" is how a sync becomes a surprise.
6. **Apply** — `gh issue edit <n> --add-label "status: needs-decision"` / `gh issue edit <n> --remove-label "status: needs-decision"`.
7. **Report** what changed. If both sets were empty, say the labels already match the snapshot rather than printing nothing.

This label is for humans reading GitHub. Nothing in this ecosystem reads it back: `/work-issue` re-derives `NEEDS-DECISION` from the fix-order protocol on every batch run precisely so a stale label can't silently block work. Recorded and displayed, never matched on — the same treatment `/make-issues` gives `finding_id`.

## Next in the pipeline

This skill is stage 3 of the review → issue → PR → merge pipeline (`~/.claude/skills/WORKFLOW.md`). End the run by printing the next step as the last line. Which line depends on what the dispositions found, in this order:

1. **Any `NEEDS-DECISION`** — that's the next step, not `/work-issue`. Name the issue numbers and say a batch run will halt on them anyway:

   > Next: answer the decision on #12 (in the issue), then re-run `/fix-order`. `/work-issue all` halts on it until then — or `/fix-order label` first, to flag it in the GitHub UI.
2. **Otherwise** — the work:

   > Next: `/work-issue all` to work these in order, or `/work-issue 18 15` to take just the first units.

   Use the actual issue numbers from the top of the order in the scoped variant.
3. **Nothing left to work** (everything is `DEFER` / `CLOSE-MOOT`) — say so, and point at the proposals as the thing to act on. Don't recommend `/work-issue` with an empty queue.

When any issue is incomplete, add one line before the next step, with the numbers:

> Run `/issue-triage #23 #27` first — they have no place in the order until they are complete.

Mention `DEFER` and `CLOSE-MOOT` proposals alongside whichever line fires — they're standing decisions for the user, not blockers on the next command.

This skill never runs the next step itself; it prints the command and stops.

## Rules

* Never create, close, comment on, or edit an issue. Never edit an issue body. Never create a branch, worktree, or PR. Apart from the `label` subcommand, this skill only reads and writes under `.claude/tmp/fix-order/`.
* `label` may add and remove exactly one label, `status: needs-decision`, only within the resolved snapshot's scope, and only after showing both lists and getting confirmation. Never touch any other label — `backlog` and every other deferral label stay the user's to apply.
* Never run the ranking as a side effect of `label`. A missing snapshot is a stop-and-report, not a prompt to generate one.
* `clean` and `clean --all` are the only operations that delete anything; both require showing candidates and getting explicit confirmation.
* Base `COLLIDES` claims on actually reading the source, not on file paths alone. `OVERLAPS` is cheap and mechanical; `COLLIDES` is not, and asserting it without opening the code is the main way this skill can produce a wrong grouping.
* Label `MOOTS` and semantic `DEPENDS-ON` as judgment calls. "Likely moots" and "moots" are different claims — don't collapse them. When in doubt, leave the issue as `WORK` and raise it in Open questions; a wrongly-closed issue costs more than a redundant PR.
* Never infer a finding ID, issue number, or dependency the evidence didn't produce. `—` is correct output for absent.
* Never propose `DEFER` for an issue describing a defect in shipped code. Deferral is for speculative or future-scoped work, not for bugs that are merely inconvenient.
* Keep effort a tiebreaker only. Never let it override severity, blast radius, or dependency order.
* Never fill in what an incomplete issue lacks — no file guessed from its prose, no severity from its title. Rank it last and send it to `/issue-triage`.
* Never give an issue a free position when it `OVERLAPS` or `COLLIDES` with an open PR. It stacks on the PR or waits for it.
* Never close an issue because its verification says `already-fixed`, and never rank an issue lower because it is unverified. A verification result is evidence for a proposal.
* Keep staleness and size as tiebreakers in the PR order. Never let them override the stack constraint, the critical tier, or blast radius.
* `/merge-order` never makes its own order. When the two disagree, this skill is wrong or out of date — fix it here.
* If `gh` fails (auth, rate limit) or an issue number doesn't exist, stop and report. No silent retries, no guessing at issue contents.

## Repeat-run mode

If a file matching the current scope already exists, read it first. Mark issues no longer open as `CLOSED`, re-rank the remainder, and note which dispositions changed since the last run and why (usually: an issue was fixed, a decision was made, or a label changed).

**Full-queue repeat runs** always re-run Phase 1 in full — a high-severity issue filed since the last run must not stay invisible. For an issue already in `units` whose live `updatedAt` is not later than the file's `generated` timestamp, reuse its recorded fingerprint data, edges, and disposition verbatim rather than recomputing. One exception: if a newly-processed issue's Phase 2 analysis produces an edge touching a skipped issue, that edge is new information — update the skipped issue's entry, and re-check whether its disposition should change (a new `COLLIDES` edge can turn a `WORK` into a `GROUP`).

Open PRs are re-read on every run, never reused from the file. A PR opened, pushed to, merged, or closed since `generated` changes the edges of every issue that touches its files — recompute those issues' PR edges and re-check their dispositions (a merged PR releases the issues held for it).

**Scoped repeat runs** stay locked to the issue numbers already in the file's `units` array.

---

# Project documentation

Everything below is for humans installing, using, or contributing to this skill. It is not part of the fix-order protocol.

## Installation

Personal install (available across all your projects):

```bash
mkdir -p ~/.claude/skills/fix-order
# copy this file to ~/.claude/skills/fix-order/SKILL.md
```

Requires the `gh` CLI, authenticated (`gh auth status`) with read access to the target repo.

## Usage

```
/fix-order                  # full open queue
/fix-order #11 #15 #18      # scoped to a subset
/fix-order list             # past snapshots at a glance
/fix-order open             # open the snapshot folder (macOS)
/fix-order clean [--all]    # tidy up old snapshots
/fix-order label [#11 #15]  # sync `status: needs-decision` onto GitHub
```

`label` is the only one that writes to GitHub. It reads the newest snapshot for the given scope and makes GitHub agree with it — adding the label to issues currently dispositioned `NEEDS-DECISION`, removing it from issues in that same snapshot that no longer are. Run it after `/fix-order` to make the blocked issues visible in the UI, and again after answering a decision to clear the flag.

Output goes to `.claude/tmp/fix-order/FIX_ORDER.md`, the shared per-skill scratch convention. It persists between sessions so repeat runs can report what changed, and never enters version control.

**Recommended one-time setup** — add this to your global excludes file so no repo ever needs seeding:

```bash
echo '**/.claude/tmp/' >> "$(git config --global core.excludesFile)"
```

Without it, the skill falls back to appending to `.git/info/exclude` on first run in a repo — never to the tracked `.gitignore`, which would create a commit diff you'd have to carry. That fallback is per-repo and invisible in `git status`, which is the point, but it's also an obscure corner of git: if you ever find a file that refuses to show up in `git status` with nothing in either `.gitignore` to explain it, `git check-ignore -v <path>` names the exact file and line responsible.

## Why a disposition per issue instead of a ranked list

A plain ranked list of fixes can't express the two most valuable things this skill finds.

The first is **an issue that shouldn't be worked at all** — if fixing B makes A moot, A's correct position in the order is "nowhere," and the correct action is to close it with a comment. A ranking has no way to say that.

The second is **two issues that shouldn't be worked separately**. When two issues rewrite the same function, working them as consecutive items in an order is actively worse than working them together: each branch is cut from `main`, so the second PR conflicts with the first by construction, and if one issue's fix is only well-defined given the other's design decision, the first PR embodies a decision the second one then has to revisit. Grouping collapses both problems.

Ordering is real, but it's the last and least interesting step — applied only to what survives the dispositions.

## Why `NEEDS-DECISION` exists

An issue that says "this requires a policy decision" is not implementable as filed, but it looks exactly like every other issue to an automated batch run. Without this disposition, `/work-issue all` will happily invent the policy, and the maintainer discovers what was decided by reading a PR. Pulling these out of the sequence and surfacing the question — with the options the issue itself already listed — costs one round-trip and prevents a class of work that has to be redone.

## Why this skill never applies the `backlog` label

Proposing a deferral and enacting one are different acts. `backlog` records a maintainer's decision that something isn't worth doing now; a skill that applies it is making that decision instead of surfacing it. `/work-issue`'s own rules already say deciding what's worth doing now is the user's call — this skill is the thing that makes the call *easy*, by arriving with a short list and reasons, not the thing that makes it unilaterally.

The same logic applies more strongly to `CLOSE-MOOT`: closing an issue destroys queue state on a judgment call that can be wrong. Both are proposals.

## Why `status: needs-decision` is labelled but `backlog` isn't

They look like the same act — a skill putting a label on an issue — and they aren't.

`backlog` records a decision *the maintainer made*: this isn't worth doing now. A skill applying it makes that call instead of surfacing it, and the cost of a wrong one is silent: the issue drops out of every future queue and nobody looks at it again.

`status: needs-decision` records something about *the issue's own text* — that it isn't implementable as filed, because a policy or domain question inside it is unanswered. That's much nearer to an observation than a decision, and its failure mode runs the opposite direction: a wrongly-applied one makes you open the issue and conclude it's fine. The label invites inspection rather than suppressing it, which is the same job the disposition itself does — `NEEDS-DECISION` exists so a maintainer never discovers what got decided by reading a PR, and a label is that warning where the maintainer is actually looking.

Two guardrails keep the distinction from eroding. It's synced rather than applied — the subcommand removes the label as readily as it adds it, so it can't rot into a claim nobody has re-checked. And nothing downstream reads it, so a stale one is a cosmetic problem rather than something that silently blocks `/work-issue`.

The reason it's a separate subcommand rather than a step at the end of a fix-order run is removal, not permission. Applying it mid-run would mean every fix-order invocation mutates GitHub in both directions, which turns the advisory skill into a writing one for a benefit the user can get by typing six more characters.

## How this fits with your other skills

The intended loop:

1. `/project-review` or `/code-review` — find the work
2. `/make-issues` — file it; `/issue-triage` — complete every issue (summary, labels, fingerprint)
3. `/fix-order` — decide what to work, in what order, what to combine, what to drop
4. `/work-issue all` — execute the plan (it runs this skill's Phases 1.5–5, including Phase 4.5, as a sub-protocol to order its queue)
5. `/merge-order` — this skill's PR order, plus what you need while merging (ready, blocked, rebase likely, next action)
6. Merge manually in the recommended order

Step 3 replaces what used to be a manual pass of labelling things `backlog` by hand.

The fingerprint marker that `/make-issues` and `/issue-triage` write carries a `file:` field, which is exactly the file-overlap signal Phase 2 needs. On a repo where every issue has been through `/issue-triage`, most of Phase 2 is free. An issue that has not is ranked last with "run `/issue-triage` first", rather than placed from a guess at its prose.

## Why blast radius

Ranking by size ("small ones first") or by complexity ("the big one first") optimizes the
wrong unit — the change in hand, not the work left in the queue. A small change in a file
that every other open PR or issue touches forces a rebase on all of them; a large change in
a file nobody else touches costs nothing. Blast radius measures what happens to the rest of
the queue, which is the thing to keep small. Size, staleness, and effort only break ties.

## Why severity is a tier, not a weight

Blast radius measures engineering cost; severity measures the cost of delay. They can point
in opposite directions — a critical fix can have the worst blast radius, when the bug is in
code everyone touches. One weighted number would hide that. Tiers make it visible: the
urgent change goes first, and the deliverable says who pays for it in rebase work. For
issues every severity tier counts; for PRs only the critical tier does, because the fix
already exists and a short wait costs little.

## Why file overlap alone doesn't justify grouping

`OVERLAPS` (same file) over-flags badly on any repo with a few large modules — in a codebase where half the issues touch one model file, grouping on file overlap would collapse the entire queue into one PR. `COLLIDES` (same function or symbol) is the signal that actually predicts a conflict, and it's the only one that justifies combining issues. The cost is that `COLLIDES` can't be computed from metadata; it requires opening the source. That's a deliberate trade — the cheap signal is kept as a filter that narrows what needs the expensive check.

Phase 4.6 makes the same split for PR pairs, for the same reason.

## Limitations

- `MOOTS` detection is a judgment call over issue prose, and prose is often optimistic about what a fix will cover. The skill is deliberately biased toward leaving an issue as `WORK` and raising the question, since a wrongly-closed issue is a worse error than a redundant PR.
- Dependencies that nobody wrote down and that aren't visible in the code are invisible here. Declared dependencies are only as good as the issue text.
- File overlap between PRs is necessary but not sufficient. Two PRs can change different files and still conflict in behavior (one renames a function the other calls). That shows up only when the code runs, so run the tests after every merge.
- Severity ordering depends on the repo having severity labels. On a repo without them, ordering falls back to dependency, blast radius, and effort, which is weaker. `/issue-triage` adds the labels.
- Blast radius counts files, not symbols. Two changes in the same large file count as an overlap even when they would merge cleanly.

## License

Original, written for Peter's personal skills ecosystem. Freely modifiable.
