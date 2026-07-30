# `/code-review` PR mode — design

Status: implemented. One design revision made during implementation: the **Out of scope
(pre-existing)** section was originally described as a feed for `/make-issues`. It isn't —
those entries carry no tier, severity, or evidence, so filing one means inventing all three,
which the pipeline's "an inferred value is a bug" rule forbids. `/make-issues` now skips that
section explicitly and points at scope mode instead. See "What counts as a finding" below.

## Problem

`/code-review` takes a scope — a folder, file, or glob — and reviews whatever is in the
working tree at that path. It has no way to review a change *as a change*.

That gap is already visible in the pipeline. `WORKFLOW.md`'s stage 6 tells you to run
"`/code-review` (or `/review`) the specific PR" before merging, but `/code-review` can't
take a PR, so the parenthetical is doing all the work. The fallback it points at, the
built-in `/review`, is a fifteen-line prompt template: `gh pr view` + `gh pr diff`, then
prose to the terminal. No severity taxonomy, no scoring, no saved artifact, no
`/make-issues` hand-off, and no file context beyond the diff itself.

So the one stage of the pipeline that most needs a line-level record — the last gate before
code lands on `main` — is the only stage with no durable artifact.

Reviewing a PR by hand today means checking the branch out into the working tree (which
disturbs whatever you were doing) and then running `/code-review` on a scope, which reports
every pre-existing issue in those files alongside the ones the PR actually introduced.

## Goals

- `/code-review 68` reviews what PR #68 proposes, using the same tiers, scoring, reporting
  rule, and report format as scope mode.
- Findings are about *this PR*, not pre-existing debt in the files it happens to touch.
- The working tree is never disturbed — no checkout, no worktree, nothing to tear down.
- The report is a normal `/code-review` report: same directory, same gitignore pattern,
  parseable by `/make-issues` with no new parser.
- Downstream skills that read `docs/reviews/` can tell a PR report apart from a scope report
  and treat it correctly, rather than silently mistaking unmerged-branch findings for
  findings about `main`.

## Non-goals

- **Not a replacement for the built-in `/review`.** That stays the quick prose read of a PR
  with no artifact. This is the version that leaves a record.
- **Not GitHub-mutating.** No inline review comments, no summary comment, no approve or
  request-changes. `/code-review` stays read-only, like every other review skill in this
  repo; `/make-issues` remains the only skill in the review chain that writes to GitHub.
- **Not running the PR's tests.** Review reads code. Test signal is CI's job, and needing it
  is what would force a worktree.
- **Not reviewing multiple PRs in one run.** One PR, one report. Merge-order questions across
  several PRs are `/pr-triage`'s job.
- **Not a new stage in the pipeline.** PR mode is stage 6 (pre-merge review), not a second
  stage 1. It does not create pipeline state.
- **Not diffing against a stale base.** The review is against the merge base, so unrelated
  commits that landed on `main` after the PR branched are not attributed to the PR.

## Design

### Mode detection

PR mode triggers on `/code-review <arg>` where `<arg>` is a bare integer (`68`), a
`#`-prefixed number (`#68`), a `PR`-prefixed number (`PR68`), or a GitHub PR URL
(`https://github.com/owner/repo/pull/68`). Everything else is scope mode, unchanged.

A bare integer is always a PR, never a path. If `gh pr view` can't resolve it, the skill
stops and reports what it tried — it does not fall back to interpreting `68` as a scope,
because a silent fallback would produce a confusing "no files found" error for what is
really an auth or wrong-repo problem.

`--focus` behaves identically in PR mode. `--refresh` means re-fetch the PR head, which may
have gained commits since the last run, and write a new dated report.

### Gathering the code

```
gh auth status                      # hard requirement; fail with a clear message
gh pr view <n> --json number,title,state,isDraft,author,baseRefName,headRefName,\
                     headRefOid,baseRefOid,additions,deletions,changedFiles,url
git fetch origin pull/<n>/head      # works for fork PRs; no local branch created
git merge-base <baseRefOid> <headRefOid>
gh pr diff <n>                      # the hunks
git show <headSha>:<path>           # full-file context, per changed file
```

Nothing is checked out. `git show` against the fetched sha gives full-file context for
analysis while the working tree stays exactly as it was — which also means there is no
teardown step and therefore no failure mode where a stale worktree is left behind.

Diffing against the **merge base** rather than the base branch tip is what keeps unrelated
commits that landed on `main` after the PR branched from being attributed to the PR.

State handling:

| PR state | Behavior |
|---|---|
| Open | Proceed |
| Draft | Proceed, note draft status in the report header |
| Merged or closed | Say so and ask before continuing — legitimate but usually a mistake |

The existing 30-file threshold applies to `changedFiles`. Deleted files are reviewed from
the diff alone (there is no file at head to read). Binaries, lockfiles, and generated files
are skipped and listed as skipped, so the reader knows they weren't silently dropped.

### What counts as a finding

Full files are read for context; findings are reported only on lines the PR **added or
modified**.

