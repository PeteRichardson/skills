---
name: pipeline
description: Report where this repo stands in the review → issue → PR → merge pipeline and name the next command to run. Reads the artifacts each stage leaves behind (docs/reviews/, fingerprinted issues, .claude/tmp/ snapshots, Fix-I branches, open PRs) — there is no state file. Supports `/pipeline` (dashboard), `/pipeline next`, `/pipeline brief` (cheat sheet, no API calls), `/pipeline blocked` (only what needs a decision from you), and `/pipeline doc`. Use when the user types /pipeline, asks where they are in the workflow, what the next step is, or what's blocking them. Advisory only — it names commands and never runs a pipeline stage.
disable-model-invocation: true
---

# Pipeline

A status skill for the six-stage workflow documented in `~/.claude/skills/WORKFLOW.md`:
review → file → triage → work → order → merge.

It answers one question — *what do I type next?* — and it answers it from artifacts rather
than from anything it remembers.

When invoked via `/pipeline`, follow the protocol below. Everything from here through the
`---` divider is the protocol Claude executes. The section after the divider is
documentation for humans installing or maintaining this skill.

---

## Operating principles

**Detect, never track.** Every stage leaves a durable artifact, so the current position is
always derivable. Never write a progress file, never carry state between invocations, and
never trust a previous run's conclusion — the user merges PRs, closes issues, and abandons
branches outside this skill constantly, and a tracker would be wrong the first time they did.

**This skill runs nothing.** It names the next command; the user types it. That boundary is
the same one `/issue-triage` and `/pr-triage` hold, and it's what keeps stage 6 — merging —
a thing the user does by hand deliberately.

**The script does the counting; you do the judgment.** `pipeline-status` (next to this file)
computes every count and the mechanical next-step cascade. Don't re-derive its numbers with
your own `gh` calls. Your value is the part it can't do: reading the actual text of a
`NEEDS-DECISION` question, noticing a semantic-collision warning in a merge order, spotting
that a "stale" report is stale only because of unrelated commits.

## Phase 0: Subcommands

* **`/pipeline`** (no args) — dashboard + next step. Proceed to Phase 1.
* **`/pipeline next`** — the next command only, with one line of why. Run
  `pipeline-status -b`, then add reasoning per Phase 2 if the recommendation depends on
  something that needs reading (a decision question, a conflicting PR). Stop there.
* **`/pipeline brief`** — the cheat sheet. Print the six stages and their commands from
  memory of `WORKFLOW.md`'s "At a glance" table. **Make no API or filesystem calls at all** —
  this mode exists to be instant when the user just needs reminding what the order is.
  Stop here.
* **`/pipeline blocked`** — only what's waiting on a human decision. Skip the dashboard;
  run Phase 1, then report just the Phase 2 blocked-on-you items. If nothing is blocked,
  say so in one line and name the next command instead.
* **`/pipeline doc`** — print the path to `~/.claude/skills/WORKFLOW.md` and offer to open
  it. Don't paste the whole file into the conversation unless asked. Stop here.

## Phase 1: Run the detector

```bash
~/.claude/skills/pipeline/pipeline-status
```

Show its output verbatim — it's already formatted, and reformatting it into prose loses the
at-a-glance shape that's the point. Add `-n` if the user asked for an offline check.

If the script is missing or not executable, fall back to running its checks by hand and say
you did:

```bash
ls -lt docs/reviews/                                       # stage 1
gh issue list --state open --limit 300 --json number,labels # stage 2
ls -lt .claude/tmp/issue-triage/                           # stage 3
git branch -a | grep -E 'Fix-I[0-9]+' ; gh pr list         # stage 4
ls -lt .claude/tmp/pr-triage/                              # stage 5
gh pr list --state merged --limit 30                       # stage 6
```

## Phase 2: Add what the script can't judge

Read further **only** where the dashboard shows something that needs it. Don't open files to
confirm counts the script already produced.

