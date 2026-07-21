# `/make-issues` — design

Status: proposed, not yet implemented.

## Problem

`/project-review` produces `docs/reviews/PROJECT_REVIEW.md`, and `/code-review` produces `docs/reviews/code-review_<scope>_<date>.md`, but nothing turns either kind of finding into tracked work. Both docs are explicitly ephemeral — the user may delete/regenerate `PROJECT_REVIEW.md` at will, and `code-review` reports are gitignored by design (never committed at all). Findings need a path into GitHub Issues that:

- doesn't depend on either review doc surviving,
- doesn't create duplicate issues when the same underlying finding reappears in a later, differently-worded regeneration (finding IDs, exact wording, and even line numbers are not stable across runs — see the companion change in `/project-review`'s own `git`-history ID scan),
- applies consistent severity/category/effort labels **shared across both source tools**, not a separate taxonomy per tool,
- and can also retroactively fold in issues that were filed by hand, so they participate in future dedup matching.

## Goals

- Default run reads `docs/reviews/PROJECT_REVIEW.md` and files an issue per finding at Medium severity or above.
- Also works against a `/code-review` report — pass its path explicitly, e.g. `/make-issues docs/reviews/code-review_src_2025-06-04.md` — with source format auto-detected from the file, not a separate flag.
- `--all` flag removes the severity filter (project-review source); for a code-review source, default behavior already processes every finding in the report (see Command surface) since those reports are already pre-curated to ~10 issues.
- `-f <ids>` flag processes only specific findings: `F3 F5 F9`-style IDs for a project-review source, ordinal numbers (`1 3`) for a code-review source.
- Before creating an issue, search for a likely duplicate; auto-create when nothing matches well, pause and ask only when something does.
- Seed severity/category/effort labels into the target repo from a static list vendored in the skill itself, shared identically by both source formats.
- `backfill` subcommand retrofits the same fingerprint onto pre-existing, human-authored issues (open and closed) so they're found by future dedup searches too.

## Non-goals

- **Not a `/project-review` or `/code-review` subcommand.** Both source skills are read-only; this skill mutates GitHub (creates issues, comments on existing ones). Different blast radius, kept as a separate skill — same reasoning as why `pr-triage` and `code-review` stay separate from each other.
- **Not a live LabelKit sync.** The vendored label list, once seeded, is this skill's own source of truth going forward. `PeteRichardson/LabelKit` was only the starting snapshot.
- **Not perfect dedup.** Matching is best-effort (file + category narrowing, then keyword overlap). Occasional duplicate issue creation is an accepted cost, not a bug to eliminate.
- **Not auto-closing or auto-updating issues when a finding later resolves.** v1 only creates and backfills; reconciling "this finding is now RESOLVED, should the issue close?" is a possible future addition, not in scope here.
- **Not resilient to file renames/moves in the fingerprint.** If a file the fingerprint references gets renamed, that issue's dedup entry effectively goes stale (falls back to keyword-only matching, which is weaker). Accepted edge case, not designed around.
- **Not attempting a single unified report parser.** Project-review and code-review formats are different enough (table vs. sections, stable IDs vs. ordinals, different field sets) that the skill branches into two source-specific parsers rather than forcing one schema.

## Design

### Command surface

- `/make-issues [path]` — `path` defaults to `docs/reviews/PROJECT_REVIEW.md`. If `path` is given and matches the `code-review_*.md` naming/frontmatter shape (see Source detection), the skill switches to code-review parsing.
  - **Project-review source**: process every finding with severity Medium, High, or Critical.
  - **Code-review source**: process every finding in the report (no default severity filter — the report is already capped to ~10 curated issues by `/code-review` itself, so a second filtering pass adds little).
- `/make-issues [path] --all` — project-review source: drop the severity filter. Code-review source: no-op (already processes everything), accepted without error for consistency rather than rejected as an invalid flag.
- `/make-issues [path] -f <ids>` — process only the named findings.
  - Project-review source: `F3 F5 F9`-style IDs as they appear in the current doc.
  - Code-review source: ordinal numbers (`1 3`) matching that report's `### N.` headings — scoped to this one file only, not a globally stable identifier the way project-review's IDs are.
  - IDs/ordinals not found are reported and skipped; the rest still run.
- `/make-issues backfill` — scan every issue in the repo (`--state all`, per the user's explicit call to include closed issues) that lacks a fingerprint marker. For each, ask the LLM whether it references specific code in this repo; if yes, infer file(s)/category/keywords and post the fingerprint as a new **comment** (never edit the issue's original body). If the issue isn't code-related (e.g. a feature request with no file references), skip it. Source-agnostic — doesn't touch either review doc.

### Source detection

- **Project-review**: default path, or a file containing a Findings table with an `ID` column (`F1`, `F2`, ...).
- **Code-review**: filename matches `code-review_*.md`, and/or frontmatter is the `git_sha` / `generated_at` / `scope` shape (no `prs`-style array) with `### N. [Issue name]` section headings rather than a table.
- If a path is given that matches neither shape, stop and say so rather than guessing.

