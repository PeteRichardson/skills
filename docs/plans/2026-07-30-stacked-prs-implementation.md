# Stacked PRs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `/work-issue all` from producing PRs that conflict with each other, by authoring each overlapping unit on top of the previous one instead of on a shared stale base.

**Architecture:** `/issue-triage` gains a Phase 4.5 that converts `WORK` units into `STACK` (branch from the previous unit) or `HOLD` (defer past the depth cap) after ordering. `/work-issue` branches stacked units from the parent's remote branch, targets the PR at it, and records the parent's head sha in a PR-body marker. A new `/work-issue restack` subcommand replays a child's own commits onto the base once the parent merges. `/pr-triage` treats a stack as a hard ordering constraint.

**Tech Stack:** Markdown skill definitions executed by Claude; `bash` + `git` + `gh` for the one executable artifact (`pipeline-status`) and the restack test harness.

## Global Constraints

Copied verbatim from `docs/specs/2026-07-30-stacked-prs-design.md`. Every task's requirements implicitly include these.

- **This repo has no build, lint, or test tooling.** The "code" is Markdown instructions. Verification for a Markdown task is a `grep` assertion that fails before the edit and passes after; only Task 1 produces executable code with a real test cycle.
- **`~/.claude/skills` is a symlink to this repo.** Every edit is live in new sessions immediately. There is no install step and no way to stage a change.
- **Commits are conventional, scoped to the skill directory:** `feat(issue-triage): ...`, `feat(work-issue): ...`, `feat(pr-triage): ...`, `docs(workflow): ...`.
- **Depth cap is 3** (parent + 2 children). The 4th unit in a collision cluster becomes `HOLD`.
- **Never bare `git push --force`.** Always `--force-with-lease`.
- **Phase 3's disposition precedence table in `issue-triage/SKILL.md` is not modified.** `STACK` and `HOLD` are assigned in the new Phase 4.5 by converting units already dispositioned `WORK`.
- **No skill may auto-restack, auto-merge, or auto-close.** `/work-issue restack` is run by the user.
- **Never invent an identifier.** Absent is correct output; inferred is a bug (`WORKFLOW.md`).
- **When a skill's name or cross-reference changes, grep the other `SKILL.md` files for dependents** (`AGENTS.md`).

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `work-issue/restack-recipe.test.sh` | **Create.** Proves the `git rebase --onto` recipe works under all three GitHub merge modes, and that the naive alternative doesn't | 1 |
| `issue-triage/SKILL.md` | **Modify.** New Phase 4.5, `STACK`/`HOLD` dispositions, `stack:` snapshot block | 2 |
| `work-issue/SKILL.md` | **Modify.** Phase 3 branches from parent, Phase 5 targets parent + writes marker, batch plan shows chains | 3 |
| `work-issue/SKILL.md` | **Modify.** `restack` subcommand in Phase 0 + its own protocol section | 4 |
| `pr-triage/SKILL.md` | **Modify.** Topological constraint in Phase 3, blast-radius correction, chain display in Phase 5 | 5 |
| `pipeline/pipeline-status`, `WORKFLOW.md`, `pipeline/SKILL.md` | **Modify.** Detect restack-needed state; document the model and the stage-6 loop | 6 |

Tasks 3 and 4 both modify `work-issue/SKILL.md` but are split because a reviewer could reasonably accept the stacking behavior while rejecting the force-pushing subcommand. Task 3 leaves the skill in a coherent state on its own: stacks get created, and the manual `git rebase --onto` recipe is documented for undoing them.

---

### Task 1: Restack recipe test harness

The restack is the one piece of this design that can be executed and therefore genuinely tested. Its correctness is non-obvious — a naive `git rebase` looks like it works and then conflicts on a line nobody touched — so the recipe gets a test before any skill documents it.

**Files:**
- Create: `work-issue/restack-recipe.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the verified command form `git rebase --onto <target> <recorded parent head> <child branch>`, referenced by name in Tasks 3, 4, and 6. Exit code 0 = all scenarios pass.

- [ ] **Step 1: Confirm the red state**

```bash
cd /Users/pete/projects/skills && ./work-issue/restack-recipe.test.sh; echo "exit=$?"
```

Expected: `no such file or directory`, `exit=127`.

- [ ] **Step 2: Write the test**

Create `work-issue/restack-recipe.test.sh`:

```bash
#!/usr/bin/env bash
# Verifies the restack recipe used by `/work-issue restack`.
#
# The recipe replays only the CHILD's commits onto the target, using the parent
# head sha recorded in the child PR's <!-- work-issue-stack --> marker:
#
#     git rebase --onto <target> <recorded parent head> <child branch>
#
# Scenarios 1-3 prove it works under every GitHub merge mode. Scenario 4 is a
# negative control proving the naive alternative does NOT, which is the entire
# reason the marker records a sha. See
# docs/specs/2026-07-30-stacked-prs-design.md ("Evidence").
set -uo pipefail

PASSES=0; FAILURES=0
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

