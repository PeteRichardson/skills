---
name: work-issue
description: Take a GitHub issue through to an open PR on its own worktree, using a branch name that carries the issue number and review finding ID (Fix-I60-F3-rust-ps-path). Posts a resolution comment on each issue explaining what the PR proposes for that issue specifically. Use when the user types /work-issue, says "fix issue 60 on a worktree, push the branch and open a PR", "work issue 60", "start work on issue 60", or asks to do that for every open issue not already addressed by a PR. Owns branch/worktree naming, push, PR creation, the per-issue resolution comment, and worktree teardown.
---

# Work Issue

Take one GitHub issue from "not started" to "PR open", on a dedicated worktree, with a branch name that makes the issue number and review finding ID readable at a glance.

Everything from here through the `---` divider is the protocol Claude executes. The section after the divider is documentation for humans installing or maintaining this skill.

---

## The naming scheme

Three identifier spaces get conflated constantly — issue number, `/project-review` finding ID, and PR number. The first two go in the branch name, each with a distinct prefix:

```
Fix-I60-F3-rust-ps-path
    └─┘ └┘ └───────────┘
   issue finding  slug from the issue title
```

- `Fix` — a literal marker, not a claim about issue type. Present on every branch.
- `I<n>` — the GitHub issue number. Always present; this skill does not run without one.
- `F<n>` — the finding ID from a `/project-review` or `/code-review` report, if the issue records one. Omitted entirely when it doesn't — `Fix-I63-rust-shell-quote`, no empty segment.
- Slug — 2–4 words from the issue title, lowercased, `[a-z0-9-]` only, ≤ 32 chars.

**Grouped units** — when `/issue-triage` returns a `GROUP` disposition, several issues share one branch and one PR. Every issue number appears, ascending, each with its own `I` prefix; finding IDs follow in the same order, and are omitted entirely if none of the issues has one:

```
Fix-I11-I15-sparql-retry-set
    └──┘└──┘ └─────────────┘
   both issue numbers   slug describing the combined change
```

The slug describes what the *unit* does, not any one issue's title — a combined branch has no single title to derive from. The PR body carries one `Fixes #<n>` line per issue so GitHub closes all of them on merge. Everything else about the scheme is unchanged.

**One name, everywhere.** The local branch, the remote branch, the worktree directory and the PR's head branch all carry the same name, from Phase 3 to the merge. Never rename the local branch — not to add the PR number, not for any other reason. A local name that differs from its upstream's breaks the plain `git push`, and a push that names the local branch creates a new remote branch that no PR uses: CI never runs, and the stray branch outlives the merge. See "Why the PR number is not in the branch name" below.

The PR number is not in the name because it does not exist until after the push. `gh pr view --json number,url` from the branch, or `gh pr list --head <branch>`, gives it.

## The resolution comment

A linked PR tells a reader *where* the work went, not *what happened to their issue*. For a grouped unit that gap is the whole problem: several issues share one PR, so every reporter but one is handed a diff that is mostly not about their bug. Phase 5 posts one comment per issue to close that gap, written so it can be read during a bug scrub without opening the PR.

**Everything in it is a proposal.** At the moment it's written the PR is open and unreviewed — it can be rejected, rewritten, or sent back for a rearchitecture that invalidates the note entirely. The format exists to make that unmissable.

```markdown
**Proposed fix — PR #22, open and unmerged**

> [!NOTE]
> Nothing has changed on `main` yet. If #22 is revised or rejected, everything below
> the diagnosis changes with it. #22 is the source of truth.

### Diagnosis
`sparql_query()` retried every 5xx on a fixed 2s backoff and ignored `Retry-After`, so a
throttled endpoint got hammered and the query still failed.

### What #22 proposes (this issue's part)
Parse and honour `Retry-After` when present; the fixed backoff becomes the fallback only.
- `src/sparql/client.rs` — `retry_policy()`, `sparql_query()`

### If it merges, you'll notice
Queries against throttled endpoints wait the server's requested interval instead of failing
after 3 fast retries.

### Deliberately not covered
Connection-level timeouts (still fixed at 30s) — that's #19.

<!-- work-issue-resolution
status: proposed
pr: 22
issue: 11
grouped_with: 15
finding: F7
-->
```

Composing it:

