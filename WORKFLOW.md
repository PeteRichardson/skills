# The review → issue → PR → merge pipeline

How the skills in this repo are meant to be used **together**, in order. Each skill's own
`SKILL.md` documents that skill in isolation; this file is the thing that says which one
comes next and why.

The pipeline runs on a GitHub-backed repo. Stages 2–5 need `gh` authenticated
(`gh auth status`); stage 1 and the inner loop work anywhere.

Work comes in from three sources — a review, a spec, or a person — and every issue passes
through one gate, `/issue-triage`, before anything ranks it:

```
            Source code
           /           \
  /project-review    /code-review  ──(engine: ocr, native, or matt)
           \               |
  you ──► /grill-with-docs ──► spec
   |           \               |
   |            /make-issues  or  /to-spec + /to-tickets
   |                   |
   └──(by hand)──►  ISSUES  ◄──►  /issue-triage   (summary, labels, fingerprint; --verify)
                       |
                       ├──►  /fix-order   ──►  .claude/tmp/fix-order/FIX_ORDER.md
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

---

## At a glance

| # | Stage | Command | Produces | Durable trace it leaves |
|---|-------|---------|----------|-------------------------|
| 1 | Find the work | `/project-review` and/or `/code-review <scope>` — or, from an idea, `/grill-with-docs` → `/to-spec` | Findings with `file:line`, severity, effort — or a spec | `docs/reviews/PROJECT_REVIEW.md`, `docs/reviews/code-review_*.md` |
| 2 | File and complete the work | `/make-issues [--all]`, `/to-tickets`, or by hand — then `/issue-triage` | Complete GitHub issues: summary, labels, fingerprint | Issues carrying `<!-- project-review-finding -->` and `severity:`/`category:`/`effort:` labels (`source:` when a review filed them) |
| 3 | Decide what to work | `/fix-order` | Disposition per issue + ordered work units | `.claude/tmp/fix-order/FIX_ORDER.md` |
| 4 | Do the work | `/work-issue all` (or `/work-issue <n>`); `/implement-spec` for one big spec | One PR per work unit, stacked when units overlap | Branches `Fix-I<n>-…` (one name, local and remote), open PRs, a resolution comment per issue |
| 5 | Decide merge order | `/merge-order` | `/fix-order`'s PR order, with ready / stack / rebase / next action per PR | `.claude/tmp/merge-order/MERGE_ORDER.md` |
| 6 | Merge | `/code-review <pr>`, then **manual** merge in the stage-5 order | Merged PRs, auto-closed issues | `docs/reviews/code-review_PR*.md`, git history |

Then loop: a fresh `/project-review` after a batch of merges is how the next round starts.

Lost your place? `/pipeline` (or `~/.claude/skills/pipeline/pipeline-status`) reads the
right-hand column and tells you which stage you're on — see [Where am I?](#where-am-i--recovering-pipeline-state).

### One-time setup

```bash
gh auth status                                              # stages 2-5 need this
echo '**/.claude/tmp/' >> "$(git config --global core.excludesFile)"
```

The second line keeps `/fix-order` and `/merge-order` scratch output out of every repo's
`git status`. Without it each skill falls back to appending to that repo's
`.git/info/exclude` on first run — which works, but is obscure enough to be confusing later.

---

## The through-line: three identifier spaces

The single most important thing the pipeline does is keep **finding ID → issue number → PR
number** connected, because these are conflated constantly and each answers a different
question:

- `F3` — which review row this came from (why it's worth doing)
- `#60` — the durable record of the work (what it is)
- `PR68` — where to review it (where it lives now). Not in the branch name: it is assigned
  after the push, and `gh pr list --head <branch>` gives it

It's carried like this:

```
/project-review    writes  F3 in PROJECT_REVIEW.md
        ↓
/make-issues       records finding_id: F3 in issue #60's fingerprint marker
        ↓
/work-issue        reads it back → branch Fix-I60-F3-rust-ps-path → PR #68
        ↓
/fix-order         displays all three side by side in its PR merge order
```

Rule that holds at every stage: **an absent ID is correct output; an inferred one is a bug.**
Hand-filed issues have no `F<n>` and never get one — `/issue-triage` deliberately
won't invent one, and neither will `/work-issue`, `/fix-order`, or `/merge-order`.

---

## Stage 1 — Find the work

Two different tools, and they compose rather than compete:

- **`/project-review`** — repo-wide architecture and tech-debt audit. Slow, broad, produces
  numbered findings (`F1`, `F2`, …) with severity *and* effort in
  `docs/reviews/PROJECT_REVIEW.md`. This is the stage-1 default.