# base -> parent (TWO commits, the second revising the first) -> child (one
# commit, a different line). Two parent commits is what breaks naive rebasing;
# a /work-issue PR gets a second commit as soon as review asks for a change.
build() {
  local d="$ROOT/$1"
  mkdir -p "$d"; cd "$d" || exit 1
  git init -q -b main .
  git config user.email test@example.com; git config user.name Test
  printf 'line1\nline2\nline3\nline4\nline5\n' > f.txt
  git add -A; git commit -qm "base"
  git checkout -qb parent
  sed -i.bak 's/line2/line2-parent-attempt1/' f.txt; rm -f f.txt.bak
  git commit -qam "parent attempt 1"
  sed -i.bak 's/line2-parent-attempt1/line2-parent-final/' f.txt; rm -f f.txt.bak
  git commit -qam "parent attempt 2"
  PARENT_HEAD=$(git rev-parse HEAD)   # the value the PR-body marker records
  git checkout -qb child
  sed -i.bak 's/line4/line4-child/' f.txt; rm -f f.txt.bak
  git commit -qam "child fix"
  git checkout -q main
}

ok()  { PASSES=$((PASSES+1));   printf '  ok    %s\n' "$1"; }
bad() { FAILURES=$((FAILURES+1)); printf '  FAIL  %s\n' "$1"; }

# A correct restack leaves exactly one commit ahead of main and both fixes in the file.
assert_restacked() {
  local label=$1 n content
  n=$(git log --oneline main..child | wc -l | tr -d ' ')
  content=$(cat f.txt)
  if [ "$n" != "1" ]; then
    bad "$label: expected 1 commit ahead of main, got $n"; return
  fi
  case "$content" in
    *line2-parent-final*) : ;;
    *) bad "$label: parent's fix missing from working tree"; return ;;
  esac
  case "$content" in
    *line4-child*) : ;;
    *) bad "$label: child's fix missing from working tree"; return ;;
  esac
  ok "$label"
}

echo "restack recipe"

# --- Scenario 1: parent squash-merged ---------------------------------------
build squash
git merge --squash parent >/dev/null 2>&1 && git commit -qm "squashed parent (#68)"
git checkout -q child
if git rebase --onto main "$PARENT_HEAD" child >/dev/null 2>&1; then
  assert_restacked "squash-merged parent"
else
  git rebase --abort >/dev/null 2>&1; bad "squash-merged parent: rebase conflicted"
fi

# --- Scenario 2: parent rebase-merged (commits replayed with NEW shas) -------
# main must move first, otherwise the replay reproduces identical shas and the
# scenario is degenerate.
build rebase
printf 'from another PR\n' > other.txt; git add -A; git commit -qm "unrelated PR merged"
git cherry-pick "$PARENT_HEAD~1" "$PARENT_HEAD" >/dev/null 2>&1
if [ "$(git rev-parse HEAD)" = "$PARENT_HEAD" ]; then
  bad "rebase-merged parent: setup degenerate, shas did not change"
else
  git checkout -q child
  if git rebase --onto main "$PARENT_HEAD" child >/dev/null 2>&1; then
    assert_restacked "rebase-merged parent"
  else
    git rebase --abort >/dev/null 2>&1; bad "rebase-merged parent: rebase conflicted"
  fi
fi

# --- Scenario 3: parent merged with a merge commit --------------------------
build mergecommit
git merge -q --no-ff parent -m "merge parent (#68)"
git checkout -q child
if git rebase --onto main "$PARENT_HEAD" child >/dev/null 2>&1; then
  assert_restacked "merge-commit parent"
else
  git rebase --abort >/dev/null 2>&1; bad "merge-commit parent: rebase conflicted"
fi

# --- Scenario 4: NEGATIVE CONTROL -------------------------------------------
# Naive `git rebase main child` with a squash-merged multi-commit parent must
# CONFLICT. If this ever starts passing, the marker's sha is no longer load
# bearing and the design can be simplified -- but verify that deliberately.
build naive
git merge --squash parent >/dev/null 2>&1 && git commit -qm "squashed parent (#68)"
git checkout -q child
if git rebase main >/dev/null 2>&1; then
  bad "negative control: naive rebase unexpectedly succeeded (recipe may be unnecessary)"
else
  git rebase --abort >/dev/null 2>&1
  ok "negative control: naive rebase conflicts, as expected"
fi

printf '\n%d passed, %d failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x work-issue/restack-recipe.test.sh
```

- [ ] **Step 4: Run the test and make sure it passes**

```bash
./work-issue/restack-recipe.test.sh; echo "exit=$?"
```

Expected output:

```
restack recipe
  ok    squash-merged parent
  ok    rebase-merged parent
  ok    merge-commit parent
  ok    negative control: naive rebase conflicts, as expected