### Staleness pre-check

Both source formats carry frontmatter that can be checked against the current working tree before filing anything: project-review's own finding-ID scan already establishes the doc is being read fresh; code-review's `git_sha`/`scope` frontmatter (already present per its own spec, used today by `/project-review`'s Phase 1.5) lets `/make-issues` warn — not block — when a cited file has changed since the report's `git_sha`, since line numbers may have drifted.

### Finding → issue mapping

**Title**: short summary derived from the finding's description (project-review's Description column, or code-review's Issue name / Issue text).

**Body**: source-aware, since the two formats carry different fields:
- *Project-review*: Description, Recommendation, File:Line, Severity, Effort.
- *Code-review*: Issue text, Evidence code snippet, Location, Impact (HIGH tier) or Score breakdown (IDIOM tier: interview knowledge / simplification / scope, plus the idiomatic-alternative comparison already in the report).

Both end with the hidden fingerprint marker (see Dedup). Since the skill authors the whole body for issues it creates, the marker lives directly in the body — no need for the comment-based approach `backfill` uses for human-authored issues.

**Labels**: one `severity:` label, zero or more `category:` labels, and (project-review source only) one `effort:` label — code-review has no effort concept, so that label is simply omitted for code-review-sourced issues.

- *Project-review*: Severity and Effort map directly from their columns. Category: the finding's Category cell is split on `/` first (project-review findings can carry compound categories, e.g. "Architectural decay / dead code", observed directly in the `t` repo's own `PROJECT_REVIEW.md`), and each component becomes its own `category:` label.
- *Code-review*: severity/category are derived, not read directly, since code-review's HIGH/IDIOM/MEDIUM/LOW tiers aren't a direct match to the `severity:`/`category:` split:
  - **IDIOM tier** → always `category: IDIOM`, plus a derived `severity:` from the existing 1–10 importance score: **≥ 7 → High, otherwise → Medium** (never Low — mirrors `/project-review`'s own rule that IDIOM findings carry a Medium floor regardless of raw impact). This requires a companion edit to `code-review`'s report template so the derived severity is computed and shown once, in the report itself, rather than `make-issues` silently re-deriving a threshold that could drift out of sync with `code-review`'s own scoring scale — see "Companion change to `/code-review`" below.
  - **HIGH tier** → `severity: High` (or `severity: Critical` if the finding's own text signals something more severe than code-review's HIGH bar, e.g. active data loss — judgment call). Category is LLM-classified against the shared vocabulary from the finding's free-text description, biased toward `category: Security hygiene` or the new `category: Correctness & memory safety` (see Label seeding) since that's what code-review's HIGH tier is defined to contain.
  - **MEDIUM tier** → `severity: Medium`. Category LLM-classified against the shared vocabulary — code-review's own stated MEDIUM examples map onto existing categories directly enough that a plain description-based classification should land correctly most of the time: missing nil/error checks and incomplete error handling → Error handling & observability; performance bottlenecks → Performance & resource hygiene; high cyclomatic complexity → Architectural decay.
  - **LOW tier** → `severity: Low`. Category LLM-classified — style/naming → Consistency rot; missing comments → Documentation drift.

  This classification is a judgment call, the same way `backfill` already judges human-authored issues — not a rigid per-example lookup table, since code-review's actual finding text varies more than its four category-example lists suggest.

### Label seeding

Vendored table, 21 labels total (12 category + 4 severity + 3 effort + 2 source), matching the combined closed vocabulary of `/project-review`'s Phase 2 dimensions and `/code-review`'s severity/IDIOM tiers. This is the union of `PeteRichardson/LabelKit`'s original 15 labels, the 3 gaps identified against `/project-review` alone (`category: Performance & resource hygiene`, `category: Security hygiene`, `severity: Critical`), one further gap identified by extending to `/code-review` (`category: Correctness & memory safety` — covers memory safety, crashes/deadlocks, and severe correctness bugs that don't fit any existing category), and a new `source:` pair so issues stay filterable by which tool produced them:

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