- **`/code-review <scope>`** — line-level review of a folder/file/glob. Tiered
  HIGH/IDIOM/MEDIUM/LOW, ~10 findings, ordinals instead of stable IDs, no effort estimate.
  Report goes to `docs/reviews/code-review_<scope>_<date>.md`.

`/code-review` also takes a PR number, or no argument (the changes on the current branch),
but **those are stage 6, not stage 1** — they review a proposed change rather than the repo,
and the report carries a `pr:` or `change:` frontmatter key marking it as describing code that
hasn't merged. `/project-review`'s Phase 1.5 and `pipeline-status` both skip those reports for
that reason, so running one never makes it look like this round's work has been found. Matt
Pocock's `/implement` and `/implement-spec` end with "run /code-review"; that runs this
skill in change mode.

`/code-review` runs one **engine** and always writes the same report format:
`open-code-review-delegate` (`ocr`, the default for a PR or a change), its own protocol
(`native`, the default for a scope — `ocr` reviews only diffs), or
`mattpocock-skills:code-review` (`matt`, its Standards + Spec check, with an **Axis:** line on
each finding). Choose with `--engine`.

Run `/code-review` first if you want the detail to feed the audit — `/project-review`'s
Phase 1.5 ingests existing code-review reports as evidence. Run it after, scoped to a
subsystem the audit flagged, when you want depth on one area.

Both reports are disposable. Regenerate freely; the finding IDs are reconstructed from git
history so a deleted `PROJECT_REVIEW.md` can't cause an ID collision with issues already filed.

**Also useful here:** `/add-tests` (coverage gaps on recent changes) and `/update-docs`
(doc drift) surface work the review tools don't frame as findings.