4 passed, 0 failed
exit=0
```

If scenario 4 reports `unexpectedly succeeded`, **stop and report it** — it means the recorded sha is no longer necessary and Tasks 3–4 should be simplified rather than implemented as written.

- [ ] **Step 5: Commit**

```bash
git add work-issue/restack-recipe.test.sh
git commit -m "test(work-issue): verify restack recipe across all three merge modes"
```

---

### Task 2: `/issue-triage` — Phase 4.5, `STACK` and `HOLD`

**Files:**
- Modify: `issue-triage/SKILL.md` — insert a new section after Phase 4 (currently line 94, ends where `## Phase 5: Deliverable` begins at line 104); extend the snapshot YAML example (~line 129) and the Phase 5 report sections (~line 169–179)

**Interfaces:**
- Consumes: the `OVERLAPS` / `COLLIDES` edges from Phase 2 (unchanged), and the ordered unit list from Phase 4 (unchanged).
- Produces: two new disposition values, `STACK` and `HOLD`, and a `stack:` block in the snapshot frontmatter with keys `parent_order`, `parent_issue`, `depth`. `/work-issue` batch mode reads these in Task 3. `HOLD` units carry `order: ~` and `held_for:`.

- [ ] **Step 1: Write the failing assertion**

```bash
cd /Users/pete/projects/skills
grep -q '^## Phase 4.5: Form stacks' issue-triage/SKILL.md && echo PASS || echo FAIL
grep -q 'parent_order' issue-triage/SKILL.md && echo PASS || echo FAIL
```

Expected: `FAIL` twice.

- [ ] **Step 2: Insert Phase 4.5**

Immediately before `## Phase 5: Deliverable` in `issue-triage/SKILL.md`, insert:

```markdown
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
```

- [ ] **Step 3: Extend the snapshot schema**

In the Phase 5 YAML example, add a stacked unit and a held unit after the existing `WORK`
unit (`order: 2`, issue 14). Insert before the `NEEDS-DECISION` entry:

```yaml
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
```

- [ ] **Step 4: Add the report sections**

In Phase 5's body sections (alongside the existing "Grouping detail" and "Relationship
graph" bullets), add:

```markdown
* **Stack detail** — for each chain, the order of its links, which file overlap put each
  child on its parent, and the explicit note that a child cannot merge before its parent.
* **Held units** — every `HOLD` unit, which chain it overlaps, and that it is a candidate for
  the next batch rather than a deferral. `HOLD` is a scheduling consequence of the depth cap,
  not a judgment about the issue — keep it out of the `DEFER` section, which is a judgment.
```

- [ ] **Step 5: Update the disposition table in the skill's own `description` and summary table**

The frontmatter `description` lists what the skill produces. Add `STACK`/`HOLD` to the
"disposition per issue" phrasing so the trigger text stays accurate:

Change `a disposition per issue, and an ordered work plan` to
`a disposition per issue (including stacked and held units), and an ordered work plan`.

- [ ] **Step 6: Run the assertions to verify they pass**

```bash
cd /Users/pete/projects/skills
grep -q '^## Phase 4.5: Form stacks' issue-triage/SKILL.md && echo PASS || echo FAIL
grep -q 'parent_order' issue-triage/SKILL.md && echo PASS || echo FAIL
grep -q 'held_for' issue-triage/SKILL.md && echo PASS || echo FAIL
grep -c 'HOLD' issue-triage/SKILL.md
```

Expected: `PASS`, `PASS`, `PASS`, and a count of at least 5.

Also confirm Phase 3's table was **not** touched:

```bash
git diff issue-triage/SKILL.md | grep -c '^-.*CLOSE-MOOT'
```

Expected: `0`.

- [ ] **Step 7: Commit**

```bash
git add issue-triage/SKILL.md
git commit -m "feat(issue-triage): add STACK and HOLD dispositions via a new Phase 4.5"
```

---

### Task 3: `/work-issue` — branch from the parent and record its head

**Files:**
- Modify: `work-issue/SKILL.md` — Phase 3 (line 129, step 3 at line 135), Phase 5 (line 146, steps 1–2 and the resolution comment step 4), Batch mode (line 185, the disposition table ~line 205 and step 6 at ~line 217), and Rules (line 228)

**Interfaces:**
- Consumes: `STACK` / `HOLD` dispositions and the `stack:` block from Task 2.
- Produces: the `<!-- work-issue-stack -->` PR-body marker with keys `parent_pr`, `parent_branch`, `parent_head`. Task 4's `restack` subcommand reads exactly these three keys; Task 5 reads `parent_pr`.

- [ ] **Step 1: Write the failing assertion**

```bash
cd /Users/pete/projects/skills
grep -q 'work-issue-stack' work-issue/SKILL.md && echo PASS || echo FAIL
grep -q 'gh pr create --base' work-issue/SKILL.md && echo PASS || echo FAIL
```

Expected: `FAIL` twice.

- [ ] **Step 2: Make Phase 3 branch from the parent**

Replace Phase 3 step 3 (currently `git worktree add .worktrees/<working-name> -b <working-name> origin/<base>`) with:

```markdown
3. Create the worktree, branched from the base — or, for a `STACK` unit, from its parent:

   ```bash
   # WORK / GROUP unit — unchanged
   git worktree add .worktrees/<working-name> -b <working-name> origin/<base>

   # STACK unit — branch from the parent's REMOTE branch
   git worktree add .worktrees/<working-name> -b <working-name> origin/<parent working name>
   ```

   Use the parent's **remote** name (`Fix-I60-F3-…`), never its local one. Phase 6 renames the
   local branch to carry the PR number (`PR68-Fix-I60-F3-…`); the remote name is the stable
   identifier and is what the parent's PR actually points at.

   Record `git rev-parse origin/<parent working name>` now — Phase 5 writes it into the PR
   body, and it is the value `/work-issue restack` needs later. Capture it before doing any
   work, so it names the commit this branch was actually cut from.
```

- [ ] **Step 3: Make Phase 5 target the parent and write the marker**

Replace Phase 5 steps 1–2 with:

```markdown
1. `git push -u origin <working-name>` — the remote branch keeps this name permanently.
2. `gh pr create --title "<title>" --body "<body>"`. The body must contain `Fixes #<n>` so
   GitHub links the issue, and should name the finding ID (`Addresses F3 from the project
   review`) when there is one.

   **For a `STACK` unit**, add `--base <parent working name>` so the PR targets its parent
   rather than the base branch, and include the stack marker in the body:

   ```html
   <!-- work-issue-stack
   parent_pr: 68
   parent_branch: Fix-I60-F3-rust-ps-path
   parent_head: 1a2b3c4d5e6f7890abcdef1234567890abcdef12
   -->
   ```

   `parent_head` is the sha captured in Phase 3. The PR body is the only durable home for it:
   the worktree is gone by the end of Phase 6, and the local branch may be deleted after the
   merge. Without it, `/work-issue restack` has to guess where the parent's commits end.

   Never write a marker with an inferred value. If the parent's PR number isn't known yet
   because its `gh pr create` failed, this unit doesn't get created either — report and stop.
```

- [ ] **Step 4: Mention the stack in the resolution comment**

In Phase 5 step 4 (the resolution comment), add after the existing composition rules:

```markdown
   For a `STACK` unit, the comment must say the PR is stacked on #`<parent_pr>` and cannot
   merge until that one does. A reporter reading the issue would otherwise reasonably expect
   an open PR to be mergeable, and the GitHub UI shows the unfamiliar base branch without
   explaining it.
```

- [ ] **Step 5: Add the batch-mode dispositions and plan display**

In Batch mode's disposition table, add two rows after the `GROUP` row:

```markdown
   | `STACK` | Work it on a branch cut from its parent's remote branch, PR based on that branch. The parent is always earlier in the same run, so its branch already exists — batch mode is sequential. |
   | `HOLD` | Report as held for the next batch, naming the chain it overlaps, and skip. Not a deferral: nothing is wrong with the issue, it just exceeds the depth cap. |
```

And extend batch step 6 (the confirmation) to show chains:

```markdown
6. Before starting a batch of more than ~3 units, show the triage plan and confirm. Each unit
   opens a real PR. The plan names each unit's base explicitly, so a stack is visible before
   anything is pushed:

   ```
     #11  WORK              base: main
     #15  STACK on #11      base: Fix-I11-F2-config-parse
     #18  STACK on #15      base: Fix-I15-F9-config-validate
     #21  HOLD              overlaps the #11 -> #15 -> #18 chain, held to next batch
   ```

   Stacking needs no flag. It is what the triage already decided; the plan is where it
   becomes visible.
```

- [ ] **Step 6: Add the rules**

Append to the Rules section:

```markdown
* Never cut a `STACK` unit's branch from the base. The whole point is that it sees its
  parent's changes while the code is being written; branching from the base silently produces
  exactly the conflict this disposition exists to prevent.
* Never write a `work-issue-stack` marker with a guessed `parent_head`. If the sha wasn't
  captured in Phase 3, re-derive it with `git rev-parse origin/<parent branch>` before the
  branch has any commits of its own — never after.
* Never stack onto a parent whose PR failed to open. No parent PR, no child.
```

- [ ] **Step 7: Document the manual restack**

Task 4 adds the subcommand. Until then — and as the fallback whenever it isn't wanted — add to
the "Coming back to a PR later" section:

```markdown
### Restacking a child by hand

When a stacked PR's parent merges, replay only the child's own commits onto the base, using
the `parent_head` recorded in the child PR's `work-issue-stack` marker:

```bash
git fetch origin
git rebase --onto origin/<base> <parent_head> <child branch>
git push --force-with-lease
```

