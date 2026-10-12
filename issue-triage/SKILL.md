---
name: issue-triage
argument-hint: "[#n ...] [--verify] [--reverify #n ...]"
description: Make GitHub issues complete, whoever filed them. Adds what is missing and nothing else — a summary at the top, severity/category/effort labels in empty namespaces, and the dedup fingerprint — after one confirmation table. With --verify, reproduces each issue once and records the steps in the issue. Owns the label vocabulary, the category rules, the summary format and the fingerprint format that /make-issues also uses. Use when the user files an issue by hand, asks to "triage", "label", "summarize" or "fill in" issues, or when /make-issues has just filed issues. For deciding what to fix first, use /fix-order instead.
disable-model-invocation: false
---

# Issue Triage

The gate that every issue passes through. An issue can come from `/make-issues`, from Matt
Pocock's `/to-spec` or `/to-tickets`, or from a person. After this skill, each one has the
same things: a summary, labels, and a fingerprint. Then `/fix-order` can rank all of them
with no review report in hand.

When invoked via `/issue-triage`, follow the protocol below. Everything from here through the
`---` divider is the protocol to execute. The section after the divider is documentation for
humans.

Design: `docs/specs/2026-10-12-unified-issue-workflow-design.md` (D2) in this repo.

---

## Operating principles

**Fill gaps, never rewrite.** Every pass adds only what is missing. A label goes only into an
empty namespace. A summary goes only onto a body that has none. A fingerprint goes only onto an
issue that has none. A person's work on an issue stays exactly as it is.

**Nothing is applied before the user confirms.** All proposals go into one table. The user may
accept all, drop rows, or change a value. The only write without that table is the
verification comment, which `--verify` asks for by name.

**An empty result is honest; a guessed value is a bug.** When the issue text gives no basis for
a value, leave it empty and show `—`.

**Never edit Matt Pocock's skills or their labels.** `/to-spec` and `/to-tickets` add
`ready-for-agent`. Leave it, and every other label this skill does not own, as it is.

## Phase 0: Arguments

- `/issue-triage` — every **open** issue.
- `/issue-triage #12 #15` — only those issues, in any state.
- `--verify` — also run Phase 5 on the issues in scope. Off by default.
- `--reverify #n ...` — run Phase 5 again on those issues, even when they have a marker.
- Called by `/make-issues` — the scope is the issues that run just filed. The caller passes
  their numbers. Same protocol, same confirmation table.

## The vocabulary

This file owns the label vocabulary, the category rules, the summary format and the
fingerprint format. `/make-issues` uses them from here; it does not keep a copy.

### Labels

Baseline — 23 labels (13 category + 4 severity + 3 effort + 2 source + 1 status), matching
`/project-review`'s Phase 2 dimensions and `/code-review`'s severity/IDIOM tiers:

```
category: Architectural decay              #d4c5f9
category: Consistency rot                  #d4c5f9
category: Type & contract debt             #d4c5f9
category: Dependency & config debt         #d4c5f9
category: Test debt                        #d4c5f9
category: Documentation drift              #d4c5f9
category: Error handling & observability   #d4c5f9
category: UX & CLI ergonomics              #d4c5f9
category: IDIOM                            #d4c5f9
category: Performance & resource hygiene   #d4c5f9
category: Security hygiene                 #d4c5f9
category: Correctness & memory safety      #d4c5f9
category: Data integrity & robustness      #d4c5f9

severity: Critical   #b60205
severity: High        #d73a4a
severity: Medium      #fbca04
severity: Low         #0e8a16

effort: L   #1d76db
effort: M   #5319e7
effort: S   #c5def5

source: project-review   #bfd4f2
source: code-review      #bfd4f2

status: needs-decision   #d876e3
```

`status:` is a workflow axis rather than a property of the issue, which is why it is a
namespace of its own rather than another `category:`. **Neither this skill nor `/make-issues`
applies it or creates it.** It is listed here because this file owns the vocabulary, and
`/fix-order label` (its only writer) needs a canonical name and color to reuse instead of
minting a variant.

**Seeding.** Before the first label write of a run, `gh label list`, then create any
`severity:`/`effort:`/`source:` label that this run will apply and that is missing. Create only
what the run uses: an unused label on every repo is noise. Never create `status:`.

`severity:`/`effort:`/`source:`/`status:` are **closed** (structural, not open
classification). Never mint a new value in them.

### Category resolution

`category:` is a **baseline, not a closed set** (favor reuse, allow a new category when it is
truly needed). Resolve every category value in this order before applying a label:

1. **Exact or close semantic match against this repo's existing `category:` labels**
   (`gh label list`) — "Data consistency" reuses an existing
   `category: Data integrity & robustness` rather than minting a near-duplicate. A judgment
   call, not a strict string match.
