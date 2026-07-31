# Stacked PRs for overlapping issues — design

Status: designed, not yet implemented. Touches `/issue-triage`, `/work-issue`, `/pr-triage`,
`pipeline-status`, and `WORKFLOW.md`.

## Problem

`/work-issue all` cuts every branch from `origin/<base>` (`work-issue/SKILL.md`, Phase 3
step 3). A batch of ten issues produces ten PRs that all describe a world in which none of
the other nine happened. Merge the first and the second may conflict — not because its fix is
wrong, but because it was authored against a base that no longer exists.

`/issue-triage` already detects this, and already handles the severe half of it. Phase 2
builds two edge types:

- `COLLIDES` — two issues change the same function or symbol → `GROUP` → one branch, one PR.
  These can't conflict, by construction.
- `OVERLAPS` — same file, different symbols → **nothing**.

The `OVERLAPS` band is deliberately left alone, for a good reason documented at
`issue-triage/SKILL.md:328`: grouping on file overlap would collapse an entire queue into one
PR on any repo with a few large modules. But leaving it alone means those units get
independent PRs off the same stale base, which is precisely where the conflicts come from.

The band is stranded: too weak to justify one shared PR, too strong to ignore.

## Goals

- Author each overlapping unit on top of the one before it, so collisions are resolved when
  the code is written rather than when it's merged.
- Keep the existing `GROUP` and `WORK` behavior untouched.
- Add no wall-clock cost to `/work-issue all`.
- Give a stacked child a deterministic path back onto the base branch after its parent merges,
  independent of the repo's merge mode.
- Never let a stacked PR be merged before its parent.

## Non-goals

- **Not automatic merging or restacking.** The restack force-pushes; it stays an explicit
  command the user runs, consistent with stage 6 being manual on purpose.
- **Not stacking across `COLLIDES`.** Those still become one `GROUP` PR. Stacking two PRs that
  rewrite the same function gives the reviewer two half-answers.
- **Not unbounded chain depth.** Capped at 3 (see "Depth cap").
- **Not fork or cross-repo stacking.** The parent branch must be on the same remote.
- **Not a general-purpose stacked-PR tool.** No `git town` / `graphite`-style restack of an
  arbitrary tree. One linear chain per collision cluster, that's all.
- **Not a fix for semantic collisions.** Two changes that merge cleanly and are still jointly
  wrong remain `/pr-triage`'s "likely semantic collision" to flag.

## Evidence: why the restack records a sha

Tested in scratch repos rather than reasoned about, because the behavior is not what it
first appears.

**Squash-merged parent.** The child rebases cleanly if the parent had **one** commit — git
computes patch-ids, sees the patch already applied, drops it. With **two** commits the squash
produces a single new patch that is patch-identical to neither original, so git tries to
re-apply both and **conflicts, on a line the child never touched.** A `/work-issue` PR picks
up a second commit the moment review asks for a change, so this is the common case, not the
edge case.