Because category/severity/effort are closed vocabularies (now spanning both source skills' own SKILL.md definitions), this table should need no runtime additions in practice. Before creating any issue, the skill still checks the target repo has all 21 (`gh label list`) and creates any missing ones (`gh label create`) as a defensive fallback — cheap, and the same self-healing posture already adopted for `/project-review`'s finding-ID scan, protecting against a future edit to either dimension list rather than anything expected to fire today.

### Companion change to `/code-review`

`code-review/SKILL.md`'s "Issue Categories & Importance" section currently lists HIGH / IDIOM / MEDIUM / LOW as four peers on one axis. To let `/make-issues` apply consistent labels, IDIOM needs to be treated the way `/project-review` already treats it: a **category**, orthogonal to severity, with severity derived from its score rather than being a tier itself.

Concrete change: when an IDIOM issue is scored, also compute and display its derived severity in the report — **≥ 7/10 → High, otherwise → Medium** (never Low, matching the Medium floor `/project-review` already applies to its own IDIOM category). Update the report heading template for IDIOM entries only:

```
### N. [Issue name] (IDIOM) — Severity: High — Importance: 8/10
```

MEDIUM/HIGH/LOW entries are unchanged — their tier name already directly is their severity, no derivation needed. Also lightly reword the "Issue Categories & Importance" intro to state the two-axis model explicitly (severity: HIGH/MEDIUM/LOW; category: IDIOM is one recognized category among others, scored separately) so a human reading the doc isn't misled by the old flat framing either.

### Dedup / fingerprinting

Marker format, an HTML comment (invisible in rendered GitHub UI), identical regardless of source:

```html
<!-- project-review-finding
source: project-review
file: Sources/t/EisenhowerConsoleView.swift
category: Architectural decay
keywords: leftMaxWidth, rightMaxWidth, EisenhowerConsoleView, Priority, quadrant mapping, hardcoded array
-->
```

- **Storage location**: body, for issues this skill creates (it owns the whole body). New comment, for issues `backfill` retrofits (never touches the original human-authored body).
- **Search**: `gh issue list --search "<file path>" --state all` — includes closed issues, consistent with `backfill` also covering closed issues (a closed "fixed" issue reappearing as a live finding is meaningful signal, not noise to filter out).
- **Scoring**: for every candidate the file-path search returns, extract keywords from the *new* finding the same way the marker's keywords were originally produced (literal identifiers/symbol names the finding cites, plus a couple of concept terms), then score plain Jaccard overlap (`|intersection| / |union|`) against the candidate's stored keyword list. No embeddings or fuzzy-matching library — deliberately simple and inspectable, since the keywords are literal tokens rather than free prose. Source-independent: a project-review finding and a code-review finding pointing at the same file/symbols should still match each other.
- **Selection**: sort candidates by score descending. Show only the top result, plus any others within a small delta of it (a real tie) — not every candidate. Below a low floor (~20% overlap) with nothing else close, skip straight to auto-create.
- **Pause UX**: when a likely match exists, pause and show its title, direct issue URL (so it can be opened in a browser to compare), and the overlap score, then ask whether to create anyway or skip. When nothing clears the floor, create without pausing.

### Backfill mechanics

1. `gh issue list --state all --json number,title,body,comments,...` for the whole repo.
2. For each issue with no fingerprint marker in its body or any comment: ask the LLM to determine whether it references specific code in this repo, and if so, its likely file(s), one or more categories from the closed (now 12-entry) vocabulary, and keywords.
3. Skip issues that don't look code-related — not forcing every issue into this scheme.
4. Post a new comment containing the fingerprint marker for everything else, with `source:` omitted or set to `backfill` (it wasn't produced by either review tool).

### Error handling

- Given path (or the default `PROJECT_REVIEW.md`) missing → tell the user to run `/project-review` (or point at a valid `/code-review` report) first; stop rather than guessing at findings.
- Given path matches neither known source shape → stop and say so rather than guessing which parser to use.
- `gh` unauthenticated or API errors → surface and stop; no silent retry loops.
- A finding's File:Line no longer matches current source (file edited since the review ran) → not validated against the working tree; it's carried through as descriptive text in the issue body only, never blocks issue creation. The staleness pre-check (above) is a warning, not a hard gate.
- `-f`/ordinal naming an ID not present in the current doc → report it as skipped, continue with the rest.

### Testing / validation plan

This is a protocol document, not code — "testing" means a real dry run before trusting the default bulk-create flow, for **both** source formats:

1. Project-review: the `t` repo already has a live `PROJECT_REVIEW.md` (F1–F16) from this session; run `/make-issues -f F1` first and confirm label creation, body/marker formatting, and that a second run against the same finding correctly detects the duplicate via the search+scoring path.
2. Code-review: generate a fresh `/code-review` report against a real scope (e.g. `t`'s `Sources/`), confirm the IDIOM severity-derivation change renders correctly in the report itself, then run `/make-issues <path> -f 1` against one HIGH or MEDIUM finding and one IDIOM finding, confirming both label sets (including the derived-severity IDIOM case) come out right before trusting the bulk flow.

## Open questions

- Should a match against a **closed "wontfix"** issue be surfaced differently from a match against a closed "fixed" one during the pause-and-confirm step (e.g. an explicit "this was already rejected" note)? Not structurally required — can be a wording difference in the confirm prompt decided at implementation time rather than a design fork now.
- HIGH-tier code-review findings that read as more severe than code-review's own bar (e.g. active data loss) may warrant `severity: Critical` instead of `severity: High` — left as an LLM judgment call rather than a rule, since code-review itself has no Critical concept to key off of.