2. **Exact or close semantic match against the baseline above** — reuse its exact name/color.
3. **Otherwise, it is new** — `gh label create "category: <name>" --color "d4c5f9"
   --description "issue category"`, and name the new category in the run's report so it is
   visible rather than silently added.

Never skip to step 3, and never force a bad fit against an existing label to avoid creating
one.

### Summary format

The format of the user's global `CLAUDE.md` "GitHub issues" rule, at the very top of the body:

```markdown
> **SUMMARY:** One or two sentences about the effect on the user.

---
```

In ASD-STE100 Simplified Technical English. The one or two most important user impacts. An
enhancement gets the advantage to the user. No file names, no function names, no detail of the
solution. If the issue changes nothing that the user can see, say so, then give the effect on
the developer who reads or changes the code.

### Fingerprint format

A hidden marker that dedup (`/make-issues` Phase 3) and overlap (`/fix-order` Phase 2) read.
The marker name `project-review-finding` is kept for compatibility with every issue already
filed:

```html
<!-- project-review-finding
source: project-review|code-review|issue-triage
finding_id: <only when a review report filed the issue>
file: <path>
category: <primary category>
keywords: <comma-separated>
-->
```

- `keywords` — literal identifiers the issue cites (function names, types, variables — copied,
  not paraphrased) plus 1–3 short concept terms ("hash collision", "duplicate mapping").
  Reproducible tokens from the issue's own text, not a paraphrase that varies between runs.
- `finding_id` — provenance only, written by `/make-issues`. Omit it on every fingerprint this
  skill writes: a hand-filed issue has no report row, and inferring one would fabricate
  provenance.
- `source: backfill` on older issues means the same as `source: issue-triage`.

## Phase 1: Read the issues

`gh issue list --state open --limit 200 --json number,title,body,comments,labels,state` (or
`gh issue view <n> --json ...` for each `#n`). For each issue, note:

- fingerprint: present if the marker is in the body or in any comment,
- labels per namespace (`severity:`, `category:`, `effort:`, `source:`),
- summary: present if the body contains `**SUMMARY:**`, wherever it sits and whoever wrote it,
- verification: present if any comment contains `<!-- issue-verification`.

An issue that has everything is done. List it once as complete and skip it.

## Phase 2: Fingerprint

For each issue with no fingerprint:

1. Does it reference specific code in this repo (file paths, function/type names, a stack
   trace)? If not (a question, a feature request with no code reference), skip it. Don't force
   a fit.
2. Infer the file(s) it concerns, a category per "Category resolution", and keywords per
   "Fingerprint format".
3. Propose a **new comment** with the marker (`source: issue-triage`, no `finding_id`). Never
   edit the body for a fingerprint.

## Phase 3: Labels

A label **fills a gap**: it goes only into a namespace (`severity:`, `category:`, `effort:`)
where the issue has no label yet. Labels a person already applied stay exactly as they are.

1. **Assess** a value for each empty namespace from the issue's title, body and comments. On a
   hand-filed issue (no `source:` label), assess the filled namespaces too, for step 2. Decide
   each value from the text **before** you look at the issue's labels, so the current label does
   not anchor the result:
   - `severity:` — Low/Medium/High/Critical: the impact on the user, or on the maintainer when
     nothing is user-visible. A feature request takes the severity of the gap it fills (usually
     Low or Medium).
   - `category:` — per "Category resolution". Reuse the Phase 2 category when Phase 2
     fingerprinted this issue, so the marker and the label agree. A feature request with no debt
     or defect in it usually has no fitting category: leave the namespace empty.
   - `effort:` — S (one focused change), M (several files or a design choice), L (a restructure
     or a multi-PR feature), judged from the scope the issue describes.
2. **Compare** each assessed value of a filled namespace with the label already there. Every
   difference is a **disagreement**: one line with the issue, the namespace, the current and the
   assessed value, and a short reason (`#340 effort: S → M — needs a pending-digit state and a
   keymap change`). Disagreements go to the report, never into a label. Skip issues with a
   `source:` label: a review tool set those labels from more evidence than the issue text holds.
3. Never add a `source:` label. It records which tool filed an issue, so a hand-filed issue gets
   none.

## Phase 4: Summary

A summary is **added, never rewritten**: a person may have curated an existing one.

1. Scope: the issues with no `**SUMMARY:**` in the body.
2. Draft each one per "Summary format", from the title, body and comments.

## Confirm and apply

1. **Show one table** — issue number, title, proposed fingerprint (file + category), proposed
   labels with a short reason, proposed summary. Ask for confirmation. Apply nothing before the
   answer.
