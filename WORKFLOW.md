# The review → issue → PR → merge pipeline

How the skills in this repo are meant to be used **together**, in order. Each skill's own
`SKILL.md` documents that skill in isolation; this file is the thing that says which one
comes next and why.

The pipeline runs on a GitHub-backed repo. Stages 2–5 need `gh` authenticated
(`gh auth status`); stage 1 and the inner loop work anywhere.

---

## At a glance

| # | Stage | Command | Produces | Durable trace it leaves |
|---|-------|---------|----------|-------------------------|
| 1 | Find the work | `/project-review` and/or `/code-review <scope>` | Findings with `file:line`, severity, effort | `docs/reviews/PROJECT_REVIEW.md`, `docs/reviews/code-review_*.md` |
| 2 | File the work | `/make-issues [--all]` | GitHub issues, labelled + fingerprinted | Issues carrying `<!-- project-review-finding -->` and `severity:`/`category:`/`effort:`/`source:` labels |
| 3 | Decide what to work | `/issue-triage` | Disposition per issue + ordered work units | `.claude/tmp/issue-triage/ISSUE_TRIAGE.md` |
| 4 | Do the work | `/work-issue all` (or `/work-issue <n>`) | One PR per work unit | Branches `Fix-I<n>-…` (remote) / `PR<n>-Fix-I<n>-…` (local), open PRs, a resolution comment per issue |
| 5 | Decide merge order | `/pr-triage` | Blast-radius-ranked merge sequence | `.claude/tmp/pr-triage/PR_TRIAGE.md` |
| 6 | Merge | **manual**, in the stage-5 order | Merged PRs, auto-closed issues | Git history |

Then loop: a fresh `/project-review` after a batch of merges is how the next round starts.

Lost your place? `/pipeline` (or `~/.claude/skills/pipeline/pipeline-status`) reads the
right-hand column and tells you which stage you're on — see [Where am I?](#where-am-i--recovering-pipeline-state).

### One-time setup

```bash
gh auth status                                              # stages 2-5 need this
echo '**/.claude/tmp/' >> "$(git config --global core.excludesFile)"
```

The second line keeps `/issue-triage` and `/pr-triage` scratch output out of every repo's
`git status`. Without it each skill falls back to appending to that repo's
`.git/info/exclude` on first run — which works, but is obscure enough to be confusing later.

---

## The through-line: three identifier spaces

The single most important thing the pipeline does is keep **finding ID → issue number → PR
number** connected, because these are conflated constantly and each answers a different
question:

- `F3` — which review row this came from (why it's worth doing)
- `#60` — the durable record of the work (what it is)
- `PR68` — where to review it (where it lives now)

It's carried like this:

```
/project-review    writes  F3 in PROJECT_REVIEW.md
        ↓
/make-issues       records finding_id: F3 in issue #60's fingerprint marker
        ↓
/work-issue        reads it back → branch PR68-Fix-I60-F3-rust-ps-path
        ↓
/pr-triage         displays all three side by side in the merge table
```

Rule that holds at every stage: **an absent ID is correct output; an inferred one is a bug.**
Hand-filed issues have no `F<n>` and never get one — `/make-issues backfill` deliberately
won't invent one, and neither will `/work-issue` or `/pr-triage`.

---

## Stage 1 — Find the work

Two different tools, and they compose rather than compete:

- **`/project-review`** — repo-wide architecture and tech-debt audit. Slow, broad, produces
  numbered findings (`F1`, `F2`, …) with severity *and* effort in
  `docs/reviews/PROJECT_REVIEW.md`. This is the stage-1 default.
- **`/code-review <scope>`** — line-level review of a folder/file/glob. Tiered
  HIGH/IDIOM/MEDIUM/LOW, ~10 findings, ordinals instead of stable IDs, no effort estimate.
  Report goes to `docs/reviews/code-review_<scope>_<date>.md`.

Run `/code-review` first if you want the detail to feed the audit — `/project-review`'s
Phase 1.5 ingests existing code-review reports as evidence. Run it after, scoped to a
subsystem the audit flagged, when you want depth on one area.

Both reports are disposable. Regenerate freely; the finding IDs are reconstructed from git
history so a deleted `PROJECT_REVIEW.md` can't cause an ID collision with issues already filed.

**Also useful here:** `/add-tests` (coverage gaps on recent changes) and `/update-docs`
(doc drift) surface work the review tools don't frame as findings.

## Stage 2 — File the work

```
/make-issues                       # PROJECT_REVIEW.md, Medium+ severity only
/make-issues --all                 # every finding, including Low
/make-issues -f F3 F5 F9           # just these
/make-issues docs/reviews/code-review_src_2026-07-21.md
/make-issues backfill              # retrofit fingerprints onto hand-filed issues
```

This is the first stage that **mutates GitHub**. It creates issues, seeds the label
vocabulary if missing, and dedups against existing issues (open *and* closed) by file path +
keyword overlap. Above ~20% overlap it pauses and asks; below that it just creates.

Run `backfill` once per repo that has pre-existing hand-filed issues. It adds the fingerprint
as a *comment* (never a body edit) so those issues participate in future dedup — and, more
importantly, so stage 3 can see their `file:` field.

**Why the fingerprint matters downstream:** the `file:` field is exactly the overlap signal
`/issue-triage` Phase 2 needs. On a repo where every issue went through `/make-issues` or
`backfill`, most of triage is free. On a repo of raw hand-filed issues, triage has to infer
paths from prose and its grouping is correspondingly weaker.

## Stage 3 — Decide what to work

```
/issue-triage                      # full open queue
/issue-triage #11 #15 #18          # scoped
/issue-triage list                 # past snapshots, live open/closed status
```

Output is a **disposition per issue**, not a ranking — because the two most valuable things
triage finds can't be expressed as an order:

| Disposition | Meaning | Your move |
|---|---|---|
| `WORK n` | Work alone, at position n | Nothing — stage 4 handles it |
| `GROUP` | Collides with another issue at the *symbol* level | Nothing — one branch, one PR, `Fixes #a` + `Fixes #b` |
| `NEEDS-DECISION` | Not implementable as filed; needs a policy/domain call | **Answer the question in the issue, then re-triage** |
| `DEFER` | Speculative or future-scoped | Apply `backlog` yourself if you agree |
| `CLOSE-MOOT` | Another issue supersedes it | Close it yourself if you agree |

The bottom three are the ones that need you. `NEEDS-DECISION` in particular is the stage-3
output to read first: leave one unanswered and stage 4 will halt on it anyway.

A triage run applies nothing — it never labels, closes, or comments. Deferring and closing
are prioritization decisions, and a skill that enacts them is making the call rather than
surfacing it.

The one exception is opt-in and separate:

```
/issue-triage label [#11 #15]      # sync `status: needs-decision` onto GitHub
```

It makes GitHub agree with the snapshot — adding the label to issues currently dispositioned
`NEEDS-DECISION`, removing it from issues in that same snapshot that no longer are — so the
blocked work is visible in the UI rather than only in `.claude/tmp/`. Run it after a triage,
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
push, open the PR, rename the local branch to carry the PR number, tear the worktree down.

Batch mode re-runs `/issue-triage`'s Phases 2–5 **fresh** to order its queue — it never reads
a stale snapshot, since any merge or label change since invalidates one. It works units
sequentially (parallel worktrees on overlapping code is how you manufacture the conflicts
stage 5 then has to untangle), and it halts on `NEEDS-DECISION`.

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
git worktree add .worktrees/PR68-Fix-I60-F3-rust-ps-path PR68-Fix-I60-F3-rust-ps-path
git push origin HEAD:Fix-I60-F3-rust-ps-path    # explicit refspec — names differ after the rename
```

## Stage 5 — Decide merge order

```
/pr-triage                         # full open queue
/pr-triage #7 #8 #12               # scoped burn-down
/pr-triage list                    # past snapshots, live merged/closed status
```

Ranks by **blast radius** — how many other open PRs share a file with this one — ascending,
so each merge disturbs the fewest remaining PRs. Ties break on staleness, then size. A PR
linked to a critical-severity issue is promoted to a critical tier ahead of the whole queue,
and the report says outright which PRs pay for that in extra rebase work.

Worth reading beyond the order itself: the **likely semantic collision** pairs. Those are the
ones where a careless rebase resolution merges cleanly and is still wrong.

## Stage 6 — Merge, manually

Deliberately not automated. Work down the stage-5 sequence one PR at a time:

1. `/code-review` (or `/review`) the specific PR for the line-level pass, if it hasn't had one.
2. Merge it on GitHub. `Fixes #<n>` in the body closes the issue(s) automatically.
3. **Re-run `/pr-triage`** — repeat-run mode re-ranks what's left against the new base and
   tells you what changed. The previous order is invalidated by every merge; don't work down
   a stale list.
4. `git branch -d PR68-Fix-I60-F3-rust-ps-path` when the PR is merged. The PR number in the
   name is what makes this cheap; cleanup is manual on purpose.

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
| Is there a current review? | `ls -lt docs/reviews/` — compare its date against `git log -1` |
| Were the findings filed? | `gh issue list --state all --label "source: project-review" --label "source: code-review"` |
| Which issues are untriaged? | `/issue-triage list` — outstanding units vs. `gh issue list --state open` |
| Is anything blocked on me? | The `NEEDS-DECISION` / `DEFER` / `CLOSE-MOOT` sections of the latest `ISSUE_TRIAGE.md` |
| What work is in flight? | `git branch -a \| grep -E 'Fix-I[0-9]+'` and `gh pr list` |
| Is there a merge order? | `/pr-triage list` — and whether anything merged since it was generated |
| What's finished? | `gh pr list --state merged --limit 20` |

Both `list` subcommands resolve their snapshots against **live** GitHub state, so a snapshot
whose queue has entirely resolved shows up as fully closed rather than as pending work.
`/issue-triage clean` and `/pr-triage clean` remove exactly those.

---

## Variants

**Not GitHub-backed.** Stages 2–5 don't apply. Run stage 1, work findings directly off the
report, use the inner loop. The finding ID stays useful in commit messages.

**One known bug, no review.** File the issue by hand (`gh issue create`), then
`/work-issue <n>`. Skip stages 1, 2, 3, 5. The branch just has no `F<n>` segment.

**Language-learning sprint.** `/code-review src/ --focus idiom` → `/make-issues <report>` →
stage 3 onward as normal. IDIOM findings carry a derived severity so they order alongside
everything else.

**Small queue.** Under ~3 issues, stage 3 earns little — but run it anyway if any two touch
the same file, since `GROUP` is what stops you from opening two PRs that conflict by
construction. Under ~3 PRs, stage 5 earns little; blast radius on a queue of two is trivial.

---

## What the pipeline deliberately won't do

Each of these is a decision that belongs to you, and every skill involved is written to
surface it rather than take it:

- **Merge anything.** `/pr-triage` is advisory, full stop.
- **Close or defer an issue.** `/issue-triage` proposes `CLOSE-MOOT` and `DEFER`; it never
  applies a `backlog` label or closes anything, and `/work-issue` won't act on those
  proposals either. `/issue-triage label` is the one sanctioned mutation, and it touches
  exactly one label after showing you both the additions and the removals.
- **Decide a `NEEDS-DECISION` issue.** Batch mode halts instead of picking a policy and
  letting you discover it by reading a diff.
- **Work a deferred issue in batch.** An explicit `/work-issue <n>` can override, but only
  after asking.
- **Work in the main checkout.** Every change happens in the issue's worktree.
- **Invent an identifier.** No guessed finding IDs, issue numbers, or dependencies —
  `—` is the correct output for absent.