**From an idea, not from code.** Matt Pocock's `/grill-with-docs` questions a plan until it is
clear, `/to-spec` writes it as a spec, and `/to-tickets` files the spec as issues. Those issues
join the same queue at stage 2. See [Where Matt Pocock's skills fit](#where-matt-pococks-skills-fit).

## Stage 2 — File and complete the work

```
/make-issues                       # PROJECT_REVIEW.md, Medium+ severity only
/make-issues --all                 # every finding, including Low
/make-issues -f F3 F5 F9           # just these
/make-issues docs/reviews/code-review_src_2026-07-21.md
/issue-triage                      # complete hand-filed issues: summary, labels, fingerprint
```

This is the first stage that **mutates GitHub**. It creates issues, seeds the label
vocabulary if missing, and dedups against existing issues (open *and* closed) by file path +
keyword overlap. Above ~20% overlap it pauses and asks; below that it just creates. Then it
calls `/issue-triage` on the new issues, which adds the summary and any missing labels.

`/issue-triage` is the gate for **every** issue: from `/make-issues`, from `/to-spec` or
`/to-tickets`, or filed by hand. Run it after you file an issue by hand, and after
`/to-tickets`. It leaves Matt's `ready-for-agent` label alone and adds only what is missing.
The summary marker it writes — `> **SUMMARY:**` at the very top of the body — is one shape,
owned by `/issue-triage` and restated in each repo's `docs/agents/issue-tracker.md` so an
issue is filed that way whatever files it; a body that instead opens with a `## Summary`
section gets the heading converted, not a second summary stacked above it.
`/pipeline` counts an open issue with no `severity:` or `effort:` label as incomplete, and
names `/issue-triage` as the next step until there are none. It adds the
fingerprint as a *comment* (never a body edit) so the issue takes part in future dedup — and,
more importantly, so stage 3 can see its `file:` field. `/issue-triage --verify` also
reproduces each issue once and records the steps in it (opt-in).

**Why the fingerprint matters downstream:** the `file:` field is exactly the overlap signal
`/fix-order` Phase 2 needs. On a repo where every issue went through `/issue-triage`, most
of `/fix-order` is free. `/fix-order` does not guess for an issue without a fingerprint or
without `severity:` and `effort:` labels: it ranks it last and says "run `/issue-triage`
first".

## Stage 3 — Decide what to work

```
/fix-order                      # full open queue
/fix-order #11 #15 #18          # scoped
/fix-order list                 # past snapshots, live open/closed status
```

`/fix-order` needs only the open issues and the open PRs — no review report. It puts open
PRs in the same graph as the issues: a PR is an issue with a known fix. An issue that shares
a file with an open PR stacks on that PR's branch; one that changes the same function waits
(`HOLD`) until the PR merges. The order is dependency, then severity, then **blast radius**
(how many other open issues and PRs share its files — fewer goes first), then effort. A
`/issue-triage --verify` result counts too: `already-fixed` is proposed for closure, and
`not-enough-detail` or `not-reproduced` needs your decision.

Output is a **disposition per issue**, not a ranking — because the two most valuable things
`/fix-order` finds can't be expressed as an order:

| Disposition | Meaning | Your move |
|---|---|---|
| `WORK n` | Work alone, at position n | Nothing — stage 4 handles it |
| `GROUP` | Collides with another issue at the *symbol* level | Nothing — one branch, one PR, `Fixes #a` + `Fixes #b` |
| `STACK` | Shares a file with an earlier unit or an open PR | Nothing — branched from that branch; merges after it |
| `HOLD` | Chain depth cap, or waits for an open PR to merge | Nothing — it comes back in the next batch |
| `NEEDS-DECISION` | Not implementable as filed; needs a policy/domain call (or verification could not confirm it) | **Answer the question in the issue, then re-run `/fix-order`** |
| `DEFER` | Speculative or future-scoped | Apply `backlog` yourself if you agree |
| `CLOSE-MOOT` | Another issue or an open PR supersedes it, or verification found it already fixed | Close it yourself if you agree |

The bottom three are the ones that need you. `NEEDS-DECISION` in particular is the stage-3
output to read first: leave one unanswered and stage 4 will halt on it anyway.

A `/fix-order` run applies nothing — it never labels, closes, or comments. Deferring and closing
are prioritization decisions, and a skill that enacts them is making the call rather than
surfacing it.

The one exception is opt-in and separate:

```
/fix-order label [#11 #15]      # sync `status: needs-decision` onto GitHub
```

It makes GitHub agree with the snapshot — adding the label to issues currently dispositioned
`NEEDS-DECISION`, removing it from issues in that same snapshot that no longer are — so the
blocked work is visible in the UI rather than only in `.claude/tmp/`. Run it after `/fix-order`,
and again after answering a decision to clear the flag. Nothing downstream reads the label:
stage 4 re-derives the disposition itself, so a stale one is cosmetic rather than a silent
block.

## Stage 4 — Do the work

```
/work-issue 60                     # one issue
/work-issue all                    # every open, non-deferred, not-already-addressed issue
/work-issue 11 15 18               # batch scoped to a hand-picked set
```

Per work unit: fresh worktree under `.worktrees/`, branch off `origin/<base>`, do the change,
push, open the PR, tear the worktree down. When `/issue-triage --verify` recorded **Steps to
reproduce** in the issue, they become the first failing test.

Batch mode re-runs `/fix-order`'s Phases 1.5–5 **fresh** to order its queue — it never reads
a stale snapshot, since any merge or label change since invalidates one. It works units
sequentially (parallel worktrees on overlapping code is how you manufacture the conflicts
stage 5 then has to untangle), and it halts on `NEEDS-DECISION`.

**Overlapping units are stacked, not parallelised.** `/fix-order`'s Phase 4.5 marks a unit
`STACK` when it shares a file with one ranked ahead of it. That unit's branch is cut from its
parent's branch and its PR targets that branch, so the change is written against code that
already contains the parent's fix instead of against a base that predates it.

This costs no wall-clock: batch mode was already sequential, so the parent's branch always
existed by the time the child started — it was simply being ignored. Chains cap at 3; a 4th
overlapping unit is `HOLD`, reported for the next batch.

**A big spec goes another way.** When `/to-tickets` filed a spec as several tickets that
build on each other, Matt's `/implement-spec` takes the spec and its tickets to one
integration branch. It does not need `/fix-order`: the tickets' blocking edges already set
the order. On GitHub it opens a draft PR that closes the spec and its tickets, so `/pipeline`
sees them as started once that PR is open. It ends with `/code-review` on the integration
branch, which runs this repo's skill in change mode.

**Every issue also gets a resolution comment** once its PR is open — diagnosis, what the PR
proposes for *that issue specifically*, what you'd notice if it merges, and what was left out.
It's the answer to "what happened to my bug" without opening the diff, which matters most on a
grouped PR where two of three reporters would otherwise get a link to changes that aren't
theirs. Everything but the diagnosis is written in proposal tense with a `> [!NOTE]` callout
saying nothing has landed on `main` yet, because at that point nothing has — review can still
reject or rewrite the fix. Nothing updates the comment afterwards; the PR stays the source of
truth.

**Inside the worktree, the inner loop is the normal skills:**

```
superpowers:test-driven-development  →  write the change
/run-tests                           →  verify
/add-tests                           →  fill coverage gaps
/update-docs                         →  if the change was structural
/pre-commit                          →  final gate (tests exist, tests pass, docs current)
/commit-message                      →  the message; include Fixes #<n>
```

After the PR is open the worktree is gone by design. To iterate:

```bash
git worktree add .worktrees/Fix-I60-F3-rust-ps-path Fix-I60-F3-rust-ps-path
git pull --rebase    # first, in case GitHub's "Update branch" rewrote it
git push             # one name, local and remote: a plain push reaches the PR
```

## Stage 5 — Decide merge order

```
/merge-order                         # full open queue
/merge-order #7 #8 #12               # scoped burn-down
/merge-order list                    # past snapshots, live merged/closed status
```

The order comes from `/fix-order` (its Phase 4.6), run fresh — one source of order for issues
and PRs. A stack parent merges before its child; a PR linked to a critical-severity issue
goes first; then **blast radius** — how many other open PRs share a file with this one —
ascending, so each merge disturbs the fewest remaining PRs; then staleness, then size.

`/merge-order` adds one line per PR for the moment of merging: **Ready?** (CI, review,
draft, conflicts), **Stack** (parent open, or merged and waiting for a restack), **Rebase
likely?** (shares a file with an earlier PR — marked `(collision)` when a careless rebase
could merge cleanly and still be wrong), and **Next** (merge, restack, rebase, wait).

## Stage 6 — Merge, manually

Deliberately not automated. Work down the stage-5 sequence one PR at a time:

1. `/code-review 68` for the line-level pass, if the PR hasn't had one. PR mode reviews only
   the lines the PR added or modified, never checks anything out, and leaves
   `docs/reviews/code-review_PR68_<date>.md` behind. Fix what it finds on the branch so it
   lands with the PR; `/make-issues <that report>` is for findings you'd rather not block the
   merge on. The built-in `/review` is the alternative when you want a quick prose read and
   no artifact.
2. Merge it on GitHub. `Fixes #<n>` in the body closes the issue(s) automatically.
3. **`/work-issue restack`** if anything was stacked on it. A child branch still carries its
   parent's commits until this runs; merging one before restacking produces a PR whose diff
   includes changes that already landed.
4. **Re-run `/merge-order`** — it recomputes the order against the new base and tells you
   what changed. The previous order is invalidated by every merge; don't work down
   a stale list.
5. Delete the local branch when the PR is merged: `git branch -D Fix-I60-F3-rust-ps-path`.
   `-D`, because a rebase- or squash-merge leaves commits that are not ancestors of `main`, so
   `-d` refuses. Cleanup is manual on purpose.

---

## Where am I? — recovering pipeline state

There is no state file, and there shouldn't be one: **every stage leaves a durable trace, so
the current position is always derivable.** A tracker could drift; artifacts can't.

Two ways to ask:

```bash
~/.claude/skills/pipeline/pipeline-status      # six-stage dashboard, instant, zero tokens
~/.claude/skills/pipeline/pipeline-status -b   # just the next command
```

```
/pipeline            # the same dashboard, plus what the pending decisions actually say
/pipeline blocked    # only what's waiting on you
/pipeline brief      # the cheat sheet, no API calls
```

Or by hand:

| Question | Check |
|---|---|
| Is there a current review? | `ls -lt docs/reviews/` — compare its date against `git log -1`. `code-review_PR*.md` and `code-review_CHANGE-*.md` files are stage-6 reviews of unmerged code, not stage-1 work |
| Were the findings filed? | `gh issue list --state all --label "source: project-review" --label "source: code-review"` |
| Which issues have no place in the order yet? | `/fix-order list` — outstanding units vs. `gh issue list --state open` |
| Is anything blocked on me? | The `NEEDS-DECISION` / `DEFER` / `CLOSE-MOOT` sections of the latest `FIX_ORDER.md` |
| What work is in flight? | `git branch -a \| grep -E 'Fix-I[0-9]+'` and `gh pr list` |
| Is there a merge order? | `/merge-order list` — and whether anything merged since it was generated |
| What's finished? | `gh pr list --state merged --limit 20` |

Both `list` subcommands resolve their snapshots against **live** GitHub state, so a snapshot
whose queue has entirely resolved shows up as fully closed rather than as pending work.
`/fix-order clean` and `/merge-order clean` remove exactly those.

---

## Variants

**Not GitHub-backed.** Stages 2–5 don't apply. Run stage 1, work findings directly off the
report, use the inner loop. The finding ID stays useful in commit messages.

**One known bug, no review.** File the issue by hand (`gh issue create`), then
`/issue-triage #<n>`, then `/work-issue <n>`. Skip stages 1, 3, 5. `/issue-triage` adds the
labels and the fingerprint, so a later `/fix-order` sees the issue's files. Add `--verify`
when you want the steps to reproduce recorded in the issue: `/work-issue` then uses them as
its first failing test. The branch has no `F<n>` segment.

**A spec, not a review.** `/grill-with-docs` → `/to-spec` → `/to-tickets` →
`/issue-triage`. Then either `/implement-spec` (the tickets build on each other: one
integration branch) or `/fix-order` and `/work-issue` (the tickets are independent). Stage 5
onward as normal.

**Language-learning sprint.** `/code-review src/ --focus idiom` → `/make-issues <report>` →
stage 3 onward as normal. IDIOM findings carry a derived severity so they order alongside
everything else.

**Someone else's PR, or your own PR that didn't come from an issue.** Stages 1–5 don't apply
— there's no finding, no issue, and nothing to order. Go straight to stage 6:
`/code-review <pr>`, fix on the branch, merge. The report's `scope: PR #<n>` frontmatter is
the only trace it leaves, and no other stage reads it.

**Small queue.** Under ~3 issues, stage 3 earns little — but run it anyway if any two touch
the same file, since `GROUP` is what stops you from opening two PRs that conflict by
construction. Under ~3 PRs, stage 5 earns little; blast radius on a queue of two is trivial.

**A chain you no longer want stacked.** Restack the child onto the base branch directly
(`/work-issue restack` does this once the parent merges) or, to break the chain early,
`git rebase --onto origin/main <parent_head> <child>` by hand and retarget the PR. The chain
is a convenience, not a commitment.

---

## Where Matt Pocock's skills fit

Matt Pocock's skills are installed beside these (`npx skills`, and the `mattpocock-skills:`
plugin). **No skill here edits his, copies his text, or depends on his wording.** He updates
them often, and an update must need no follow-up edit here. They fit at these points:

| His skill | Where | How it joins |
|---|---|---|
| `/grill-with-docs`, `/to-spec`, `/to-tickets` | Stage 1–2, from an idea | Their issues go through `/issue-triage` like any other. It leaves `ready-for-agent` alone |
| `/implement-spec` | Stage 4, one big spec | One integration branch instead of `/work-issue`'s one PR per unit |
| `/implement` | Inside a branch | Small work on the current branch. It calls `/code-review` by name, which runs this repo's skill in change mode |
| `mattpocock-skills:code-review` | Stage 1 or 6 | An engine of `/code-review` (`--engine matt`): its Standards + Spec check, in this repo's report format |
| `/triage` | Off the main path | Type `/triage #n` by hand for its full one-issue treatment (questions, grilling, an agent brief). Not the same job as `/issue-triage`, which only completes issues |

`/to-spec` and `/to-tickets` need `docs/agents/triage-labels.md` in each repo; keep it.

If his skills change a lot — `/implement` stops calling `code-review`, or `/to-tickets` changes
its labels — check this table. Nothing here breaks, but the fit can change.

---

## What the pipeline deliberately won't do

Each of these is a decision that belongs to you, and every skill involved is written to
surface it rather than take it:

- **Merge anything.** `/merge-order` is advisory, full stop.
- **Say anything on your behalf on a PR.** `/code-review <pr>` writes a local report and
  stops — no review comment, no requested changes, no approval. Publishing a review is your
  call. The pipeline's complete set of GitHub writes stays: `/make-issues` (issues),
  `/issue-triage` (fingerprint and verification comments, labels in empty namespaces, and a
  summary at the top of a body that has none — or its leading `## Summary` heading converted
  to the marker — all after one confirmation),
  `/fix-order label` (one label, opt-in), and `/work-issue` (branch, PR, per-issue
  resolution comment).
- **Close or defer an issue.** `/fix-order` proposes `CLOSE-MOOT` and `DEFER`; it never
  applies a `backlog` label or closes anything, and `/work-issue` won't act on those
  proposals either. `/fix-order label` is the one sanctioned mutation, and it touches
  exactly one label after showing you both the additions and the removals.
- **Decide a `NEEDS-DECISION` issue.** Batch mode halts instead of picking a policy and
  letting you discover it by reading a diff.
- **Work a deferred issue in batch.** An explicit `/work-issue <n>` can override, but only
  after asking.
- **Work in the main checkout.** Every change happens in the issue's worktree.
- **Invent an identifier.** No guessed finding IDs, issue numbers, or dependencies —
  `—` is the correct output for absent.