* **Diagnosis is past tense and durable.** It stays true whether or not the PR survives review, which is why it sits above the callout's blast line — everything below is contingent and phrased that way ("What #22 proposes", "If it merges"). Keep that split; hedging the diagnosis too makes the whole comment read as guesswork.
* **State the root cause you actually found**, not a paraphrase of the issue title. When it turns out to differ from what the reporter described, say so plainly — that's the single most useful sentence in the comment for them.
* **Cite the files and symbols you actually touched.** No invented paths, no guessed line numbers.
* **Never claim tests pass without having run them** in the worktree.
* **Omit `Deliberately not covered` entirely** when there were no real scope decisions. Never write "None" — same convention as `/pr-triage`'s severity-overrides section.
* **Grouped units get one comment per issue, and they must differ.** Every section describes only that issue's slice; pasting one comment across the unit recreates the exact problem this solves. If a grouped change genuinely can't be decomposed per issue, say that plainly under `What #22 proposes` rather than inventing a split.
* **For a `STACK` unit**, the comment must say the PR is stacked on #`<parent_pr>` and cannot
  merge until that one does. A reporter reading the issue would otherwise reasonably expect
  an open PR to be mergeable, and the GitHub UI shows the unfamiliar base branch without
  explaining it.

Marker fields:

* `status:` is always `proposed`. Nothing updates it today; it's there so a future merge-time pass can flip it without re-editing every comment ever written.
* `pr:` and `issue:` are this comment's PR and the one issue it describes.
* `grouped_with:` lists the *other* issue numbers in the unit. Omitted entirely for a single-issue unit.
* `finding:` carries the `F<n>` from Phase 1. Omitted when absent, and **never inferred** — the same rule the branch name follows.

The key is `finding:`, deliberately not `finding_id:`. `/make-issues`' fingerprint marker owns `finding_id:`, and three protocols scan issue comments for it (this skill's Phase 1, `/issue-triage` Phase 1, `/pr-triage` Phase 3). All three anchor on the marker name `project-review-finding`, so using a different key name here means even a careless grep can't cross the two markers.

## Phase 0: Resolve the invocation

* **`/work-issue <n>`** — one issue. Proceed to Phase 1.
* **`/work-issue all`**, or any "for each open issue that isn't already addressed by a PR" phrasing — batch mode, see Batch mode below.
* **`/work-issue <n> <m> ...`** — several issue numbers. Enter batch mode scoped to exactly those, using the `issue-triage` protocol per step 3 below. This is batch mode over a hand-picked set, not a series of independent single runs — the numbers may turn out to belong in one grouped PR.
* **`/work-issue <description>`** with no issue number — stop. The branch format requires `I<n>`, and an issue is the durable record this whole flow hangs off. Offer to file the issue first (`gh issue create`, or `/make-issues` if it came from a review report), then re-invoke with the number.
* `restack` — `/work-issue restack` (every open stacked PR whose parent has moved or merged)
  or `/work-issue restack 71 74` (scoped to those PRs). Skips Phases 1–6 entirely and runs
  the restack protocol below. It works no issues and opens no PRs.

## Phase 1: Resolve the issue and compute both names

1. `gh issue view <n> --json number,title,state,body,comments,labels,url`. Stop if the issue is closed — say so rather than working it anyway.
2. **Deferred?** — stop if any label in `DEFERRAL_LABELS` is present: `backlog`, `icebox`, `someday`, `someday-maybe`, `future`, `deferred`, `on hold`, `wontfix`, or any `priority/backlog`-style namespaced equivalent. These mark work that is deliberately remembered but not scheduled; opening a PR against one makes a prioritization decision the label records as unmade. Report which label fired and offer to proceed anyway — a user who types the number themselves may well mean it, but the override must be theirs, not an assumption.
3. **Finding ID** — scan the issue body and every comment for `/make-issues`' fingerprint marker (`<!-- project-review-finding ... -->`) and read its `finding_id:` line. Absent for hand-filed issues, `backfill`-retrofitted issues, and issues filed before the marker carried the field. Absent is normal: drop the `F<n>` segment. **Never infer an ID** by matching the issue against a review report — a report regenerated since filing may have renumbered.
4. **Slug** — from the issue title: lowercase, strip punctuation and filler words (a, the, in, on, when, should), keep the 2–4 most specific words, join with `-`, truncate to 32 chars at a word boundary.
5. Compose the branch name. Show it to the user before creating anything.

## Phase 2: Is this issue already addressed?