One deliberate exception: a problem the PR *causes* on a line it did not touch — a changed
function contract that breaks an existing caller, a renamed field that an untouched
serializer still writes. These are reported with an extra `**Introduced by:**` field naming
the hunk responsible, so an untouched-line finding always carries its own justification.
Without that field the finding is out of scope by definition.

Pre-existing issues on untouched lines are not ranked and do not consume report slots. A
capped list of at most three appears in an **Out of scope (pre-existing)** section at the
bottom — names and locations only, no evidence blocks — because the reader will want to know
they were seen and skipped. The cap is what keeps the section from turning back into the
scope-mode report that PR mode exists to avoid.

That section is a pointer, not a work queue. `/make-issues` skips it: an entry with no tier,
severity, or evidence can't become an issue without inventing all three, and `WORKFLOW.md`'s
rule is that an inferred value is a bug. Running scope-mode `/code-review <path>` on the file
is what turns one into a finding that can be filed.

### Report

Path: `docs/reviews/code-review_PR68_2026-07-30.md`.

This matches the existing `docs/reviews/code-review*.md` gitignore pattern and
`/make-issues`' `code-review_*.md` source detector, so neither needs to change to accept it.

Frontmatter is a **superset** of the existing three keys, so every existing consumer keeps
working:

```yaml
git_sha: <PR head sha>     # existing key — the commit the line numbers refer to
generated_at: 2026-07-30T14:32:00-07:00
scope: PR #68
pr: 68                     # presence of this key marks an unmerged-branch report
pr_base_ref: main
pr_base_sha: <merge base>
```

`git_sha` holding the PR head sha is the important part: it keeps `/project-review`'s and
`/make-issues`' per-file staleness checks pointed at the commit the line numbers were
computed against, rather than at a commit that never contained this code.

`pr:` is the marker downstream skills key on. Its *presence* means "this report describes
code that is not on the base branch."

Tiers, IDIOM scoring, and the "all HIGH + top (10 − num_HIGH)" reporting rule are unchanged.
The report header gains PR title, author, state, and ± line counts.

### Downstream corrections

Three existing consumers read `docs/reviews/` and would each draw a wrong conclusion from a
PR report. Each fix keys on the `pr:` frontmatter marker.

| Where | Wrong conclusion | Fix |
|---|---|---|
| `pipeline/pipeline-status` | `newest "docs/reviews/code-review_*.md"` matches PR reports, so a stage-6 review registers as stage-1 "the work has been found" | Exclude `code-review_PR<n>_*` from the stage-1 glob |
| `project-review` Phase 1.5 | Ingests PR findings as evidence about the repo, but that code isn't on `main`. Its `<sha>..HEAD` staleness check currently gives a defensible answer only by accident | Skip reports whose frontmatter carries `pr:` |
| `make-issues` staleness pre-check | Compares the report's `git_sha` against current `HEAD` — different branches by construction, so *every* PR report warns stale | When `pr:` is present, compare against the PR head and note the report describes an unmerged branch |

Two more files carried the old "`/code-review` (or `/review`) on that PR" phrasing, written
when `/code-review` couldn't take a PR at all, and become literal now that it can:
`pr-triage/SKILL.md` (its next-step variant and its `/code-review` cross-reference) and
`pipeline/SKILL.md` (its "top PR has never been reviewed" override, which also gains the
definition of what counts as reviewed: a `code-review_PR<n>_*.md` postdating the PR's last
push).

`WORKFLOW.md` stage 6 becomes literal: `/code-review 68`, with the built-in `/review`
described as the quick-prose alternative rather than a co-equal option. Its stage-1 section
gains the explicit note that PR mode is stage 6, its at-a-glance table lists the PR report as
stage 6's artifact, a "someone else's PR" variant is added, and the "deliberately won't do"
list gains "say anything on your behalf on a PR."

`/code-review`'s own `description` frontmatter gains the PR trigger phrases, per this repo's
convention that the description doubles as the invocation trigger.

### Hand-off

PR mode sits at stage 6, so its closing line points at the branch rather than at stage 2:

> Next: fix these on the branch so they land with the PR
> (`git fetch origin pull/68/head && git checkout -b review-68 FETCH_HEAD`), or
> `/make-issues docs/reviews/code-review_PR68_2026-07-30.md` for anything you'd rather not
> block the merge on.

Fixing on the branch is primary because a finding about a PR is usually cheapest to resolve
inside that PR. `/make-issues` is the fallback for findings that shouldn't block the merge —
and the natural destination for the **Out of scope (pre-existing)** section, which by
definition can't be fixed in this PR.

## Open questions

- Whether `--refresh` on a PR whose head moved should diff the two reports and show what
  changed, rather than just regenerating. Deferred; regeneration is correct, a diff is a
  convenience.
- Whether a repeat run on the same PR on the same day should overwrite or version the report.
  Scope mode has the same collision today, so PR mode inherits its behavior rather than
  inventing a different one.
