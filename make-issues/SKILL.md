---
name: make-issues
description: Convert findings from a /project-review report (PROJECT_REVIEW.md) or a /code-review report into GitHub issues, with severity/category/effort labels and dedup against existing issues. Also backfills the dedup fingerprint onto pre-existing, hand-filed issues. Use when the user wants to turn review findings into tracked GitHub issues, file issues from a review report, or sync labels/fingerprints onto existing issues. Triggers on "turn these findings into issues", "file GitHub issues for the review", "make issues from the code review", "/make-issues".
disable-model-invocation: false
---

# Make Issues

A skill that converts findings from `/project-review`'s `PROJECT_REVIEW.md` or a `/code-review` report into GitHub issues — consistent severity/category/effort labels, deduplicated against existing issues via a hidden keyword fingerprint, without depending on either source doc surviving.

When invoked via `/make-issues`, follow the protocol below. Everything from here through the `---` divider is the protocol to execute. The section after the divider is documentation for humans installing or maintaining this skill.

Full design rationale: `docs/specs/2026-07-21-make-issues-design.md` in this repo.

---

## Operating principles

This skill mutates GitHub — it creates issues and comments on existing ones. Always show what's about to happen before creating anything, except when nothing resembles a duplicate (the fast path — see Phase 3). Never edit the body of an issue this skill didn't create; backfilling a fingerprint onto a human-authored issue always uses a new comment, never a body edit.

Dedup is best-effort, not perfect. Matching on file path + keyword overlap will occasionally miss a real duplicate or flag a false one — that's an accepted cost, not a bug to chase. Don't add embeddings, fuzzy-matching libraries, or other heavyweight machinery to close the gap.

## Phase 0: Resolve arguments and detect source format

1. Parse the invocation:
   - `/make-issues` — path defaults to `docs/reviews/PROJECT_REVIEW.md`.
   - `/make-issues <path>` — explicit path to either a `PROJECT_REVIEW.md`-shaped file or a `/code-review` report.
   - `[path] --all` — project-review: drop the severity filter. code-review: no-op (see Phase 1), accepted without error.
   - `[path] -f <ids...>` — process only the named findings (project-review: `F3`-style IDs; code-review: ordinals like `1`, `3`).
   - `/make-issues backfill` — skip straight to Phase 5. No source doc involved.
2. Read the resolved path. Missing → tell the user to run `/project-review` (if it was the default path) or point at a valid `/code-review` report, then stop. Don't guess at findings from memory or a stale read.
3. Detect source format from the file itself:
   - **Project-review**: contains a Findings table with an `ID` column (rows like `| F1 | ... |`).
   - **Code-review**: filename matches `code-review_*.md` and/or frontmatter is the `git_sha` / `generated_at` / `scope` shape, with `### N. [Issue name]` section headings instead of a table.
   - Matches neither shape → stop and say so explicitly. Do not fall back to guessing a parser.
4. **Staleness pre-check** (both formats carry frontmatter that supports this): if the source's recorded `git_sha`/commit context predates the current `HEAD` for any file a finding cites, warn once, listing which findings might have drifted line numbers — but don't block. This is advisory, matching how `/project-review`'s own Phase 1.5 treats `/code-review` staleness.

## Phase 1: Parse findings into a common record shape

Every finding, regardless of source, is normalized to: `{ id_or_ordinal, title, severity, categories[], effort_or_null, file, line_or_null, body_fields, keywords[] }`.

### Project-review source

- Parse the Findings table: `ID | Category | File:Line | Severity | Effort | Description | Recommendation`.
- `categories[]` — split the Category cell on `/` (project-review findings can carry compound categories, e.g. "Architectural decay / dead code" — each component becomes its own entry).
- Scope: default = severity in {Medium, High, Critical}. `--all` = every row. `-f F3 F5` = only those IDs; report and skip any not found in the table.

### Code-review source