| Dashboard shows | Read this | Report |
|---|---|---|
| `N NEEDS-DECISION` | The `Decisions needed` section of the newest `.claude/tmp/issue-triage/*.md` | The actual question and the options the issue named — answerable without opening GitHub. Mention `/issue-triage label` if the issues don't already carry `status: needs-decision`, but never run it: it mutates GitHub |
| A triage snapshot exists | Its `Proposed deferrals` / `Proposed closures` sections | Standing proposals, flagged as awaiting the user's call. Never as blockers |
| `N CONFLICTING` PRs | `gh pr list --json number,title,mergeable` | Which PRs need author action regardless of queue position |
| A merge order exists | The `Overlap detail` section of the newest `.claude/tmp/pr-triage/*.md` | Any **likely semantic collision** pairs — the ones where a careless rebase merges cleanly and is still wrong |
| `[stale]` on the merge order | Nothing extra | That the order must be re-run before working down it |
| `[stale]` on the review | `git log --oneline -<N>` for the commits since | Whether the drift actually touches reviewed code, or is unrelated churn. A report stale only by docs commits isn't really stale |

Everything in this table is optional detail. If the dashboard is clean and the next step is
unambiguous, say the next step and stop — a status check that produces three paragraphs when
the answer is one command has failed at its job.

## Phase 3: The next step

The script's `next:` line is the recommendation. Restate it as a command the user can type,
and add the one-sentence reason only if it isn't obvious from the dashboard.

Override the script's cascade in exactly these cases, and say why when you do:

* **It recommends `/work-issue all` but the triage snapshot is older than the newest issue
  update** — recommend re-running `/issue-triage` first. Its ordering is computed against a
  queue that has since changed.
* **It recommends `/make-issues` but no review report is fresh enough to file from** — the
  script only checks `PROJECT_REVIEW.md`'s commit drift. If the only report is a
  `/code-review` of a scope that has since been rewritten, say so.
* **It recommends merging but the top PR has never been reviewed** — `/code-review <pr>`
  comes first. A PR counts as reviewed if `docs/reviews/code-review_PR<n>_*.md` exists and
  postdates the PR's last push; the script checks only for the file's existence, so a report
  older than the newest commit on that PR is one you should call out.
* **The script recommends merging but the top PR is a stacked child** — read its
  `work-issue-stack` marker and check the parent's state. The script already recommends
  `/work-issue restack` ahead of any merge for a PR whose parent has merged, computed from
  the same `gh pr list` output rather than a per-PR call; this override only fires if you
  believe its count is stale (a parent merged in the seconds between the two runs).

Where the recommendation depends on a judgment the user might disagree with, say what the
alternative is in a clause, not a paragraph. One recommendation, not a menu.

## Rules

* Never run a pipeline stage. Not `/project-review`, not `/make-issues`, not `/work-issue`,
  and above all never a merge. This skill types nothing on the user's behalf.
* Never write a state, progress, or cache file. The dashboard is recomputed every time.
* Never contradict the script's counts with a remembered number. If a count looks wrong,
  re-run the script; don't argue with it from memory.
* Never report a stage as complete without an artifact backing it. "No issues have a
  `source:` label" is a finding; "you probably already filed those" is a guess.
* `/pipeline brief` makes no calls. If you find yourself running `gh` in brief mode, you've
  misread the subcommand.
* If `gh` fails (auth, rate limit), the script degrades to offline and says so — report that
  the GitHub-dependent stages are unknown rather than reporting them as empty.

---

# Project documentation

Everything below is for humans installing, using, or contributing to this skill. It is not
part of the protocol above.

## Installation

The skill is two files in one directory:

```
~/.claude/skills/pipeline/
├── SKILL.md          # this file
└── pipeline-status   # the detector (chmod +x)
```

`pipeline-status` needs `git`, and `gh` + `jq` for the GitHub-backed stages. Without `gh` or
`jq` it degrades to local artifacts only and says so, rather than reporting zeros.

## Usage