Run all three checks — each catches work the others miss. Any hit means **stop and report**, don't create a second worktree for the same issue:

1. **Open PR closing it** — `gh pr list --state open --json number,title,headRefName,closingIssuesReferences` and look for `<n>` in any `closingIssuesReferences`.
2. **PR head ref naming it** — from the same result, any `headRefName` matching `(^|-)I?<n>(-|$)`. Catches PRs that reference the issue in prose but never linked it.
3. **Local or remote branch naming it** — `git branch -a` with the same pattern. Catches in-flight work that has no PR yet, and abandoned half-finished branches. This is the cheapest durable signal: a branch persists regardless of PR state or whether any session is still running.

In batch mode these three checks *are* the "not already addressed by a PR" filter — run them per issue, and report each skip with which check fired. They compose with Phase 1's deferral check: a batch run skips deferred issues *and* already-addressed ones, and reports the two groups separately, since one is a scheduling decision and the other is a duplicate-work guard.

## Phase 3: Create the worktree

Run from the main repo, not from another worktree:

1. `git fetch origin` and confirm the base branch (default branch unless the user says otherwise).
2. Ensure `.worktrees/` is ignored — **without modifying any tracked file**, the same
   convention `/pr-triage` and `/issue-triage` use for `.claude/tmp/`:

   ```bash
   git check-ignore -q .worktrees/ || cat >> .git/info/exclude <<'EOF'

   # Added by the Claude Code /work-issue skill.
   # Worktrees for in-flight issue fixes. Excluded here rather than in .gitignore
   # so it never creates a commit diff. `git check-ignore -v <path>` will name
   # this file as the source. Delete this block to un-ignore.
   .worktrees/
   EOF
   ```

   Probe with `git check-ignore`, never by grepping `.gitignore` — the latter misses a
   global excludes entry and a `.git/info/exclude` entry, then appends a redundant line to
   a tracked file. The probe is a silent no-op for anyone with `**/.worktrees/` in their
   global excludes (`git config --global core.excludesFile`), which is the preferred setup,
   and equally a no-op in a repo that already carries the line in `.gitignore`.

   **When the fallback actually fires, say so once in the run output** — name the file
   written and mention that `git check-ignore -v .worktrees/` explains the exclusion later.
3. Create the worktree, branched from the base — or, for a `STACK` unit, from its parent:

   ```bash
   # WORK / GROUP unit — unchanged
   git worktree add .worktrees/<branch> -b <branch> origin/<base>

   # STACK unit — branch from the parent's REMOTE branch
   git worktree add .worktrees/<branch> -b <branch> origin/<parent branch>
   ```

   Use the parent's **remote** branch (`origin/Fix-I60-F3-…`), never its local one. The local
   copy can be behind the remote or already deleted; the remote branch is what the parent's PR
   actually points at.

   Record `git rev-parse origin/<parent branch>` now — Phase 5 writes it into the PR
   body, and it is the value `/work-issue restack` needs later. Capture it before doing any
   work, so it names the commit this branch was actually cut from.
4. `cd` into it. **Every** subsequent edit, build, test, and git command runs inside this worktree. Never edit files in the main checkout or a sibling worktree.

The worktree directory takes the branch name.

## Phase 4: Do the work

This skill owns the lifecycle, not the engineering. Use the normal skills inside the worktree: `superpowers:test-driven-development` for the change itself, `/run-tests` to verify, `/pre-commit` before committing, `/commit-message` for the message. Include `Fixes #<n>` in the final commit or the PR body (Phase 5 relies on it for linking).

If the issue needs design decisions the issue text doesn't settle, ask before implementing. A wrong fix delivered fast is worse than one round of questions.

## Phase 5: Push and open the PR