`--onto` with the recorded sha is what makes this independent of how the parent was merged. A
plain `git rebase origin/<base>` works when the parent was rebase-merged and **conflicts on
untouched lines** when it was squash-merged with more than one commit. Verified by
`work-issue/restack-recipe.test.sh`.
```

- [ ] **Step 8: Run the assertions to verify they pass**

```bash
cd /Users/pete/projects/skills
grep -q 'work-issue-stack' work-issue/SKILL.md && echo PASS || echo FAIL
grep -q 'gh pr create --title' work-issue/SKILL.md && echo PASS || echo FAIL
grep -q 'parent_head' work-issue/SKILL.md && echo PASS || echo FAIL
grep -q 'force-with-lease' work-issue/SKILL.md && echo PASS || echo FAIL
grep -c 'force"' work-issue/SKILL.md || true
```

Expected: `PASS` ×4, and no bare `--force"` occurrences.

- [ ] **Step 9: Commit**

```bash
git add work-issue/SKILL.md
git commit -m "feat(work-issue): branch STACK units from their parent and record its head sha"
```

---

### Task 4: `/work-issue restack`

**Files:**
- Modify: `work-issue/SKILL.md` — Phase 0 (line 104, the invocation table), a new protocol section after "Coming back to a PR later" (line 172), the Rules section, and Usage (line 253)

**Interfaces:**
- Consumes: the `work-issue-stack` marker keys `parent_pr`, `parent_branch`, `parent_head` from Task 3, and the recipe verified in Task 1.
- Produces: the invocation `/work-issue restack [<pr>…]`. Task 5 (`/pr-triage`) and Task 6 (`pipeline-status`) both name this command as a next step.

- [ ] **Step 1: Write the failing assertion**

```bash
cd /Users/pete/projects/skills
grep -q '/work-issue restack' work-issue/SKILL.md && echo PASS || echo FAIL
grep -q 'force-with-lease' work-issue/SKILL.md && echo PASS || echo FAIL
```

Expected: `FAIL` for the first (the second already passes from Task 3 — that's expected, it's the manual recipe).

- [ ] **Step 2: Add the subcommand to Phase 0**

In Phase 0's invocation resolution, add:

```markdown
* `restack` — `/work-issue restack` (every open stacked PR whose parent has moved or merged)
  or `/work-issue restack 71 74` (scoped to those PRs). Skips Phases 1–6 entirely and runs
  the restack protocol below. It works no issues and opens no PRs.
```

- [ ] **Step 3: Write the restack protocol**

Insert a new section after "Coming back to a PR later":

```markdown
## The `restack` subcommand

Replays a stacked child's own commits onto its new base after its parent moved. This is the
only part of this skill that force-pushes, which is why it's an explicit command rather than
something a batch run does on its own.

1. **Find the candidates.** `gh pr list --state open --json number,body,headRefName,baseRefName`
   and keep those whose body contains a `<!-- work-issue-stack` marker. Scoped invocation
   filters this list; a named PR with no marker is reported as such, not guessed at.
2. **Read the marker** for `parent_pr`, `parent_branch`, `parent_head`. A marker missing any
   of the three is corrupt — report it and skip that PR. Never reconstruct a `parent_head`
   from the branch's current position; that's the one value that can't be re-derived once the
   parent has moved.
3. **Classify the parent** with `gh pr view <parent_pr> --json state,headRefOid,baseRefName`:

   | Parent state | Action |
   |---|---|
   | Merged | Restack onto the parent's own base branch |
   | Open, `headRefOid` still equals `parent_head` | Nothing to do — report "up to date" and skip |
   | Open, `headRefOid` has moved | Restack onto the parent's new head |
   | Closed unmerged | **Report and stop for this PR.** Its base is gone, and whether the child still makes sense is a judgment call, not a rebase |

4. **Confirm before touching anything.** List each PR, its parent, and the target it will be
   rebased onto. This force-pushes; a batch of them force-pushes repeatedly.
5. **Restack**, in a throwaway worktree so the main checkout is never involved:

   ```bash
   git fetch origin
   git worktree add .worktrees/restack-<pr> <child branch>
   cd .worktrees/restack-<pr>
   git rebase --onto origin/<target> <parent_head> <child branch>
   ```

   `--onto` with the recorded sha is what makes this work regardless of the parent's merge
   mode — see `work-issue/restack-recipe.test.sh`, which proves the naive form conflicts.
6. **On conflict: stop.** `git rebase --abort`, keep the worktree, print its absolute path,
   and move to the next PR. Never resolve a restack conflict unattended — a conflict here is
   the semantic-collision case `/pr-triage` warns about, and a plausible-looking resolution
   can merge cleanly and still be wrong.
7. **Verify before pushing.** `git log --oneline origin/<target>..<child branch>` must contain
   only the child's own commits. If any of the parent's are still there, something is wrong
   with the marker or the target — report it and push nothing.
8. **Push:** `git push --force-with-lease`. Never bare `--force`: the lease is what makes this
   refuse to clobber a commit someone pushed to the child branch since.
9. **Refresh the marker** with `gh pr edit <pr> --body <updated>`: set `parent_head` to the
   sha just rebased onto, and — if the parent merged — set `parent_branch` to the base branch
   and drop `parent_pr`, since there is no longer a parent PR to wait for. A marker written
   once and never updated silently degrades the *next* restack into a plain rebase.
10. **Retarget the PR** if GitHub hasn't: `gh pr edit <pr> --base <target>`. GitHub
    auto-retargets a child when its parent merges, so this is usually a no-op — do it anyway
    rather than relying on it, and report when it was actually needed.
11. **Tear the worktree down** — `git worktree remove .worktrees/restack-<pr>` — unless step 6
    kept it.

End with a table: PR, parent, what happened (restacked / up to date / conflicted / parent
closed), and the new base. A conflicted entry names its kept worktree path.
```