- Parse each `### N. [Issue name] (TIER) ...` section (TIER ∈ {HIGH, IDIOM, MEDIUM, LOW}) into: ordinal N, tier, Location (file:line), Issue text, Evidence snippet, and tier-specific extras — HIGH: Impact; IDIOM: Severity (already derived in the report — see `code-review/SKILL.md`'s IDIOM section) + score breakdown + idiomatic-alternative comparison; MEDIUM: score breakdown.
- If an IDIOM section predates the derived-severity report format (no `Severity:` in its heading), derive it inline from the Importance score: ≥ 7/10 → High, otherwise → Medium (never Low).
- Map tier → severity: HIGH → High (bump to Critical only if the finding's own text clearly signals something beyond code-review's normal HIGH bar, e.g. active data loss — a judgment call, not a default), MEDIUM → Medium, LOW → Low, IDIOM → its derived severity.
- `categories[]`: IDIOM tier → always `["IDIOM"]`. Otherwise, resolve via Phase 4's category resolution steps — biased by tier as a prior (HIGH usually → Security hygiene, Correctness & memory safety (crashes/leaks/UAF), or Data integrity & robustness (silent data loss without a crash); MEDIUM/LOW usually → Error handling & observability, Performance & resource hygiene, Architectural decay, Consistency rot, or Documentation drift, depending on content) but not forced; pick whatever actually fits the text.
- `effort_or_null` = null always (code-review has no effort concept).
- Scope: default = every finding in the report (already curated to ~10 by `/code-review` itself — a second severity filter adds little). `--all` = same, accepted as a no-op rather than rejected. `-f 1 3` = only those ordinals, scoped to this one report file; report and skip any not found.

## Phase 2: Compose each candidate issue

For every finding in scope:

1. **Title** — short, specific summary (project-review: from Description; code-review: from the issue name).
2. **Body** — source-appropriate fields, human-readable:
   - *Project-review*: Description, Recommendation, `File:Line`, Severity, Effort.
   - *Code-review*: Issue text, Evidence snippet, Location, and Impact (HIGH) or the score breakdown + idiomatic-alternative comparison (IDIOM) or score breakdown (MEDIUM).
3. **Keywords** — literal identifiers/symbol names the finding cites (function names, types, variables — copied, not paraphrased) plus 1–3 short concept terms (e.g. "hash collision", "duplicate mapping"). These need to be reproducible tokens grounded in the finding's own text, not a paraphrase that could vary between runs.
4. **Fingerprint marker** — appended to the body:
   ```html
   <!-- project-review-finding
   source: project-review|code-review
   finding_id: <F3 (project-review) or the bare ordinal, e.g. 3 (code-review)>
   file: <path>
   category: <primary category>
   keywords: <comma-separated>
   -->
   ```
   `finding_id` is provenance only — a breadcrumb back to the report row that filed this issue, so a reader (or `/pr-triage`, which surfaces it next to the PR and issue number) can line the three identifiers up without re-deriving anything. It records the ID **as filed** and is never revised: a regenerated report may renumber, and a stale `finding_id` is expected, not an error. It is never a dedup key — see "Why dedup keys on file path + keyword overlap" below.
5. **Labels to apply**: one `severity: <X>`, one or more `category: <X>` (one per entry in `categories[]`), `effort: <X>` if not null, and `source: project-review` or `source: code-review`.

## Phase 3: Dedup search, then create

For each composed candidate, in order:

1. Search: `gh issue list --search "<file path>" --state all --json number,title,url,body,state`. `--state all` deliberately includes closed issues — a closed "fixed" issue reappearing as a live finding is meaningful signal, and `backfill` (Phase 5) covers closed issues too, so search should be consistent with that.
2. For each result, extract its stored `keywords:` — from the body (issues this skill created) or from any comment containing the marker (backfilled issues). Score plain Jaccard overlap (`|intersection| / |union|`, case-insensitive, whitespace-trimmed) against this finding's own keyword set.
3. Sort by score descending. Keep the top result, plus any others within ~5 points of it (a real tie).
4. **No candidates, or top score below ~20%**: create immediately — `gh issue create --title "<title>" --body "<body+marker>" --label "severity: X" --label "category: Y" [--label "effort: Z"] --label "source: <tool>"`. No pause.
5. **Top score at or above ~20%**: pause. Show the matched issue's title, direct URL, state (open/closed — note explicitly if closed, e.g. "closed as wontfix" vs "closed as fixed", since a rejected duplicate is a different signal than a resolved one), and the overlap score (plus ties). Ask: create anyway, or skip this finding. Move to the next finding either way.
6. Before the first `gh issue create` call in a run, ensure the target repo has all labels this run will use (Phase 4) — create any missing ones first.

## Phase 4: Label seeding and category resolution

Vendored baseline — 22 labels (13 category + 4 severity + 3 effort + 2 source), matching `/project-review`'s current Phase 2 dimensions and `/code-review`'s severity/IDIOM tiers:

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
```

This is a **baseline, not a closed set** — matches `/project-review`'s own now-extensible Phase 2 vocabulary (favor reuse, allow a new category when genuinely justified). For every `category:` value a finding names, resolve it in this order before applying a label:

1. **Exact or close semantic match against this repo's existing `category:` labels** (`gh label list`) — a finding tagged "Data consistency" should reuse an existing `category: Data integrity & robustness` label rather than mint a near-duplicate. This is a judgment call, not a strict string match.
2. **Exact or close semantic match against the vendored baseline above** — reuse its exact name/color.
3. **Otherwise, it's genuinely new** — create it with `gh label create "category: <name>" --color "d4c5f9" --description "PROJECT_REVIEW.md / code-review label"`, and mention the new category in this run's summary so it's visible rather than silently added.

`severity:`/`effort:`/`source:` labels stay closed (they're structural, not open classification) — check with `gh label list` before the first create of a run and create anything missing from the fixed list above.

## Phase 5: Backfill (subcommand)

`/make-issues backfill` — retrofits the fingerprint onto pre-existing, hand-filed issues so they participate in future dedup searches. Independent of either review doc; can be run any time.

1. `gh issue list --state all --json number,title,body,comments` for the whole repo (open and closed — deliberately, so a matching closed issue is still found later).
2. For each issue with no fingerprint marker already present (checked in the body and in every comment): determine whether it references specific code in this repo (file paths, function/type names, a stack trace, etc.). If it doesn't look code-related (a feature request with no concrete code references, a question, etc.), skip it — don't force a fit.
3. For code-related issues: infer the file(s) it concerns, a category resolved per Phase 4's steps, and keywords the same way Phase 2 does (literal identifiers, not paraphrase).
4. Post a **new comment** (never edit the original body) containing the marker, with `source: backfill` since it wasn't produced by either review tool. Omit `finding_id` entirely — a hand-filed issue has no source report row, and inferring one by matching it against a current report would fabricate provenance:
   ```html
   <!-- project-review-finding
   source: backfill
   file: <path>
   category: <category>
   keywords: <comma-separated>
   -->
   ```

## Next in the pipeline

This skill is stage 2 of the review → issue → PR → merge pipeline (`~/.claude/skills/WORKFLOW.md`). End the run by printing the next step as the last line:

> Next: `/issue-triage` to decide what to work, in what order, and what to combine.

Vary it only for these cases:

* **A `backfill` run** — same line, but note that triage is now meaningfully cheaper on this repo: the fingerprints just written are the file-overlap signal its Phase 2 reads.
* **Fewer than ~3 issues created and none share a file** — say triage is optional at this size and `/work-issue <n>` directly is reasonable. Still mention it if any two do share a file; that's the case grouping exists for.
* **Nothing was created** (everything deduped to existing issues) — recommend `/issue-triage` anyway. The queue is unchanged, not empty.

## Rules

- Never edit an issue's original body unless this skill created that issue in this same run.
- Never skip the Phase 3 dedup search, even for a single `-f`-scoped finding.
- Always run the Phase 4 category resolution steps in order (existing repo labels, then vendored baseline, then mint new) — never skip straight to minting a new category, and never force a bad fit against an existing one just to avoid creating a label.
- Stop and report rather than guess when: the source path is missing, matches neither known format, or `gh` reports an authentication/API error. No silent retries.
- `-f`/ordinal values not found in the source doc are reported as skipped; the rest of the run continues.

---

# Project documentation

Everything below is for humans installing, using, or contributing to this skill. It is not part of the protocol above.

## Installation

Personal install:

```bash
mkdir -p ~/.claude/skills/make-issues
cp /path/to/this/SKILL.md ~/.claude/skills/make-issues/SKILL.md
```

Or project-only, in `.claude/skills/make-issues/SKILL.md`, overriding the global one for that repo.

Requires the `gh` CLI, authenticated (`gh auth status`) with issue-write access to the target repo.

## Usage

In the repo you want to file issues into:

```
/make-issues                          # PROJECT_REVIEW.md, Medium+ severity
/make-issues --all                    # PROJECT_REVIEW.md, every finding
/make-issues -f F3 F5 F9              # only those finding IDs
/make-issues docs/reviews/code-review_src_2026-07-21.md          # a code-review report, every finding
/make-issues docs/reviews/code-review_src_2026-07-21.md -f 1 3   # only those ordinals from that report
/make-issues backfill                 # retrofit fingerprints onto existing hand-filed issues
```

## Why this stays a separate skill from `/project-review` and `/code-review`

Both source skills are read-only analysis tools. This one mutates GitHub — creates issues, comments on existing ones. That's a materially different blast radius, and bundling it as a subcommand would blur the "does this skill ever write to GitHub" question a user might reasonably want answered before running something. Same reasoning that keeps `pr-triage` (advisory-only) separate from anything that would actually merge or push.

## Why dedup keys on file path + keyword overlap, not the doc's own finding IDs

Neither source doc's identifiers survive the way a fingerprint needs to. `PROJECT_REVIEW.md` is explicitly disposable — the user may delete or regenerate it, and `/project-review`'s own finding IDs (`F1`, `F2`, ...) aren't guaranteed stable across a full regeneration beyond what its own git-history scan reconstructs for *its own* numbering purposes, not for cross-referencing GitHub issues. `/code-review` reports don't have stable IDs at all — ordinals reset on `--refresh`, and the reports themselves are gitignored, never entering git history. File path is durable (survives doc regeneration/deletion entirely); keywords pulled from literal code identifiers are far more reproducible across reruns than free-text descriptions, which is why the combination is the fingerprint instead of either doc's own ID scheme.

The marker still *records* the finding ID (`finding_id:`), which is not a contradiction: writing down which report row filed an issue is cheap and useful for cross-referencing (three identifier spaces — PR number, issue number, finding ID — are easy to conflate when reading a `/pr-triage` table), whereas *matching* on it would silently mis-dedup the moment a report regenerates with different numbering. Recorded, displayed, never matched on.

## Why labels are shared across both source tools instead of two separate taxonomies

A repo accumulates issues from both tools over time, and label-based filtering ("show me all `severity: High` issues") should mean one consistent thing regardless of which tool a given issue came from. That's why `/code-review`'s IDIOM tier was changed to carry a derived severity alongside its category (see the companion change in `code-review/SKILL.md`) rather than staying a fourth peer of HIGH/MEDIUM/LOW — and why `Correctness & memory safety` was added as a new category rather than stretching an existing one (like `Performance & resource hygiene`) to loosely cover memory-safety bugs it wasn't designed to describe.

## Why the category vocabulary is a living baseline, not a closed set

The first real run against `t` (16 findings) already produced 2 findings whose best category — "Data integrity", "Robustness" — didn't fit any of the original 11 `/project-review` dimensions, and forcing them into the closest existing one (`Correctness & memory safety`, which was scoped around code-review's memory-leak/crash/UAF HIGH tier) actively made the label less accurate. A vocabulary invented once, in advance, before seeing real findings, will keep being wrong at the margins at some steady rate — closing it defensively just means bad fits accumulate instead. Favoring reuse but allowing a genuinely new category (checked against this repo's existing labels first, so near-synonyms like "Data integrity" and "Data consistency" collapse into one label rather than forking) keeps precision without letting the vocabulary drift unconstrained. If it ever does get messy across many repos/runs, a future `/make-issues reorganize` subcommand (not built yet) could holistically re-cluster and merge near-duplicate categories — noted here as the intended escape valve rather than something to design preemptively.

## Limitations

- Dedup is best-effort. A file rename/move breaks the fingerprint's most reliable signal (falls back to keyword-only matching, weaker). Occasional duplicate issue creation is expected, not a failure.
- Category classification (for code-review findings, and now for any genuinely-new category) is an LLM judgment call, not a deterministic lookup — expect occasional misclassification or an occasional near-duplicate category slipping through despite the reuse-check, correctable by hand in GitHub after the fact.
- No auto-closing or auto-updating of issues when the underlying finding later resolves — v1 only creates and backfills.
- No holistic recategorization pass exists yet — if the category vocabulary does drift messy across many runs, that's currently a manual GitHub cleanup, not something this skill can fix in bulk (see the `/make-issues reorganize` note above).

## License

Freely modifiable, no upstream dependency.