1. `git push -u origin <branch>` — the remote branch gets the same name as the local one.
2. `gh pr create --title "<title>" --body "<body>"`. The body must contain `Fixes #<n>` so
   GitHub links the issue, and should name the finding ID (`Addresses F3 from the project
   review`) when there is one.

   **For a `STACK` unit**, run `gh pr create --base <parent branch> --title "<title>"
   --body "<body>"` — the added `--base` is what points the PR at its parent instead of the
   base branch — and include the stack marker in the body:

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
3. Capture the PR number from the command's output. If PR creation fails, stop here — do not tear down, do not comment. The worktree stays exactly as it is and the failure gets reported.
4. **Post the resolution comment** — one per issue in the unit, composed per "The resolution comment" above.
   1. **Check for an existing one first.** From the Phase 1 `gh issue view` result (or a fresh one), scan every comment for a `<!-- work-issue-resolution` marker naming this same `pr:`. If one exists, skip that issue and report it — never post a second comment for the same PR.
   2. `gh issue comment <n> --body "<comment>"`.
   3. **A comment failure never aborts the run.** The PR is already open and is the durable artifact; a missing comment is cosmetic by comparison. Report which issues didn't get one and continue to Phase 6.

   No confirmation prompt for this step. It is strictly less consequential than the `gh pr create` that immediately precedes it, and batch mode already confirms the plan up front for runs of more than ~3 units.

## Phase 6: Tear down

1. `cd` back to the main repo root.
2. **Teardown preconditions** — check all three, and abort teardown if any fails:
   - `git status --porcelain` in the worktree is empty
   - `git log @{u}..` is empty (nothing unpushed)
   - the PR was created successfully in Phase 5

   If any check fails, **keep the worktree**, print its absolute path and which check failed, and say the tree is still live. Never `git worktree remove --force`.
3. `git worktree remove .worktrees/<branch>`.
4. **Keep the local branch**, under its one name. It is what you come back to if the PR needs more work.
5. Report: issue number and title, PR number and URL, the branch name, whether the resolution comment was posted for each issue (and why not, if not), and whether the worktree was removed or kept (and why).

## Coming back to a PR later

The worktree is gone by design — recreate one only when you actually need to iterate or review locally:

```bash
git worktree add .worktrees/<branch> <branch>   # local branch still exists
gh pr checkout 68                                # it doesn't (fresh clone, other machine)
```

`gh pr checkout` names the local branch after the PR's head branch, which is the same one name, so nothing differs. A plain `git push` from that worktree goes to the PR and starts CI.

**When the remote branch changed without you** — GitHub's **Update branch** button, `gh pr update-branch`, or a restack from another machine rewrites the remote branch. Your local copy then shows as both ahead of and behind its upstream: the same change twice, with different commit IDs. Run `git pull --rebase` before you change anything, so you build on the remote version.

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

This is the manual version of the steps below — reach for `/work-issue restack` instead when
you don't need to do it by hand.

## The `restack` subcommand

Replays a stacked child's own commits onto its new base after its parent moved. This is the
only part of this skill that force-pushes, which is why it's an explicit command rather than
something a batch run does on its own.

1. **Find the candidates.** `gh pr list --state open --json number,body,headRefName,baseRefName`
   and keep those whose body contains a `<!-- work-issue-stack` marker. Skip any marker that
   carries `resolved: true` — that PR's stack was already unwound and there is nothing left to
   restack. Scoped invocation filters this list; a named PR with no marker is reported as such,
   not guessed at.
2. **Read the marker** for `parent_pr`, `parent_branch`, `parent_head`. A marker missing any
   of the three is corrupt — report it and skip that PR. `resolved: true` is an optional fourth
   key; its absence is normal and never counts as corruption. Never reconstruct a `parent_head`
   from the branch's current position; that's the one value that can't be re-derived once the
   parent has moved.
3. **Classify the parent** with `gh pr view <parent_pr> --json state,headRefOid,baseRefName`:

   | Parent state | Action |
   |---|---|
   | Merged | Restack onto the parent's own base branch |
   | Open, `headRefOid` still equals `parent_head` | Nothing to do — report "up to date" and skip |
   | Open, `headRefOid` has moved | Restack onto the parent's branch (the marker's `parent_branch`) |
   | Closed unmerged | **Report and stop for this PR.** Its base is gone, and whether the child still makes sense is a judgment call, not a rebase |

4. **Confirm before touching anything, and wait for an explicit yes.** List each PR, its
   parent, and the target it will be rebased onto, then stop and wait — printing the plan is
   not the confirmation. This force-pushes; a batch of them force-pushes repeatedly.
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
   and add a fourth line, `resolved: true`, since there is no longer a parent PR to wait for.
   **`parent_pr` is never removed** — step 2's corruption check requires all three original
   keys, and a marker missing one would be misreported as corrupt on every later scan. A
   marker written once and never updated silently degrades the *next* restack into a plain
   rebase.

   ```html
   <!-- work-issue-stack
   parent_pr: 68
   parent_branch: main
   parent_head: 9f8e7d6c1b2a3d4e5f60718293a4b5c6d7e8f901
   resolved: true
   -->
   ```