- [ ] **Step 4: Add the rules**

Append to Rules:

```markdown
* Never restack without confirming first. It force-pushes, and on a batch it force-pushes
  several branches in a row.
* Never resolve a restack conflict automatically. Keep the worktree, report the path, move on.
* Never push a restack whose verification step still shows the parent's commits.
* Never restack a child whose parent PR was closed unmerged. Report it; the call is the
  user's.
```

- [ ] **Step 5: Add to Usage**

```markdown
/work-issue restack              # every stacked PR whose parent merged or moved
/work-issue restack 71 74        # only these
```

- [ ] **Step 6: Update the "Next in the pipeline" section**

Add a case to the existing list:

```markdown
* **A batch that created any `STACK` units** — say that the stacked PRs must merge in chain
  order, and that `/work-issue restack` is the step between merging a parent and merging its
  child.
```

- [ ] **Step 7: Run the assertions to verify they pass**

```bash
cd /Users/pete/projects/skills
grep -q '/work-issue restack' work-issue/SKILL.md && echo PASS || echo FAIL
grep -q 'The `restack` subcommand' work-issue/SKILL.md && echo PASS || echo FAIL
grep -q 'force-with-lease' work-issue/SKILL.md && echo PASS || echo FAIL
grep -q 'Refresh the marker' work-issue/SKILL.md && echo PASS || echo FAIL
./work-issue/restack-recipe.test.sh >/dev/null && echo "recipe still verified"
```

Expected: `PASS` ×4 and `recipe still verified`.

- [ ] **Step 8: Commit**

```bash
git add work-issue/SKILL.md
git commit -m "feat(work-issue): add restack subcommand for stacked PRs"
```

---

### Task 5: `/pr-triage` — stacks constrain the merge order

**Files:**
- Modify: `pr-triage/SKILL.md` — Phase 3 (line 71, the blast-radius computation and its tiebreakers), Phase 5 deliverable (line 111, the frontmatter schema and the merge table), and the "Next in the pipeline" variants (~line 191)

**Interfaces:**
- Consumes: the `work-issue-stack` marker (`parent_pr`) from Task 3, and `/work-issue restack` from Task 4.
- Produces: `stack:` entries in `PR_TRIAGE.md`'s frontmatter `prs[]` — `parent_pr` and `blocked: true|false`.

- [ ] **Step 1: Write the failing assertion**

```bash
cd /Users/pete/projects/skills
grep -q 'work-issue-stack' pr-triage/SKILL.md && echo PASS || echo FAIL
grep -q 'restack' pr-triage/SKILL.md && echo PASS || echo FAIL
```

Expected: `FAIL` twice.

- [ ] **Step 2: Add stack detection and the ordering constraint to Phase 3**

Insert into Phase 3, before the "Tiebreakers" list:

```markdown
### Stack constraint (hard, checked before ranking)

Read each PR's body for a `<!-- work-issue-stack` marker and record its `parent_pr`. Then:

1. **A child never ranks above its parent.** This is a hard constraint like `DEPENDS-ON` is in
   `/issue-triage` Phase 4, and it outranks blast radius *and* the critical-severity
   promotion below — a child promoted above its parent isn't a tradeoff, it's an unmergeable
   order. If a critical-severity child would be promoted, promote the whole chain, parent
   first, and say so.
2. **Exclude a parent from its child's blast radius.** A stacked child shares files with its
   parent by construction — that's why it was stacked. Counting that shared file penalizes
   the chain for its own structure and sorts every stack to the back of the queue. Count only
   the *other* open PRs it shares a file with.
3. **Mark children blocked.** A child cannot merge until its parent does, and needs
   `/work-issue restack` in between.

A marker whose `parent_pr` names a PR that is already merged is a child awaiting its restack,
not a stack member — treat it as unblocked, and say the restack is outstanding.
```

- [ ] **Step 3: Extend the snapshot frontmatter**

In the Phase 5 YAML block, add a stacked PR to the `prs` list:

```yaml
  - number: 14
    critical: false
    stack:
      parent_pr: 7
      blocked: true
    issues:
      - number: 61
        finding: F14
```

Document below the block: `stack` is absent on unstacked PRs — absent means unstacked, and
`blocked: false` means the parent has merged and the restack is what's outstanding.

- [ ] **Step 4: Show chains in the merge sequence**

Add to the Phase 5 report sections:

```markdown
* **Stack chains** — each chain as one row, in link order, with the restack between links so
  the sequence is executable as written:

  > merge #7 → `/work-issue restack` → merge #14 → `/work-issue restack` → merge #19

  A child listed without its restack step reads as mergeable straight after its parent, which
  it isn't.
```

- [ ] **Step 5: Add the next-step variant**

In the "Next in the pipeline" variants list:

```markdown
* **The top PR is a stacked child whose parent just merged** — `/work-issue restack` is the
  next step, not the merge. Merging before the restack is what produces a PR diff containing
  its parent's changes.
```

- [ ] **Step 6: Run the assertions to verify they pass**

```bash
cd /Users/pete/projects/skills
grep -q 'work-issue-stack' pr-triage/SKILL.md && echo PASS || echo FAIL
grep -q 'work-issue restack' pr-triage/SKILL.md && echo PASS || echo FAIL
grep -q 'never ranks above its parent' pr-triage/SKILL.md && echo PASS || echo FAIL
grep -q 'Exclude a parent from its child' pr-triage/SKILL.md && echo PASS || echo FAIL
```

Expected: `PASS` ×4.

- [ ] **Step 7: Commit**

```bash
git add pr-triage/SKILL.md
git commit -m "feat(pr-triage): treat PR stacks as a hard merge-order constraint"
```

---

### Task 6: `pipeline-status`, `WORKFLOW.md`, `/pipeline`

**Files:**
- Modify: `pipeline/pipeline-status` — stage 5/6 section (~line 160) and `next_step()` (~line 182)
- Modify: `WORKFLOW.md` — at-a-glance table (line ~19), Stage 4, Stage 6, Variants
- Modify: `pipeline/SKILL.md` — the override cases list (~line 98)

**Interfaces:**
- Consumes: `/work-issue restack` from Task 4 and the `stack:` frontmatter from Task 5.
- Produces: no new interface. This task is the discoverability layer.

- [ ] **Step 1: Write the failing assertion**

```bash
cd /Users/pete/projects/skills
grep -q 'restack' pipeline/pipeline-status && echo PASS || echo FAIL
grep -q 'restack' WORKFLOW.md && echo PASS || echo FAIL
bash -n pipeline/pipeline-status && echo "SYNTAX OK"
```

Expected: `FAIL`, `FAIL`, `SYNTAX OK`.

- [ ] **Step 2: Detect restack-needed PRs in `pipeline-status`**

The script already fetches open PRs into `$TMP/prs` and merged ones into `$TMP/merged`. After
the stage-5 block, add:

```bash
# ------------------------------------------------- stacked PRs awaiting a restack
# A child PR whose parent has merged needs `/work-issue restack` before it can be
# merged itself -- otherwise its diff still carries the parent's commits.
RESTACK_NEEDED=0
if [[ $HAS_GH -eq 1 ]]; then
  RESTACK_NEEDED=$(jq -r '
    [ .[] | select(.body != null)
          | select(.body | test("<!-- work-issue-stack")) ] | length
  ' < "$TMP/prs" 2>/dev/null || echo 0)
fi
```

Note: this counts stacked PRs, not specifically those needing a restack — deciding that needs
the parent's state, which is one `gh` call per stacked PR and too slow for a "zero tokens,
instant" dashboard. Counting stacked PRs and letting the recommendation mention the restack is
the right trade for this script; `/pipeline` (Step 5) does the precise version.

Make sure `body` is in the `gh pr list --json` field list where `$TMP/prs` is populated — add
it if absent.

- [ ] **Step 3: Add the recommendation to `next_step()`**

Insert immediately **before** the existing `PRS_OPEN -ge 1 && -n $PT_TOP` branch, since a
restack outranks a merge:

```bash
  if [[ ${RESTACK_NEEDED:-0} -gt 0 && $MERGED -gt 0 ]]; then
    echo "/work-issue restack  —  $RESTACK_NEEDED stacked PR(s) open; any whose parent merged must be restacked before merging"
    return
  fi
```

- [ ] **Step 4: Verify the script**

```bash
cd /Users/pete/projects/skills
bash -n pipeline/pipeline-status && echo "SYNTAX OK"
./pipeline/pipeline-status -b
./pipeline/pipeline-status | head -20
```

Expected: `SYNTAX OK`, and both runs produce output with no `jq` or unbound-variable errors.
This repo has no open PRs, so the new branch won't fire — confirming it doesn't *break* the
existing cascade is the check that matters here.

- [ ] **Step 5: Add the precise check to `/pipeline`**

In `pipeline/SKILL.md`'s override cases list, add:

```markdown
* **The script recommends merging but the top PR is a stacked child** — read its
  `work-issue-stack` marker and check the parent's state. If the parent has merged,
  `/work-issue restack` comes first. The script only counts stacked PRs; it can't afford the
  per-PR `gh` call to tell which ones are actually stale, so this is the check it delegates
  to you.
```