**Rebase-merged parent** (the workflow this repo's author uses). The parent's commits are
replayed onto the base with new shas. The child's copies are patch-identical to the rewritten
ones, so a plain `git rebase <base> <child>` drops them cleanly. Differing shas are irrelevant
— git reconciles by patch content. `git merge --ff-only` does fail, since the child is no
longer a descendant of the base, but that is not a path this design uses.

**Both modes** are handled by replaying only the child's own commits:

```bash
git rebase --onto origin/<base> <recorded parent head> <child branch>
```

That command is why the parent's head sha is recorded at branch-creation time. It makes the
restack independent of how anyone chooses to merge the parent.

## Design

### `/issue-triage` — the `STACK` disposition

`STACK` is the missing middle tier between `GROUP` and `WORK`.

Note that `STACK` is **not** assigned by Phase 3's precedence table, which is unchanged.
Phase 3 can't assign it: whether a unit stacks depends on which units rank ahead of it, and
that isn't known until Phase 4 has run. `STACK` and `HOLD` are assigned afterwards, in a new
Phase 4.5, by converting units Phase 3 already dispositioned `WORK`.

| Disposition | Assign when | Effect |
|---|---|---|
| `STACK` | The unit has an `OVERLAPS` edge (without `COLLIDES`) to a unit ranked earlier in this run's order | Branched from that unit's branch, PR based on it. Merges after it. |
| `HOLD` | It would be the 4th unit in a collision cluster | Not worked this batch. Reported for the next one. |

**The parent is determined by order, not by disposition**, so this needs a new phase rather
than a change to Phase 3:

> **Phase 4.5: Form stacks.** After Phase 4 has ranked the units, walk the ordered list,
> considering only units Phase 3 dispositioned `WORK` (`GROUP` units are skipped). For each
> such unit with an `OVERLAPS` edge to any earlier unit, mark it `STACK` on the *nearest*
> such unit. A unit with no earlier overlap stays `WORK`. Chains form transitively: if #15
> stacks on #11 and #18 overlaps #15, #18 stacks on #15 — that's a depth-3 chain.

Phase 3 keeps assigning `WORK`/`GROUP` exactly as it does now; Phase 4.5 only ever converts
`WORK` → `STACK` or `HOLD`. `GROUP` units can *be* a parent (a group's branch is a branch like
any other) but are never themselves converted.

**Depth cap: 3.** A 4th unit in the same cluster becomes `HOLD` — reported as "held to the
next batch, overlaps the #11 → #15 → #18 chain" rather than stacked. Rationale: a rejected PR
at the bottom of a chain forces a restack of everything above it, and that cost grows with
depth while the benefit doesn't.

**Snapshot** gains a `stack` block on stacked units:

```yaml
  - order: 2
    disposition: STACK
    critical: false
    stack:
      parent_order: 1
      parent_issue: 11
      depth: 2
    issues:
      - number: 15
        finding: F9
```

`HOLD` units get `order: ~` and a `held_for:` naming the chain, alongside the existing
dispositions that carry no position.

### `/work-issue` — branch from the parent, record the sha

Batch mode is **already sequential** (`work-issue/SKILL.md:213` — one worktree at a time,
torn down before the next). The parent's branch therefore always exists before the child
starts. **Stacking costs no wall-clock in batch mode**; it only spends parallelism when the
user fans out agents by hand, and then only within a cluster.

Phase 3 step 3, for a `STACK` unit, branches from the parent's *remote* branch rather than
the base — the remote name is the stable one, since Phase 6 renames the local branch to carry
the PR number:

```bash
git worktree add .worktrees/<working-name> -b <working-name> origin/<parent working name>
```

Phase 5 opens the PR against the parent:

```bash
gh pr create --base <parent working name> --title ... --body ...
```

and the body carries a marker, following the same convention as `/make-issues`' fingerprint
and this skill's own resolution marker:

```html
<!-- work-issue-stack
parent_pr: 68
parent_branch: Fix-I60-F3-rust-ps-path
parent_head: 1a2b3c4d5e6f7890abcdef1234567890abcdef12
-->
```

The PR body is the right home for it: the worktree is torn down in Phase 6, the local branch
may be deleted after merge, and the body survives both. `parent_head` is the value the
restack needs and the one nothing else records.

The **resolution comment** for a stacked unit says so — that the PR is stacked on #68 and
can't merge before it — since a reporter reading the issue would otherwise expect it to be
mergeable.

**Batch plan.** Stacking is automatic, and the confirmation shown before a batch of more than
~3 units lists the chains explicitly:

```
  #11  WORK              base: main
  #15  STACK on #11      base: Fix-I11-...
  #18  STACK on #15      base: Fix-I15-...
  #21  HOLD              overlaps the #11 chain, held to next batch
```

Nothing is silent; it just doesn't need a flag.

### `/work-issue restack` — the one new subcommand

```
/work-issue restack              # every open PR whose parent has merged
/work-issue restack 71 74        # scoped
```

Per child PR carrying a `work-issue-stack` marker:

1. Read `parent_pr`, `parent_branch`, `parent_head` from the body.
2. Determine what happened to the parent:

   | Parent state | Action |
   |---|---|
   | Merged | Restack onto the base branch |
   | Open, head still `parent_head` | Nothing to do — report and skip |
   | Open, head moved (force-push or new commits) | Restack onto the parent's branch (the marker's `parent_branch`) |
   | Closed unmerged | **Report and stop.** The child's base is gone; whether its change still makes sense is a judgment call, not a rebase |