```
/pipeline            # dashboard + next step
/pipeline next       # just the next command
/pipeline brief      # the six-stage cheat sheet, instant, no API calls
/pipeline blocked    # only what's waiting on a decision from you
/pipeline doc        # where WORKFLOW.md lives
```

The script is worth using directly too — it's a shell alias away and costs nothing:

```bash
alias ps6='~/.claude/skills/pipeline/pipeline-status'
alias ps6n='~/.claude/skills/pipeline/pipeline-status -b'
```

```
  greep  (main)

  1 review      PROJECT_REVIEW.md  41m ago  ·  1 commits since  [stale]
  2 issues      34 open  ·  34 from a review report
  3 triage      ISSUE_TRIAGE.md  14m ago  ·  18 units  ·  2 NEEDS-DECISION  <- blocked on you
  4 in flight   1 branches  ·  0 PRs open
  5 merge order —
  6 merged      5 PRs (last 30)

  next: answer the 2 NEEDS-DECISION issue(s) in .claude/tmp/issue-triage/ISSUE_TRIAGE.md,
        then re-run /issue-triage
```

Run the script when you want the shape; run the skill when you want the shape plus what the
decisions actually are.

## Why there's no state file

Every alternative design started with "track which stage the user is on," and every one of
them breaks on the first merge done in a browser tab. The artifacts are already a complete
record — `docs/reviews/` for stage 1, `source:` labels and fingerprint markers for stage 2,
`.claude/tmp/*/` snapshots for stages 3 and 5, `Fix-I<n>` branches for stage 4, merged PRs
for stage 6 — and unlike a tracker they're written by the stages themselves, so they can't
disagree with reality.

This is the same reasoning behind `/issue-triage list` and `/pr-triage list` resolving their
snapshots against live GitHub state rather than trusting what the snapshot recorded.

## Why the detection lives in a script, not in the skill

Three reasons. It's all `ls`, `git`, `gh`, and `jq` — no model reasoning is involved in
counting branches, so paying for a model to do it is waste. It's usable outside a Claude
session, from a shell alias or a tmux status line, which is where "where am I?" is most often
asked. And having one implementation means the skill and the alias can't drift into
disagreeing about what stage you're on.

The skill's job is the part that genuinely needs reading comprehension: what the pending
decision actually *is*, whether a flagged overlap is a real semantic collision, whether a
report's staleness matters.

## Why this skill is user-invoked only

`disable-model-invocation: true`, matching `/issue-triage` and `/pr-triage`.

The specific reason is a trigger collision: `/project-review`'s description already claims
"what should I work on next" and "what needs to be done in this repo" as conversational
triggers. Those phrases are a genuinely good fit for both skills, and the two answers are
very different — one is a multi-minute repo audit, the other is a two-second status check.
Rather than have them compete on phrasing, this one stays behind the slash command.

If that ever feels wrong in practice, the fix is to narrow `/project-review`'s triggers to
audit-intent phrasings ("audit this codebase", "find issues to fix") and give this skill the
positional ones ("where am I", "what's next") — not to have both claim the same sentence.

## Limitations

- The script's next-step cascade is a fixed decision tree, not a judgment. It gets the common
  path right and is deliberately overridable by the skill (Phase 3).
- Review staleness is measured in commits since the report was written, which over-reports
  on repos with churny docs or config. Phase 2 exists partly to correct for that.
- Stage-4 coverage is inferred from branch names matching `Fix-I<n>`. Work done on a branch
  that doesn't follow `/work-issue`'s naming is invisible to it.
- `-n`/offline mode can't see issues or PRs at all, so it reports stages 2, 4 (PRs), 5's
  staleness, and 6 as unknown. That's honest, but it means the next-step recommendation is
  much weaker offline.
- Multi-repo status ("what's pending across all my projects") isn't supported. The script is
  per-repo; a loop over directories would be a separate tool.

## License

Original, written for Peter's personal skills ecosystem. Freely modifiable.