- [ ] **Step 6: Document the model in `WORKFLOW.md`**

Update the at-a-glance table's stage 4 row to mention stacked branches, then add to Stage 4:

```markdown
**Overlapping units are stacked, not parallelised.** `/issue-triage`'s Phase 4.5 marks a unit
`STACK` when it shares a file with one ranked ahead of it. That unit's branch is cut from its
parent's branch and its PR targets that branch, so the change is written against code that
already contains the parent's fix instead of against a base that predates it.

This costs no wall-clock: batch mode was already sequential, so the parent's branch always
existed by the time the child started — it was simply being ignored. Chains cap at 3; a 4th
overlapping unit is `HOLD`, reported for the next batch.
```

And rewrite Stage 6's loop:

```markdown
1. `/code-review 68` for the line-level pass, if the PR hasn't had one.
2. Merge it on GitHub. `Fixes #<n>` in the body closes the issue(s) automatically.
3. **`/work-issue restack`** if anything was stacked on it. A child branch still carries its
   parent's commits until this runs; merging one before restacking produces a PR whose diff
   includes changes that already landed.
4. **Re-run `/pr-triage`** — repeat-run mode re-ranks what's left against the new base.
5. `git branch -d PR68-Fix-I60-F3-rust-ps-path` when the PR is merged.
```

Add to Variants:

```markdown
**A chain you no longer want stacked.** Restack the child onto the base branch directly
(`/work-issue restack` does this once the parent merges) or, to break the chain early,
`git rebase --onto origin/main <parent_head> <child>` by hand and retarget the PR. The chain
is a convenience, not a commitment.
```

- [ ] **Step 7: Run the assertions to verify they pass**

```bash
cd /Users/pete/projects/skills
grep -q 'restack' pipeline/pipeline-status && echo PASS || echo FAIL
grep -q 'work-issue restack' WORKFLOW.md && echo PASS || echo FAIL
grep -q 'Phase 4.5' WORKFLOW.md && echo PASS || echo FAIL
grep -q 'stacked child' pipeline/SKILL.md && echo PASS || echo FAIL
bash -n pipeline/pipeline-status && echo "SYNTAX OK"
./pipeline/pipeline-status -b
```

Expected: `PASS` ×4, `SYNTAX OK`, and a sensible next-step line.

- [ ] **Step 8: Final cross-reference check**

Every skill that names another must still be accurate (`AGENTS.md`):

```bash
cd /Users/pete/projects/skills
grep -rn 'STACK\|HOLD\|restack' --include='SKILL.md' --include='*.md' . | grep -v docs/ | sort
```

Read the output. Confirm: `/issue-triage` defines `STACK`/`HOLD`, `/work-issue` consumes them
and defines `restack`, `/pr-triage` and `pipeline` consume `restack`, and nothing references a
disposition or subcommand that doesn't exist.

- [ ] **Step 9: Commit**

```bash
git add pipeline/pipeline-status pipeline/SKILL.md WORKFLOW.md
git commit -m "docs(workflow): document PR stacking and the restack step in stage 6"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| `STACK` disposition, Phase 4.5, transitivity | 2 |
| Depth cap 3 → `HOLD` | 2 |
| Snapshot `stack:` block | 2 |
| Branch from parent's remote branch | 3 |
| `gh pr create --base` | 3 |
| `work-issue-stack` marker | 3 |
| Resolution comment names the stack | 3 |
| Batch plan shows chains | 3 |
| `restack` subcommand, all 4 parent states | 4 |
| Conflict → keep worktree, never resolve | 4 |
| Verify-before-push | 4 |
| `--force-with-lease` | 3, 4 |
| Marker refresh (spec Risks: "step 7 is not optional") | 4 |
| Base retarget fallback | 4 |
| Topological constraint | 5 |
| Blast-radius correction | 5 |
| Chain display with restack between links | 5 |
| `pipeline-status` detection | 6 |
| `WORKFLOW.md` stages 4 and 6 | 6 |
| Evidence (merge-mode behavior) | 1 |

No gaps. The spec's two Open Questions (auto-working `HOLD` units; `/pr-triage` running the restack) are deliberately unimplemented — both were resolved as "no" for v1.

**Placeholder scan:** No `TBD`, no "add error handling", no "similar to Task N". Every code and Markdown block is literal content to insert.

**Type consistency:** The marker keys are `parent_pr` / `parent_branch` / `parent_head` in Tasks 3, 4, and 5. The snapshot keys are `parent_order` / `parent_issue` / `depth` in `/issue-triage` (Task 2) and `parent_pr` / `blocked` in `/pr-triage` (Task 5) — deliberately different, because one indexes units within a triage snapshot and the other indexes live PRs. Task 2 and Task 5 each say so.

**One risk the plan can't remove:** Tasks 2–6 have no executable test. Their `grep` assertions prove the text landed, not that Claude follows it correctly. The first real `/work-issue all` run on a repo with two overlapping issues is the actual integration test, and it should be done on a throwaway repo before a real one.