10. **Retarget the PR** if GitHub hasn't: `gh pr edit <pr> --base <target>`. GitHub
    auto-retargets a child when its parent merges, so this is usually a no-op — do it anyway
    rather than relying on it, and report when it was actually needed.
11. **Tear the worktree down** — `git worktree remove .worktrees/restack-<pr>` — unless step 6
    kept it.

End with a table: PR, parent, what happened (restacked / up to date / conflicted / parent
closed), and the new base. A conflicted entry names its kept worktree path.

## Batch mode

For "every open issue not already addressed by a PR":

1. Get the candidate set, excluding deferred issues:

   ```bash
   gh issue list --state open --limit 200 --json number,title,labels \
     --jq '.[] | select(.labels | map(.name) | any(. == "backlog" or . == "icebox" or . == "someday" or . == "future" or . == "deferred" or . == "on hold" or . == "wontfix") | not)'
   ```

   Filter client-side like this rather than with `--search '-label:backlog'`. Both work, but GitHub's search index is eventually consistent — an issue labelled seconds ago can still come back from `--search`, which is exactly the race a loop that labels and re-queries will hit. `--jq` reads the issues API directly and is immediately correct. Note also that `--label` is include-only; there is no `--exclude-label` flag.

   Report the excluded issues by number and title. A deferred issue that silently never appears reads as "nothing left to do" when the truth is "you decided not to do these" — and a mistakenly-labelled issue would otherwise stay invisible forever.
2. Run Phase 2's three checks per issue; report the skips as a list with the reason each fired.
3. **Order the queue using the `issue-triage` protocol.** Read `~/.claude/skills/issue-triage/SKILL.md` and execute its Phases 2–5, including Phase 4.5, against the candidate set from steps 1–2, skipping its Phase 1 (this batch already did that filtering). Do **not** try to invoke it through the Skill tool — `issue-triage` sets `disable-model-invocation: true`, so it is reachable only by the user typing `/issue-triage` or by reading its protocol file directly, which is what this step does.

   Run it fresh every time — never read a previous `.claude/tmp/issue-triage/` snapshot, which any merge, close, or label change since invalidates. Its dispositions bind this run:

   | Disposition | What batch mode does |
   |---|---|
   | `WORK n` | Work it alone, at position n. |
   | `GROUP` | Work all its issues on **one** worktree, one branch, one PR — see the grouped-unit naming above. Never split a group into consecutive single runs; the second branch would be cut from `main` and conflict with the first by construction. |
   | `STACK` | Work it on a branch cut from its parent's remote branch, PR based on that branch. The parent is always earlier in the same run, so its branch already exists — batch mode is sequential. |
   | `HOLD` | Report as held for the next batch, naming the chain it overlaps, and skip. Not a deferral: nothing is wrong with the issue, it just exceeds the depth cap. |
   | `NEEDS-DECISION` | **Halt and ask.** Present the question and the options the issue names. Do not implement, do not guess, do not skip silently. |
   | `DEFER` | Report as a deferral proposal and skip. Never apply the label. |
   | `CLOSE-MOOT` | Report the proposal with its evidence and skip. Never close the issue. |

   If `~/.claude/skills/issue-triage/SKILL.md` isn't present (it's an optional companion, not a hard dependency), fall back to working the candidate set in issue-number order and say so explicitly — an unordered batch is a degraded run, not the normal path.
4. Run Phases 1 and 3–6 on each work unit **sequentially**, in the triage order — one worktree at a time, fully torn down before the next is created. Sequential is deliberate: parallel worktrees on overlapping code produce conflicting PRs, which is the problem `/pr-triage` then has to clean up.
5. A failure on one unit doesn't abort the run. Record it, move to the next, and end with a table: issues, PR (or the failure reason), branch name, comment posted y/n, worktree removed y/n — plus the `NEEDS-DECISION`, `DEFER`, and `CLOSE-MOOT` sets, which are the run's real output for the user to act on.
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

## Next in the pipeline

This skill is stage 4 of the review → issue → PR → merge pipeline (`~/.claude/skills/WORKFLOW.md`). End the run by printing the next step as the last line, after the Phase 6 report (or the batch summary table):

