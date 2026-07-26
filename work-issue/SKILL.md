---
name: work-issue
description: Take a GitHub issue through to an open PR on its own worktree, using a branch name that carries the PR number, issue number, and review finding ID (PR68-Fix-I60-F3-rust-ps-path). Use when the user types /work-issue, says "fix issue 60 on a worktree, push the branch and open a PR", "work issue 60", "start work on issue 60", or asks to do that for every open issue not already addressed by a PR. Owns branch/worktree naming, push, PR creation, and worktree teardown.
---

# Work Issue

Take one GitHub issue from "not started" to "PR open", on a dedicated worktree, with a branch name that makes the issue number, PR number, and review finding ID all readable at a glance.

Everything from here through the `---` divider is the protocol Claude executes. The section after the divider is documentation for humans installing or maintaining this skill.

---

## The naming scheme

Three identifier spaces get conflated constantly — PR number, issue number, and `/project-review` finding ID — so all three go in the branch name, each with a distinct prefix:

```
PR68-Fix-I60-F3-rust-ps-path
└──┘     └─┘ └┘ └───────────┘
 PR #   issue  finding   slug from the issue title
```

- `PR<n>` — added only once the PR exists (Phase 6). Absent before that.
- `Fix` — a literal marker, not a claim about issue type. Present on every branch.
- `I<n>` — the GitHub issue number. Always present; this skill does not run without one.
- `F<n>` — the finding ID from a `/project-review` or `/code-review` report, if the issue records one. Omitted entirely when it doesn't — `PR71-Fix-I63-rust-shell-quote`, no empty segment.
- Slug — 2–4 words from the issue title, lowercased, `[a-z0-9-]` only, ≤ 32 chars.

**Grouped units** — when `/issue-triage` returns a `GROUP` disposition, several issues share one branch and one PR. Every issue number appears, ascending, each with its own `I` prefix; finding IDs follow in the same order, and are omitted entirely if none of the issues has one:

```
PR22-Fix-I11-I15-sparql-retry-set
         └──┘└──┘ └─────────────┘
        both issue numbers   slug describing the combined change
```

The slug describes what the *unit* does, not any one issue's title — a combined branch has no single title to derive from. The PR body carries one `Fixes #<n>` line per issue so GitHub closes all of them on merge. Everything else about the scheme is unchanged.

Two names exist per unit:

| | Name | Lives on |
|---|---|---|
| **Working name** | `Fix-I60-F3-rust-ps-path` | the remote branch, permanently |
| **Final name** | `PR68-Fix-I60-F3-rust-ps-path` | the local branch only, after Phase 6 |

They differ on purpose and permanently. The PR number doesn't exist until the branch has been pushed and the PR opened, and GitHub will not repoint an open PR's head branch — so the remote keeps the working name forever. Never try to reconcile them.

## Phase 0: Resolve the invocation

* **`/work-issue <n>`** — one issue. Proceed to Phase 1.
* **`/work-issue all`**, or any "for each open issue that isn't already addressed by a PR" phrasing — batch mode, see Batch mode below.
* **`/work-issue <n> <m> ...`** — several issue numbers. Run `/issue-triage #<n> #<m> ...` scoped to exactly those, then execute the plan it returns. This is batch mode over a hand-picked set, not a series of independent single runs — the numbers may turn out to belong in one grouped PR.
* **`/work-issue <description>`** with no issue number — stop. The branch format requires `I<n>`, and an issue is the durable record this whole flow hangs off. Offer to file the issue first (`gh issue create`, or `/make-issues` if it came from a review report), then re-invoke with the number.

## Phase 1: Resolve the issue and compute both names

1. `gh issue view <n> --json number,title,state,body,comments,labels,url`. Stop if the issue is closed — say so rather than working it anyway.
2. **Deferred?** — stop if any label in `DEFERRAL_LABELS` is present: `backlog`, `icebox`, `someday`, `someday-maybe`, `future`, `deferred`, `on hold`, `wontfix`, or any `priority/backlog`-style namespaced equivalent. These mark work that is deliberately remembered but not scheduled; opening a PR against one makes a prioritization decision the label records as unmade. Report which label fired and offer to proceed anyway — a user who types the number themselves may well mean it, but the override must be theirs, not an assumption.
3. **Finding ID** — scan the issue body and every comment for `/make-issues`' fingerprint marker (`<!-- project-review-finding ... -->`) and read its `finding_id:` line. Absent for hand-filed issues, `backfill`-retrofitted issues, and issues filed before the marker carried the field. Absent is normal: drop the `F<n>` segment. **Never infer an ID** by matching the issue against a review report — a report regenerated since filing may have renumbered.
4. **Slug** — from the issue title: lowercase, strip punctuation and filler words (a, the, in, on, when, should), keep the 2–4 most specific words, join with `-`, truncate to 32 chars at a word boundary.
5. Compose the working name and the final-name template. Show both to the user before creating anything.

## Phase 2: Is this issue already addressed?

Run all three checks — each catches work the others miss. Any hit means **stop and report**, don't create a second worktree for the same issue:

1. **Open PR closing it** — `gh pr list --state open --json number,title,headRefName,closingIssuesReferences` and look for `<n>` in any `closingIssuesReferences`.
2. **PR head ref naming it** — from the same result, any `headRefName` matching `(^|-)I?<n>(-|$)`. Catches PRs that reference the issue in prose but never linked it.
3. **Local or remote branch naming it** — `git branch -a` with the same pattern. Catches in-flight work that has no PR yet, and abandoned half-finished branches. This is the cheapest durable signal: a branch persists regardless of PR state or whether any session is still running.

In batch mode these three checks *are* the "not already addressed by a PR" filter — run them per issue, and report each skip with which check fired. They compose with Phase 1's deferral check: a batch run skips deferred issues *and* already-addressed ones, and reports the two groups separately, since one is a scheduling decision and the other is a duplicate-work guard.

## Phase 3: Create the worktree

Run from the main repo, not from another worktree:

1. `git fetch origin` and confirm the base branch (default branch unless the user says otherwise).
2. Ensure `.worktrees/` is gitignored — check `.gitignore`, append the single line if absent, same one-line-entry convention `/pr-triage` uses for `.claude/tmp/`.
3. `git worktree add .worktrees/<working-name> -b <working-name> origin/<base>`
4. `cd` into it. **Every** subsequent edit, build, test, and git command runs inside this worktree. Never edit files in the main checkout or a sibling worktree.

The worktree directory takes the **working** name, not the final one — the PR number isn't known yet, and the directory is torn down in Phase 6 before the mismatch matters.

## Phase 4: Do the work

This skill owns the lifecycle, not the engineering. Use the normal skills inside the worktree: `superpowers:test-driven-development` for the change itself, `/run-tests` to verify, `/pre-commit` before committing, `/commit-message` for the message. Include `Fixes #<n>` in the final commit or the PR body (Phase 5 relies on it for linking).

If the issue needs design decisions the issue text doesn't settle, ask before implementing. A wrong fix delivered fast is worse than one round of questions.

## Phase 5: Push and open the PR

1. `git push -u origin <working-name>` — the remote branch keeps this name permanently.
2. `gh pr create --title "<title>" --body "<body>"`. The body must contain `Fixes #<n>` so GitHub links the issue, and should name the finding ID (`Addresses F3 from the project review`) when there is one.
3. Capture the PR number from the command's output. If PR creation fails, stop here — do not rename, do not tear down. The worktree stays exactly as it is and the failure gets reported.

## Phase 6: Rename, then tear down

1. **Rename the local branch**, from inside the worktree: `git branch -m PR<pr>-<working-name>`. Git moves the branch's config section with it, so upstream tracking survives and still points at the working-named remote branch.
2. `cd` back to the main repo root.
3. **Teardown preconditions** — check all three, and abort teardown if any fails:
   - `git status --porcelain` in the worktree is empty
   - `git log @{u}..` is empty (nothing unpushed)
   - the PR was created successfully in Phase 5

   If any check fails, **keep the worktree**, print its absolute path and which check failed, and say the branch is renamed but the tree is still live. Never `git worktree remove --force`.
4. `git worktree remove .worktrees/<working-name>` — by its original path; the directory was never renamed.
5. **Keep the renamed local branch.** It's the artifact that makes `git branch -d PR68-Fix-I60-F3-rust-ps-path` work after the PR merges, and it's what `git branch` shows you when you're trying to remember which branch became which PR.
6. Report: issue number and title, PR number and URL, the final branch name, and whether the worktree was removed or kept (and why).

## Coming back to a PR later

The worktree is gone by design — recreate one only when you actually need to iterate or review locally:

```bash
git worktree add .worktrees/PR68-Fix-I60-F3-rust-ps-path PR68-Fix-I60-F3-rust-ps-path   # local branch still exists
gh pr checkout 68 --branch PR68-Fix-I60-F3-rust-ps-path                                 # it doesn't (fresh clone, other machine)
```

`gh pr checkout`'s `--branch` flag is what keeps the PR-prefixed convention intact — without it, gh names the local branch after the remote head ref, which is the un-prefixed working name.

**Gotcha after the rename:** `git push` with git's default `push.default=simple` refuses to push when the local branch name differs from its upstream's name, which is exactly the state Phase 6 leaves behind. To push more commits to the same PR, use an explicit refspec: `git push origin HEAD:<working-name>`. This is the main reason the rename is the *last* step rather than an early one.

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
3. **Order the queue with `/issue-triage`.** Pass the surviving candidate set to it and use the plan it returns. Run it fresh every time — never read a previous `.claude/tmp/issue-triage/` snapshot, which any merge, close, or label change since invalidates. Its dispositions bind this run:

   | Disposition | What batch mode does |
   |---|---|
   | `WORK n` | Work it alone, at position n. |
   | `GROUP` | Work all its issues on **one** worktree, one branch, one PR — see the grouped-unit naming above. Never split a group into consecutive single runs; the second branch would be cut from `main` and conflict with the first by construction. |
   | `NEEDS-DECISION` | **Halt and ask.** Present the question and the options the issue names. Do not implement, do not guess, do not skip silently. |
   | `DEFER` | Report as a deferral proposal and skip. Never apply the label. |
   | `CLOSE-MOOT` | Report the proposal with its evidence and skip. Never close the issue. |

   If `/issue-triage` is unavailable, fall back to working the candidate set in issue-number order and say so explicitly — an unordered batch is a degraded run, not the normal path.