2. **Fingerprints** — `gh issue comment <n> --body-file <file>`.
3. **Labels** — seed per "Labels", then `gh issue edit <n> --add-label ...`.
4. **Summaries** — fetch the body again just before the write. If it changed since the draft, or
   it now contains `**SUMMARY:**`, skip that issue and say so. Otherwise write the summary
   block, a blank line, then the fetched body byte for byte (`gh issue edit <n> --body-file
   <file>`, so no shell quoting touches it).

## Phase 5: Verify (only with `--verify` or `--reverify`)

The idea comes from the verification step of Matt Pocock's `/triage`. The text here is this
repo's own, so his updates never conflict with it.

1. **Skip** an issue that has an `issue-verification` marker, unless `--reverify` names it, or
   the issue body or a comment by a person changed after the marker's comment.
   A new commit alone is **not** a reason: the `sha:` field shows how old the result is.
2. **Bug:** reproduce the claim from the issue's own steps, or from a minimal case the issue
   describes. **Enhancement, refactor, test gap:** confirm the gap is still there (the code
   still does what the issue says).
3. The result is one of:
   - `confirmed` — with the code path and the commands that showed it,
   - `not-reproduced` — what was tried,
   - `not-enough-detail` — the questions that block it,
   - `already-fixed` — where the fix is.
4. **Write the result into the issue, once**, as a new comment:

   ```markdown
   ## Verification

   **Result:** confirmed at `<short sha>`

   **Steps to reproduce:**
   1. ...

   **Code path:** `src/filelist.rs:66` (`read_filelist`) → `src/options.rs:89` (`resolve`)

   <!-- issue-verification
   result: confirmed
   sha: <full sha>
   -->
   ```

   Write the steps so `/work-issue` can turn them into its first failing test without doing the
   work again.
5. `already-fixed`, `not-reproduced` and `not-enough-detail` are reported. They never close an
   issue and never add a label. `/fix-order` reads them.

## Report

- Issues complete before the run, and issues changed.
- Count per label namespace, issues left with an empty namespace, any new category minted.
- **Disagreements** — the Phase 3 step 2 lines, or "none".
- Summaries added, and issues skipped because their body changed.
- With `--verify`: each issue and its result.

## Next in the pipeline

End the run with the next step as the last line:

> Next: `/fix-order` to decide what to fix first, and what to fix together.

When `/make-issues` called this skill, leave the "Next" line to `/make-issues`.

## Rules

- Never edit an issue body, except to prepend a confirmed summary to a body that has none.
  Every other byte stays as it was.
- Never remove or change a label. Add only into an empty namespace, only after the user confirms.
- Never apply `status:` or any label of Matt Pocock's skills (`ready-for-agent`, `needs-triage`,
  `bug`, `enhancement`, …).
- Run "Category resolution" in order. Never skip to minting.
- Verify only with `--verify` or `--reverify`. Never verify the same issue twice without a
  reason from Phase 5 step 1.
- Stop and report when `gh` reports an authentication or API error. No silent retries.

---

# Project documentation

Everything below is for humans. It is not part of the protocol above.

## Usage

```
/issue-triage                     # every open issue: fill what is missing
/issue-triage #12 #15             # only those issues, any state
/issue-triage --verify            # also reproduce each unverified issue
/issue-triage --reverify #12      # reproduce #12 again
```

## Why this is separate from `/fix-order`

`/fix-order` answers "what do I fix first?". This skill answers "is each issue complete enough
to rank?". The old `/issue-triage` did the first job, and the second was hidden in
`/make-issues backfill`. A hand-filed issue then needed a skill named for filing review findings.
Now each job has one skill, with a name that says what it does.

## Why verification is opt-in

A review finding already has evidence (`file:line`, a snippet) from the `HEAD` it was found at.
One review can file many issues, and many are not worked soon. A check made weeks before the
work is old when the work starts. So verification is a trial: the user runs `--verify` when it
is useful, and decides later whether a path (hand-filed issues, `/work-issue`) should verify by
default (spec Q6).

## Relation to Matt Pocock's `/triage`

His `/triage` moves one issue at a time through state labels (`needs-triage`,
`ready-for-agent`, …), waits for direction at each step, can close issues, and is
`disable-model-invocation: true`, so no skill can call it. It stays installed for manual use:
type `/triage #n` when one issue needs questions, grilling, and an agent brief. This skill
never applies his labels.

## Limitations

- Labels and categories are LLM judgment calls. Expect occasional misclassification,
  correctable by hand in GitHub.
- Fingerprints for hand-filed issues are inferred from prose, so they are weaker than the ones
  `/make-issues` writes from a review report.