3. `git fetch origin`, then
   `git rebase --onto origin/<target> <parent_head> <child branch>` in a worktree.
4. On conflict: stop, keep the worktree, print its path. Never resolve a rebase conflict
   unattended — that's the semantic-collision case, and a wrong resolution merges clean.
5. Verify before pushing: `git log --oneline origin/<target>..<child>` must contain only the
   child's own commits. If the parent's commits are still present, something is wrong —
   report rather than push.
6. `git push --force-with-lease` — never bare `--force`. Confirm before pushing.
7. **Update the marker** with the new `parent_head` (and `parent_branch` → the base branch,
   plus a fourth line `resolved: true`, once the parent merged), so a second restack is as
   deterministic as the first. **`parent_pr` is never removed** — the corruption check requires
   all three original keys, and a marker missing one reads as corrupt on every later scan even
   though the restack that produced it succeeded. A marker written once and never refreshed
   goes stale on the first parent force-push.
8. Retarget the PR base if GitHub hasn't (`gh pr edit <n> --base <target>`). GitHub
   auto-retargets children when a parent merges; step 8 is the fallback for the cases it
   doesn't, and is a no-op when it already did.

### `/pr-triage` — stacks are a hard ordering constraint

0. **Queue membership.** A stacked child's `baseRefName` is its parent's branch, not the repo
   base — Phase 1's existing same-base filter drops it before any of the rules below can see
   it. The filter must also admit any PR whose `baseRefName` matches another open PR's
   `headRefName`.
1. **Topological constraint, satisfied as a block move.** A child never ranks above its
   parent — this joins the existing critical-severity promotion as a rule that outranks blast
   radius, with the difference that a stack violation isn't a preference, it's unmergeable.
   The ascending blast-radius sort has no way to know about it on its own, so the algorithm is
   explicit: a chain (parent plus every descendant) sorts as one block, positioned at its
   root's blast-radius rank, then unpacks internally in link order (parent first). The
   critical-severity promotion is the same block-move triggered by the critical tier instead
   of a blast-radius rank — one rule, not two.
2. **No blast-radius correction needed.** A stacked child's PR is opened against its parent's
   branch (`gh pr create --base <parent branch>`), so `gh pr diff --name-only` already returns
   only the child's own files — the parent's files never enter its overlap set. There's
   nothing to subtract, and this holds after a restack too, since the restacked branch still
   carries only the child's own commits.
3. **Display.** Show chains as a unit, with children marked blocked until the parent merges,
   and the merge sequence naming the restack between links:

   > merge #68 → `/work-issue restack` → merge #71 → `/work-issue restack` → merge #74

### `pipeline-status` and `WORKFLOW.md`

`pipeline-status` gains a check for open PRs whose parent PR has merged, and recommends
`/work-issue restack` when it finds any — it sits between "merge the top PR" and "re-run
`/pr-triage`" in the cascade.

`WORKFLOW.md` stage 4 documents the stacking model; stage 6's loop becomes: review → merge →
**restack** → re-run `/pr-triage`.

## Risks

- **A rejected parent invalidates its chain.** Depth 3 caps the blast radius at two restacks.
  A parent closed unmerged is reported, never auto-rebased.
- **Force-push.** Mitigated by `--force-with-lease`, an explicit confirm, the pre-push
  verification in step 5, and by living in its own subcommand rather than firing during a
  batch.
- **Marker drift.** A `parent_head` that isn't refreshed on every restack silently degrades
  the second restack into a plain rebase. Step 7 is not optional.
- **Reviewer confusion.** A PR based on another branch shows only its own diff, which is the
  desirable behavior, but the base branch name in the GitHub UI is unfamiliar. The resolution
  comment saying "stacked on #68" is the mitigation.

## Open questions

- Whether `HOLD` units should be auto-worked by a follow-up `/work-issue all` once the chain
  merges, or wait for the user to re-run. Leaning: wait — it's the same "every stage leaves a
  durable trace" argument, and a batch that silently continues later is hard to reason about.
- Whether `/pr-triage` should offer to run the restack itself after showing the order. Kept
  out of v1 deliberately: it is advisory-only today, and a force-push is a poor first
  mutation for it.
