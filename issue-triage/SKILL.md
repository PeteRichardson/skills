---
name: issue-triage
description: Assess a set of open GitHub issues and recommend what to work, in what order, what to combine into a single PR, what to close as moot, and what needs a human decision first. Produces a scoped snapshot under .claude/tmp/issue-triage/ with a relationship graph (file/symbol overlap, declared dependencies, supersession), a disposition per issue (including stacked and held units), and an ordered work plan. Supports `/issue-triage list`, `/issue-triage open`, `/issue-triage clean` [--all], and `/issue-triage label` to sync a `status: needs-decision` label onto GitHub for UI visibility. Its Phases 2-5 are also run as a sub-protocol by `/work-issue` batch mode to order its queue. Use when the user has several open issues and asks which to fix first, how to order the backlog, or to triage the issue queue. A triage run creates, closes, and modifies nothing — advisory only; `label` is the sole mutation and touches one label after confirmation.
disable-model-invocation: true
---

# Issue Triage

A Claude Code skill that looks at a set of open issues and recommends a **fix plan** — not merely an order. Some issues shouldn't be worked at all because another issue moots them; some shouldn't be worked *separately* because they rewrite the same function; some can't be worked yet because they need a decision only the maintainer can make.

When invoked via `/issue-triage`, follow the protocol below. Everything from here through the `---` divider is the protocol Claude executes. The section after the divider is documentation for humans installing or maintaining this skill.

---

## Operating principles

**The output is a disposition per issue, not a ranking.** A linear order cannot express "don't work this one at all" or "work these two as one change," which are the two highest-value things triage produces. Ranking is the last step, applied only to what survives.

**A triage run is advisory.** It never creates, closes, labels, comments on, or edits an issue; never creates a branch, worktree, or PR. It reads (`gh issue list`, `gh issue view`, `git log`, source files) and writes under `.claude/tmp/issue-triage/`. Every disposition is a recommendation the user or `/work-issue` acts on — in particular `CLOSE-MOOT` and `DEFER` are proposals requiring confirmation, never actions.

The single exception is the **`label` subcommand**, which the user invokes separately and which syncs exactly one label (`status: needs-decision`) after showing what it will change. Running a triage never applies it; typing `/issue-triage label` does.

**Deferral is the maintainer's call, not this skill's.** Proposing that an issue be deferred is useful; applying a `backlog` label is a priority decision belonging to the user. This skill proposes; it never applies a deferral label, and `label` won't either — see "Why `status: needs-decision` is labelled but `backlog` isn't" below for why those two aren't the same act.