4. Run Phases 1 and 3–6 on each work unit **sequentially**, in the triage order — one worktree at a time, fully torn down before the next is created. Sequential is deliberate: parallel worktrees on overlapping code produce conflicting PRs, which is the problem `/pr-triage` then has to clean up.
5. A failure on one unit doesn't abort the run. Record it, move to the next, and end with a table: issues, PR (or the failure reason), final branch name, worktree removed y/n — plus the `NEEDS-DECISION`, `DEFER`, and `CLOSE-MOOT` sets, which are the run's real output for the user to act on.
6. Before starting a batch of more than ~3 units, show the triage plan and confirm. Each unit opens a real PR.

## Rules

* Never work in the main checkout — every change happens inside the issue's worktree.
* Never delete a worktree with uncommitted or unpushed work, and never use `git worktree remove --force`. A kept worktree with a printed reason is always the correct fallback.
* Never rename or force-push the remote branch to match the local one, and never try to repoint an open PR's head. The two names differing is the design, not a defect.
* Never invent a finding ID or an issue number. An absent `F<n>` segment is correct output; a wrong one is worse than none.
* One worktree per issue. If Phase 2 says the issue is already covered, stop — don't create a parallel attempt.
* Never implement a `NEEDS-DECISION` issue by choosing the policy yourself. The whole point of the disposition is that the choice reaches the user before code exists.
* Never act on `/issue-triage`'s `CLOSE-MOOT` or `DEFER` proposals — report them. Closing an issue or deferring one is a mutation on a judgment call; triage is advisory and so is this skill's handling of it.
* Never work a deferred issue in batch mode, and never strip a deferral label to make an issue eligible. Deciding something is worth doing now is the user's call; the label is that decision already recorded. A single explicit `/work-issue <n>` may override it, but only after asking.
* Stop and report rather than guess when `gh` fails (auth, rate limit) or the issue number doesn't exist. No silent retries.

---

# Project documentation

Everything below is for humans installing, using, or contributing to this skill. It is not part of the protocol.

This skill is deliberately repo-agnostic — plain `git worktree` and `gh`, no project-specific session-coordination tooling. If a given repo needs extra steps (submodule pointers, a coordination registry, mandated branch prefixes for certain change types), those belong in that repo's `CLAUDE.md`, not here.

## Usage

```
/work-issue 60
/work-issue all
```

Or just say it: "fix issue 60 on a worktree, push the branch and open a PR". The skill is model-invocable precisely so that phrasing works — the whole point is that the naming convention applies whether or not you remember to type the slash command.

## Why the PR number is in the branch name at all

Because the alternative is reading three numbers off three different surfaces. An issue number tells you what the work is; a PR number tells you where to review it; a finding ID tells you which review row it came from. `git branch` and `ls .worktrees/` only ever showed the first one, so every "which PR was this again?" required a `gh pr list`. Putting all three in one string makes `gh pr checkout 68`, `git branch -d PR68-…`, and grepping a review report all reachable from a name you're already looking at.

## Why the remote branch keeps the un-prefixed name

Chicken-and-egg: the PR number is assigned by `gh pr create`, which needs the branch pushed first. GitHub has no API to change an open PR's head branch, so making the remote match would mean closing the PR and refiling it — losing review comments and CI history to fix a cosmetic mismatch. The local name is where the ergonomics actually live (`git branch`, `git worktree`, tab-completion), so that's where the PR number goes.

## Why the worktree gets torn down

Once the PR is open, the local tree has served its purpose — review happens on the web or in a freshly checked-out worktree, and a directory left behind "just in case" accumulates into exactly the pile this naming scheme was invented to navigate. Teardown is conditional, not eager: uncommitted work, unpushed commits, or a failed PR creation all keep the tree alive with a printed reason.

## How this fits with the other skills

`/project-review` and `/code-review` find the work; `/make-issues` files it as GitHub issues and records the `finding_id` this skill reads back out; `/work-issue` turns one issue into a PR; `/pr-triage` orders the resulting PR queue for merging. The finding ID is the thread running through all four — it's why `/make-issues` records `finding_id` in its fingerprint marker even though it deliberately never *matches* on it.

## Limitations

- Requires an issue. There's no "quick fix with no issue" path, by design — the branch format has nowhere to put a missing `I<n>`.
- Batch mode is sequential. Parallel worktrees would be faster and would produce conflicting PRs on overlapping code.
- The finding ID is only as good as what `/make-issues` recorded at filing time. Issues predating that field, and hand-filed issues, get no `F<n>` segment ever — `/make-issues backfill` deliberately doesn't invent one.
- No cleanup of the renamed local branches after their PRs merge. `git branch -d PR68-…` stays a manual step, which is the whole reason the PR number is in the name.