* **Batch run, or any run leaving 2+ PRs open** — the merge order:

  > Next: `/pr-triage` to rank the open PRs by blast radius and get a merge order.
* **Single run leaving one PR open** — no triage needed for a queue of one; say the PR is ready for review and merge.
* **A `NEEDS-DECISION` halt** — the decision is the next step, not `/pr-triage`. Name the issue and repeat the question.
* **Any unit failed, or a worktree was kept** — lead with that and its absolute path. A kept worktree is live state; it outranks the next command.
* **A batch that created any `STACK` units** — say that the stacked PRs must merge in chain
  order, and that `/work-issue restack` is the step between merging a parent and merging its
  child.

## Rules

* Never work in the main checkout — every change happens inside the issue's worktree.
* Never delete a worktree with uncommitted or unpushed work, and never use `git worktree remove --force`. A kept worktree with a printed reason is always the correct fallback.
* Never rename a branch, local or remote, and never try to repoint an open PR's head. The local branch, the remote branch, the worktree and the PR keep the one name from Phase 3 to the merge. Never push with a local name that differs from the remote's.
* Never invent a finding ID or an issue number. An absent `F<n>` segment is correct output; a wrong one is worse than none. The same holds inside the resolution comment — no invented finding IDs, no invented file paths.
* Never post more than one resolution comment per issue per PR. Check for the marker before posting; a duplicated note on a re-run is noise on an issue someone else is reading.
* Never paste the same resolution comment across a grouped unit. One PR closing three issues means three different comments, each about its own issue.
* Comments only — never edit an issue's body or title, even one this skill's PR will close. Same boundary `/make-issues` holds.
* Never write the resolution comment as though the fix has landed. It is written before review; `**Proposed fix**`, the `> [!NOTE]` callout, and the proposal tense are not decoration.
* One worktree per issue. If Phase 2 says the issue is already covered, stop — don't create a parallel attempt.
* Never implement a `NEEDS-DECISION` issue by choosing the policy yourself. The whole point of the disposition is that the choice reaches the user before code exists.
* Never act on `/issue-triage`'s `CLOSE-MOOT` or `DEFER` proposals — report them. Closing an issue or deferring one is a mutation on a judgment call; triage is advisory and so is this skill's handling of it.
* Never work a deferred issue in batch mode, and never strip a deferral label to make an issue eligible. Deciding something is worth doing now is the user's call; the label is that decision already recorded. A single explicit `/work-issue <n>` may override it, but only after asking.
* **`status: needs-decision` is not a deferral label.** `/issue-triage label` applies it for visibility in the GitHub UI; it is not in `DEFERRAL_LABELS` and must never be added to it. Never skip an issue for carrying it and never remove it. Batch mode derives the `NEEDS-DECISION` disposition fresh from the triage protocol on every run, which is what makes the halt correct — a label left behind after the decision was answered would otherwise block the issue silently and permanently. Read the disposition, not the label.
* Stop and report rather than guess when `gh` fails (auth, rate limit) or the issue number doesn't exist. No silent retries.
* Never cut a `STACK` unit's branch from the base. The whole point is that it sees its
  parent's changes while the code is being written; branching from the base silently produces
  exactly the conflict this disposition exists to prevent.
* Never write a `work-issue-stack` marker with a guessed `parent_head`. If the sha wasn't
  captured in Phase 3, re-derive it with `git rev-parse origin/<parent branch>` before the
  branch has any commits of its own — never after.
* Never stack onto a parent whose PR failed to open. No parent PR, no child.
* Never restack without confirming first and waiting for an explicit yes. It force-pushes,
  and on a batch it force-pushes several branches in a row.
* Never resolve a restack conflict automatically. Keep the worktree, report the path, move on.
* Never push a restack whose verification step still shows the parent's commits.
* Never restack a child whose parent PR was closed unmerged. Report it; the call is the
  user's.
* Never drop a key from a stack marker when refreshing it. A key that disappears turns a valid
  marker into one the corruption check in step 2 rejects.

---

# Project documentation

Everything below is for humans installing, using, or contributing to this skill. It is not part of the protocol.

This skill is deliberately repo-agnostic — plain `git worktree` and `gh`, no project-specific session-coordination tooling. If a given repo needs extra steps (submodule pointers, a coordination registry, mandated branch prefixes for certain change types), those belong in that repo's `CLAUDE.md`, not here.