**Axes stay separate.** Dependency order, severity, and effort are three different things. Never blend them into a score — tier them, and state the tradeoff in prose when they conflict. (Same reasoning as `/pr-triage`'s severity-vs-blast-radius tiering.)

## Phase 0: Subcommands

Check the invocation before doing anything else:

* **`/issue-triage list`** — for every file in `.claude/tmp/issue-triage/` (create the directory first if absent — an empty listing isn't an error), read its frontmatter (`units`, `generated`) rather than the full report. Then make **one** `gh issue list --state all --json number,state,title,url,closedAt` call covering the union of every issue number across all files, and classify each file's issues against that single result — don't make a separate API call per file.

  For each file, print the filename, its `generated` timestamp, and its resolved absolute path on one line, then two groups below it:

  ```
  ISSUE_TRIAGE.md  (generated 2026-07-26 15:04)  /Users/pete/project/.claude/tmp/issue-triage/ISSUE_TRIAGE.md
      1  #18, #19  ‼ set_field: precedence + agreement      https://github.com/org/repo/issues/18
      2  #11, #15    SPARQL retry set + Retry-After         https://github.com/org/repo/issues/11
      ?  #12         Rating priority (NEEDS-DECISION)       https://github.com/org/repo/issues/12
      ---
      #20    Sloop-of-war era filter    closed 2026-07-26   https://github.com/org/repo/issues/20
  ```

  - **Outstanding** (issues the live result doesn't report as `CLOSED`): one line per work unit, in `units` array order, prefixed with its order number — or `?` for a unit whose disposition is `NEEDS-DECISION` or `DEFER`, which have no position in the sequence. Prefix with `‼` when the unit's frontmatter `critical` is `true`. No color — plain text only.
  - A `---` separator line, only if both groups are non-empty.
  - **Closed**: one line per issue, newest `closedAt` first, ending with `closed <date>`.
  - Each line ends with the issue's plain `url` from the live result — plain text, not a rendered hyperlink.

  Sort files newest-generated first (from frontmatter `generated`, not file mtime). Stop here; don't run a triage.
* **`/issue-triage open`** — run `open .claude/tmp/issue-triage/` (macOS). If `open` isn't available, print the absolute path. Stop here.
* **`/issue-triage clean`** — read every file's frontmatter issue numbers, make one `gh issue list --state all --json number,state` call covering the union. Any file whose entire issue set is now closed is a removal candidate. Show candidates plus what's being kept and why, and ask for confirmation before deleting. Stop here.
* **`/issue-triage clean --all`** — unconditional wipe of `.claude/tmp/issue-triage/`. Show what will be deleted, ask for confirmation. Stop here.
* **`/issue-triage label`**, or **`/issue-triage label #11 #15`** — sync the `status: needs-decision` label against an existing snapshot so the queue's blocked issues are visible in the GitHub UI. **This is the only subcommand that mutates GitHub.** See "The `label` subcommand" below. Stop here; don't run a triage.
* **`/issue-triage`** (no args) — full-queue run, proceed to Phase 1.
* **`/issue-triage #11 #15 #18`** (issue numbers) — scoped run limited to those issues, proceed to Phase 1 with the scope noted.
* **Executed as a sub-protocol by `/work-issue` batch mode** — not via the Skill tool (`disable-model-invocation: true` puts this skill out of reach of it), but by `/work-issue` reading this file and running Phases 2–5, including Phase 4.5, directly. The caller supplies an already-filtered candidate set: skip Phase 1, use the supplied set verbatim, proceed to Phase 2, and still write the snapshot.

## Phase 1: Enumerate the eligible set

1. Confirm the repo.
2. `gh issue list --state open --limit 200 --json number,title,body,comments,labels,createdAt,updatedAt,url`
3. **Exclude already-deferred issues.** Any issue carrying `backlog`, `icebox`, `someday`, `someday-maybe`, `future`, `deferred`, `on hold`, `wontfix`, or a `priority/backlog`-style namespaced equivalent is out of scope — that decision is already made. List them once as excluded, with the label that fired, so a mislabelled issue stays visible. This vocabulary is shared with `/work-issue`'s Phase 1 deferral check; keep the two lists in sync.
4. **Exclude already-addressed issues** using `/work-issue`'s Phase 2 checks: an open PR whose `closingIssuesReferences` names it, a PR `headRefName` matching `(^|-)I?<n>(-|$)`, or a local/remote branch matching the same pattern. Report each with which check fired.
5. **Read the `/make-issues` fingerprint** for each surviving issue — scan the body and every comment for `<!-- project-review-finding ... -->` and extract `file:`, `category:`, `keywords:`, and `finding_id:` if present. This is the cheapest source of the file-overlap signal Phase 2 needs, and issues carrying it need no code reading to place. Absent is normal (hand-filed, or `backfill`-retrofitted without one) — fall back to reading the issue text for cited paths and symbols. Never infer a `finding_id` that isn't recorded.

## Phase 2: Build the relationship graph

For every pair of surviving issues, determine which of these edges hold. Each requires different evidence; don't collapse them.

* **`OVERLAPS`** — both issues change the same file. From the fingerprint `file:` field where present, otherwise from paths cited in the issue text. Verify the path still exists; an issue filed against a since-renamed file is stale, and the *current* path is what matters. Pure set intersection, no judgment yet.
* **`COLLIDES`** — both issues change the same *function or symbol*, not merely the same file. This requires actually opening the source and locating what each issue proposes to change. `OVERLAPS` without `COLLIDES` is incidental adjacency (two issues adding separate functions to one module) and does **not** justify grouping.
* **`DEPENDS-ON`** — issue A cannot be correctly implemented before issue B lands. Two sources: declared (scan issue bodies and comments for "depends on #N", "blocks #N", "prerequisite", "should land before #N") and semantic (A's fix is only well-defined given B's design decision). Declared dependencies are facts; semantic ones are judgment calls and must be labelled as such.
* **`MOOTS`** — fixing B makes A unnecessary, not merely easier. A high bar: B must remove the condition A describes, not just touch the same code. If B merely makes A smaller, that is `COLLIDES`, not `MOOTS`.
* **`DUPLICATES`** — A and B describe the same defect, filed twice.

Record the evidence for each edge. An edge asserted without evidence is the failure mode this phase exists to prevent.

## Phase 3: Assign a disposition

Every issue gets exactly one. Apply in this order — earlier dispositions win:

| Disposition | Assign when | Effect |
|---|---|---|
| `CLOSE-MOOT` | A `MOOTS` or `DUPLICATES` edge points at it | Recommend closing with a comment naming the superseding issue. **Never worked.** |
| `NEEDS-DECISION` | The issue's own text says a policy/domain decision is required, or its fix has materially different valid outcomes the issue doesn't choose between | Pulled out of the sequence. The user decides before any code is written. |
| `GROUP` | It `COLLIDES` with one or more other issues | Combined with them into **one** work unit → one branch, one PR closing all of them. |
| `DEFER` | It is genuinely speculative, blocked on absent data, or scoped as a future idea | Proposed as a `backlog` candidate. **Never labelled by this skill.** |
| `WORK` | Everything else | Worked on its own, in sequence position n. |

`NEEDS-DECISION` outranks `GROUP` deliberately: a decision issue must not be silently absorbed into a grouped PR where the decision gets made as an implementation detail.

A **work unit** is one `WORK` issue or one `GROUP` set. Units, not issues, are what Phase 4 orders and what `/work-issue` turns into branches.

## Phase 4: Order the work units

Rank only `WORK` and `GROUP` units. `NEEDS-DECISION`, `DEFER`, and `CLOSE-MOOT` have no position.

1. **Dependency order first.** Topologically sort on `DEPENDS-ON`. This is a hard constraint, not a preference — it outranks everything below. Report a cycle rather than breaking it arbitrarily.
2. **Severity tier.** Within what the dependency order leaves free, `severity: Critical` then `High` before `Medium`/`Low`. Read severity from labels; if the repo has no severity labels, say so once and skip this step rather than inventing a scheme.
3. **Effort tiebreaker.** `effort: S` before `M` before `L`, so the queue shrinks fastest. Never let effort override severity or dependency.

When severity and dependency conflict — a High-severity issue that must wait on a Medium one — state it in prose in the deliverable rather than hiding it in the ordering.

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

`STACK` is deliberately **not** in Phase 3's precedence table, and that table is unchanged.
Phase 3 can't assign it: whether a unit stacks depends on which units rank ahead of it, which
isn't known until Phase 4 has run. This phase only ever converts a `WORK` unit into `STACK`
or `HOLD` — it never touches `GROUP`, `NEEDS-DECISION`, `DEFER`, or `CLOSE-MOOT`.

A `GROUP` unit can *be* a parent — its branch is a branch like any other — but is never
itself converted.

| Disposition | Assigned when | Effect |
|---|---|---|
| `STACK` | `OVERLAPS` (without `COLLIDES`) an earlier-ranked unit, within the depth cap | Branched from that unit's branch; PR based on it; merges after it. |
| `HOLD` | Would be the 4th link in a chain | Skipped this batch, reported for the next. `order: ~`. |

**Why `COLLIDES` is excluded:** those are already `GROUP`ed into one PR by Phase 3, which is
strictly better — two stacked PRs that rewrite the same function hand the reviewer two half
answers. Stacking is for the `OVERLAPS` band only, which Phase 2 deliberately leaves
ungrouped (see "Why file overlap alone doesn't justify grouping").

**Why depth 3:** a PR rejected at the bottom of a chain forces a restack of everything above
it. That cost grows with depth; the benefit doesn't.

## Phase 5: Deliverable

This project uses `.claude/tmp/` as the shared convention for ephemeral skill output, namespaced per-skill. Before writing anything:

1. `mkdir -p .claude/tmp/issue-triage`
2. Ensure `.claude/tmp/` is ignored — **without modifying any tracked file**:

   ```bash
   git check-ignore -q .claude/tmp/ || cat >> .git/info/exclude <<'EOF'

   # Added by the Claude Code /issue-triage skill.
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
3. Filename: `ISSUE_TRIAGE.md` for a full run, or `ISSUE_TRIAGE-<numbers>.md` (issue numbers ascending) for a scoped run.

Write `.claude/tmp/issue-triage/<filename>` with YAML frontmatter so `list` can report status without parsing the body:

```yaml
---
generated: <ISO 8601 timestamp>
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
  - order: ~
    disposition: HOLD
    critical: false
    held_for: "#14 -> #15 chain"
    issues:
      - number: 21
        finding: ~
  - order: ~
    disposition: NEEDS-DECISION
    critical: false
    issues:
      - number: 12
        finding: ~
---
```

`units` is ordered by `order`, with unordered dispositions (`NEEDS-DECISION`, `DEFER`, `CLOSE-MOOT`) last, carrying `order: ~`. `finding: ~` means no recorded finding ID — never guess one. Entries are never removed after an issue closes; see Repeat-run mode.

Then the body:

* **Work plan** — one row per unit, in order:

  ```markdown
  | Order | Issues | Finding | Disposition | Title | Rationale |
  |-------|--------|---------|-------------|-------|-----------|
  | 1 | #18, #19 | F7, — | GROUP | set_field precedence + agreement | both rewrite set_field; #19 undefined without #18's precedence |
  | 2 | #14 | — | WORK | Stable ship ids | severity High, no overlap with anything open |
  | — | #12 | — | NEEDS-DECISION | Rating priority | issue says "a real domain decision"; not codeable as filed |
  ```

  Identifier formatting, since conflating the three spaces is the failure mode this table prevents: issue numbers keep `#`; finding IDs stay bare (`F3`, or a bare ordinal from `/code-review`); use `—` for absent, never a blank cell, never a guess.
* **Grouping detail** — for each `GROUP` unit, what specifically collides (file, function, why separate PRs would conflict) and the suggested combined branch slug.
* **Stack detail** — for each chain, the order of its links, which file overlap put each
  child on its parent, and the explicit note that a child cannot merge before its parent.
* **Held units** — every `HOLD` unit, which chain it overlaps, and that it is a candidate for
  the next batch rather than a deferral. `HOLD` is a scheduling consequence of the depth cap,
  not a judgment about the issue — keep it out of the `DEFER` section, which is a judgment.
* **Decisions needed** — for each `NEEDS-DECISION`, the question stated plainly and the options the issue itself names. This section is the one the user acts on first; make it answerable without opening the issue.
* **Proposed deferrals** — each `DEFER` with its reason, phrased as a recommendation. State explicitly that no label has been applied.
* **Proposed closures** — each `CLOSE-MOOT`, naming the superseding issue and the evidence. State explicitly that nothing has been closed.
* **Relationship graph** — the Phase 2 edges with their evidence. Skip pairs with no edge; don't pad.
* **Open questions** — edges you couldn't classify confidently, ambiguous dependencies, anything needing maintainer judgment.

## The `label` subcommand

Puts `status: needs-decision` on the issues this queue is blocked on, so they're filterable in the GitHub UI instead of only visible in a snapshot under `.claude/tmp/`. It is a **sync**, not an apply — it removes the label as readily as it adds it, because a label left behind after a decision was answered is worse than no label at all.

1. **Resolve the snapshot**, don't generate one. `/issue-triage label` → `ISSUE_TRIAGE.md`; `/issue-triage label #11 #15` → `ISSUE_TRIAGE-11-15.md`. Missing → say so, tell the user to run the triage first, and stop. **Never run a triage implicitly here.** A sync against dispositions the user hasn't read is a mutation they didn't agree to.
2. **Staleness check.** `gh issue list --state all --json number,state,title,updatedAt` over the snapshot's issue numbers. Warn — once, listing them — about any issue whose `updatedAt` is later than the snapshot's `generated` timestamp, or that has closed since. Offer re-running the triage first. Advisory, not blocking; the user may know the update was cosmetic.
3. **Compute two sets, scoped strictly to issue numbers present in this snapshot's `units`:**
   - **Add** — issues in a unit whose `disposition` is `NEEDS-DECISION`, that don't already carry the label.
   - **Remove** — issues in this snapshot carrying the label whose disposition is now anything else.

   Issues absent from the snapshot are never touched, **even if they carry the label**. A scoped run covers three issues; it has no basis for an opinion about the other thirty, and stripping a label off an issue it never looked at is the failure this scoping rule exists to prevent.
4. **Ensure the label exists** — `gh label list`; if absent, `gh label create "status: needs-decision" --color "d876e3" --description "Blocked on a maintainer decision (from /issue-triage)"`. This is the `status:` namespace in `/make-issues`' vendored label baseline; reuse its exact name and color rather than minting a variant.
5. **Show both lists and confirm** — issue number and title per line, adds and removals grouped separately, with the removals explained (decision answered, disposition changed, issue closed). Ask before touching anything, **even when one list is empty**. Skipping the prompt because "it's only two labels" is how a sync becomes a surprise.
6. **Apply** — `gh issue edit <n> --add-label "status: needs-decision"` / `gh issue edit <n> --remove-label "status: needs-decision"`.
7. **Report** what changed. If both sets were empty, say the labels already match the snapshot rather than printing nothing.

This label is for humans reading GitHub. Nothing in this ecosystem reads it back: `/work-issue` re-derives `NEEDS-DECISION` from the triage protocol on every batch run precisely so a stale label can't silently block work. Recorded and displayed, never matched on — the same treatment `/make-issues` gives `finding_id`.

## Next in the pipeline

This skill is stage 3 of the review → issue → PR → merge pipeline (`~/.claude/skills/WORKFLOW.md`). End the run by printing the next step as the last line. Which line depends on what the dispositions found, in this order:

1. **Any `NEEDS-DECISION`** — that's the next step, not `/work-issue`. Name the issue numbers and say a batch run will halt on them anyway:

   > Next: answer the decision on #12 (in the issue), then re-run `/issue-triage`. `/work-issue all` halts on it until then — or `/issue-triage label` first, to flag it in the GitHub UI.
2. **Otherwise** — the work:

   > Next: `/work-issue all` to work these in order, or `/work-issue 18 15` to take just the first units.

   Use the actual issue numbers from the top of the order in the scoped variant.
3. **Nothing left to work** (everything is `DEFER` / `CLOSE-MOOT`) — say so, and point at the proposals as the thing to act on. Don't recommend `/work-issue` with an empty queue.

Mention `DEFER` and `CLOSE-MOOT` proposals alongside whichever line fires — they're standing decisions for the user, not blockers on the next command.

This skill never runs the next step itself; it prints the command and stops.

## Rules

* Never create, close, comment on, or edit an issue. Never edit an issue body. Never create a branch, worktree, or PR. Apart from the `label` subcommand, this skill only reads and writes under `.claude/tmp/issue-triage/`.
* `label` may add and remove exactly one label, `status: needs-decision`, only within the resolved snapshot's scope, and only after showing both lists and getting confirmation. Never touch any other label — `backlog` and every other deferral label stay the user's to apply.
* Never run a triage as a side effect of `label`. A missing snapshot is a stop-and-report, not a prompt to generate one.
* `clean` and `clean --all` are the only operations that delete anything; both require showing candidates and getting explicit confirmation.
* Base `COLLIDES` claims on actually reading the source, not on file paths alone. `OVERLAPS` is cheap and mechanical; `COLLIDES` is not, and asserting it without opening the code is the main way this skill can produce a wrong grouping.
* Label `MOOTS` and semantic `DEPENDS-ON` as judgment calls. "Likely moots" and "moots" are different claims — don't collapse them. When in doubt, leave the issue as `WORK` and raise it in Open questions; a wrongly-closed issue costs more than a redundant PR.
* Never infer a finding ID, issue number, or dependency the evidence didn't produce. `—` is correct output for absent.
* Never propose `DEFER` for an issue describing a defect in shipped code. Deferral is for speculative or future-scoped work, not for bugs that are merely inconvenient.
* Keep effort a tiebreaker only. Never let it override severity or dependency order.
* If `gh` fails (auth, rate limit) or an issue number doesn't exist, stop and report. No silent retries, no guessing at issue contents.

## Repeat-run mode

If a file matching the current scope already exists, read it first. Mark issues no longer open as `CLOSED`, re-triage the remainder, and note which dispositions changed since the last run and why (usually: an issue was fixed, a decision was made, or a label changed).

**Full-queue repeat runs** always re-run Phase 1 in full — a high-severity issue filed since the last run must not stay invisible. For an issue already in `units` whose live `updatedAt` is not later than the file's `generated` timestamp, reuse its recorded fingerprint data, edges, and disposition verbatim rather than recomputing. One exception: if a newly-processed issue's Phase 2 analysis produces an edge touching a skipped issue, that edge is new information — update the skipped issue's entry, and re-check whether its disposition should change (a new `COLLIDES` edge can turn a `WORK` into a `GROUP`).

**Scoped repeat runs** stay locked to the issue numbers already in the file's `units` array.

---

# Project documentation

Everything below is for humans installing, using, or contributing to this skill. It is not part of the triage protocol.

## Installation

Personal install (available across all your projects):

```bash
mkdir -p ~/.claude/skills/issue-triage
# copy this file to ~/.claude/skills/issue-triage/SKILL.md
```

Requires the `gh` CLI, authenticated (`gh auth status`) with read access to the target repo.

## Usage

```
/issue-triage                  # full open queue
/issue-triage #11 #15 #18      # scoped to a subset
/issue-triage list             # past snapshots at a glance
/issue-triage open             # open the snapshot folder (macOS)
/issue-triage clean [--all]    # tidy up old snapshots
/issue-triage label [#11 #15]  # sync `status: needs-decision` onto GitHub
```

`label` is the only one that writes to GitHub. It reads the newest snapshot for the given scope and makes GitHub agree with it — adding the label to issues currently dispositioned `NEEDS-DECISION`, removing it from issues in that same snapshot that no longer are. Run it after a triage to make the blocked issues visible in the UI, and again after answering a decision to clear the flag.

Output goes to `.claude/tmp/issue-triage/ISSUE_TRIAGE.md`, the shared per-skill scratch convention. It persists between sessions so repeat runs can report what changed, and never enters version control.

**Recommended one-time setup** — add this to your global excludes file so no repo ever needs seeding:

```bash
echo '**/.claude/tmp/' >> "$(git config --global core.excludesFile)"
```

Without it, the skill falls back to appending to `.git/info/exclude` on first run in a repo — never to the tracked `.gitignore`, which would create a commit diff you'd have to carry. That fallback is per-repo and invisible in `git status`, which is the point, but it's also an obscure corner of git: if you ever find a file that refuses to show up in `git status` with nothing in either `.gitignore` to explain it, `git check-ignore -v <path>` names the exact file and line responsible.

## Why a disposition per issue instead of a ranked list

The original framing of this skill was "recommend a fix order." That framing can't express the two most valuable things triage finds.

The first is **an issue that shouldn't be worked at all** — if fixing B makes A moot, A's correct position in the order is "nowhere," and the correct action is to close it with a comment. A ranking has no way to say that.

The second is **two issues that shouldn't be worked separately**. When two issues rewrite the same function, working them as consecutive items in an order is actively worse than working them together: each branch is cut from `main`, so the second PR conflicts with the first by construction, and if one issue's fix is only well-defined given the other's design decision, the first PR embodies a decision the second one then has to revisit. Grouping collapses both problems.

Ordering is real, but it's the last and least interesting step — applied only to what survives triage.

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

The reason it's a separate subcommand rather than a step at the end of a triage run is removal, not permission. Applying it mid-run would mean every triage invocation mutates GitHub in both directions, which turns the advisory skill into a writing one for a benefit the user can get by typing six more characters.

## How this fits with your other skills

The intended loop:

1. `/project-review` or `/code-review` — find the work
2. `/make-issues` (or `backfill`) — file it, with labels and fingerprints
3. `/issue-triage` — decide what to work, in what order, what to combine, what to drop
4. `/work-issue all` — execute the plan (it runs this skill's Phases 2–5, including Phase 4.5, as a sub-protocol to order its queue)
5. `/pr-triage` — order the resulting PR queue
6. Merge manually in the recommended order

Step 3 replaces what used to be a manual pass of labelling things `backlog` by hand.

There's a real synergy with `/make-issues`: the fingerprint marker it writes carries a `file:` field, which is exactly the file-overlap signal Phase 2 needs. On a repo where every issue has been through `/make-issues` or `backfill`, most of Phase 2 is free. On a repo of hand-filed issues, Phase 2 has to read issue prose instead, and its `OVERLAPS` edges are correspondingly less reliable.

## Why file overlap alone doesn't justify grouping

`OVERLAPS` (same file) over-flags badly on any repo with a few large modules — in a codebase where half the issues touch one model file, grouping on file overlap would collapse the entire queue into one PR. `COLLIDES` (same function or symbol) is the signal that actually predicts a conflict, and it's the only one that justifies combining issues. The cost is that `COLLIDES` can't be computed from metadata; it requires opening the source. That's a deliberate trade — the cheap signal is kept as a filter that narrows what needs the expensive check.

This mirrors `/pr-triage`'s Phase 2/Phase 4 split for the same reason.

## Limitations

- `MOOTS` detection is a judgment call over issue prose, and prose is often optimistic about what a fix will cover. The skill is deliberately biased toward leaving an issue as `WORK` and raising the question, since a wrongly-closed issue is a worse error than a redundant PR.
- Dependencies that nobody wrote down and that aren't visible in the code are invisible here. Declared dependencies are only as good as the issue text.
- This skill doesn't read PR diffs — that's `/pr-triage`'s job, downstream. It reasons about issues and source, not about work in flight beyond the "already addressed" filter.
- Severity ordering depends on the repo having severity labels. On a repo without them, ordering falls back to dependency plus effort, which is weaker.

## License

Original, written for Peter's personal skills ecosystem. Freely modifiable.