## Usage

```
/work-issue 60
/work-issue all
/work-issue restack              # every stacked PR whose parent merged or moved
/work-issue restack 71 74        # only these
```

Or just say it: "fix issue 60 on a worktree, push the branch and open a PR". The skill is model-invocable precisely so that phrasing works — the whole point is that the naming convention applies whether or not you remember to type the slash command.

## Why the PR number is not in the branch name

An earlier version of this skill renamed the local branch after the PR opened, from `Fix-I60-F3-rust-ps-path` to `PR68-Fix-I60-F3-rust-ps-path`. The remote branch could not get the number too: `gh pr create` assigns it only after the push, and GitHub cannot change an open PR's head branch. So each unit had two names, one on each side.

In use, the two names caused more work than the number saved:

- `git push` with `push.default=simple` refuses when the local name differs from its upstream's. The fix, `git push origin HEAD:<remote name>`, is easy to forget.
- `git push origin PR68-…` creates a *new* remote branch. No PR uses it, so CI never runs, and the stray branch stays after the PR merges.
- When GitHub rewrites a PR branch (the **Update branch** button, `gh pr update-branch`), the local copy falls behind. With two names it is hard to see that the local and remote branches are the same work.

The PR number is one command away: `gh pr view --json number,url` on the branch, or `gh pr list --head <branch>`. The issue number and finding ID stay in the name, because they are known before the branch exists and never change.

## Why the issue gets a comment when the PR already links to it

GitHub's link tells you where the work went. It doesn't tell you what happened to your bug, and during a scrub that difference costs a click and a diff read per issue.

The case that forces it is the grouped PR. When one PR closes three issues, the link is the *same* link for all three, and two of the three reporters open it to find a diff that's mostly about something else. A per-issue comment is the only place the answer to "what happened to mine, specifically" can live.

The comment is written at PR-creation time because that's the last moment this skill controls — merging is manual and happens later, possibly after review has changed the fix. That's why the whole format is built around being a proposal rather than a report: the header says open and unmerged, a `> [!NOTE]` callout renders as a coloured box saying nothing has changed on `main`, and every section below the diagnosis is in proposal tense.

The diagnosis is the exception, deliberately. What was actually wrong stays true whether the PR merges, gets rewritten, or is closed unmerged — so it's the one part written as fact, and it's the part that's still worth reading a year later if the PR was rejected and the bug refiled.

## Why the worktree gets torn down

Once the PR is open, the local tree has served its purpose — review happens on the web or in a freshly checked-out worktree, and a directory left behind "just in case" accumulates into exactly the pile this naming scheme was invented to navigate. Teardown is conditional, not eager: uncommitted work, unpushed commits, or a failed PR creation all keep the tree alive with a printed reason.

## How this fits with the other skills

`/project-review` and `/code-review` find the work; `/make-issues` files it as GitHub issues and records the `finding_id` this skill reads back out; `/work-issue` turns one issue into a PR; `/pr-triage` orders the resulting PR queue for merging. The finding ID is the thread running through all four — it's why `/make-issues` records `finding_id` in its fingerprint marker even though it deliberately never *matches* on it.

## Limitations

- Requires an issue. There's no "quick fix with no issue" path, by design — the branch format has nowhere to put a missing `I<n>`.
- Batch mode is sequential. Parallel worktrees would be faster and would produce conflicting PRs on overlapping code.
- The finding ID is only as good as what `/make-issues` recorded at filing time. Issues predating that field, and hand-filed issues, get no `F<n>` segment ever — `/make-issues backfill` deliberately doesn't invent one.
- No cleanup of local branches after their PRs merge. Deleting them stays a manual step. PRs that are rebase- or squash-merged leave commits that are not ancestors of the base, so `git branch -d` refuses them; use `-D` once the PR shows as merged.
- The resolution comment describes the fix **as proposed**, and nothing updates it afterwards. A PR substantially rewritten in review leaves a comment that no longer matches what merged. The format is built to survive that honestly rather than to prevent it — the callout says the PR is the source of truth, and `status: proposed` in the marker is there so a future merge-time pass can flip these without re-editing the format. Nothing reads or updates that field today.
- A run that never reaches an open PR — a failure, or a worktree kept for uncommitted work — posts no comment at all. Those are reported in-session only, so an abandoned branch leaves its issue looking untouched on GitHub.
