# `/make-issues` — design

Status: proposed, not yet implemented.

## Problem

`/project-review` produces `docs/reviews/PROJECT_REVIEW.md`, but nothing turns those findings into tracked work. The doc itself is explicitly ephemeral — the user may delete it if it goes stale, if they stop trusting it, or just to start fresh (this already happened once in the `t` repo). Findings need a path into GitHub Issues that:

- doesn't depend on the review doc surviving,
- doesn't create duplicate issues when the same underlying finding reappears in a later, differently-worded regeneration of the doc (finding IDs, exact wording, and even line numbers are not stable across runs — see the companion change in `/project-review`'s own `git`-history ID scan),
- applies consistent severity/category/effort labels,
- and can also retroactively fold in issues that were filed by hand, so they participate in future dedup matching.

## Goals

- Default run reads `docs/reviews/PROJECT_REVIEW.md` in the current repo and files an issue per finding at Medium severity or above.
- `--all` flag removes the severity filter.
- `-f F3 F5 F9` flag processes only the named finding IDs from the current doc.
- Before creating an issue, search for a likely duplicate; auto-create when nothing matches well, pause and ask only when something does.
- Seed severity/category/effort labels into the target repo from a static list vendored in the skill itself.
- `backfill` subcommand retrofits the same fingerprint onto pre-existing, human-authored issues (open and closed) so they're found by future dedup searches too.

## Non-goals

- **Not a `/project-review` subcommand.** `/project-review` is read-only; this skill mutates GitHub (creates issues, comments on existing ones). Different blast radius, kept as a separate skill — same reasoning as why `pr-triage` and `code-review` stay separate from each other.
- **Not a live LabelKit sync.** The vendored label list, once seeded, is this skill's own source of truth going forward. `PeteRichardson/LabelKit` was only the starting snapshot.
- **Not perfect dedup.** Matching is best-effort (file + category narrowing, then keyword overlap). Occasional duplicate issue creation is an accepted cost, not a bug to eliminate.
- **Not auto-closing or auto-updating issues when a finding later resolves.** v1 only creates and backfills; reconciling "this finding is now RESOLVED, should the issue close?" is a possible future addition, not in scope here.
- **Not resilient to file renames/moves in the fingerprint.** If a file the fingerprint references gets renamed, that issue's dedup entry effectively goes stale (falls back to keyword-only matching, which is weaker). Accepted edge case, not designed around.

## Design

### Command surface

- `/make-issues` — read `docs/reviews/PROJECT_REVIEW.md`; process every finding with severity Medium, High, or Critical.
- `/make-issues --all` — process every finding regardless of severity.
- `/make-issues -f F3 F5 F9` — process only the named IDs. IDs not found in the current doc are reported and skipped; the rest still run.
- `/make-issues backfill` — scan every issue in the repo (`--state all`, per the user's explicit call to include closed issues) that lacks a fingerprint marker. For each, ask the LLM whether it references specific code in this repo; if yes, infer file(s)/category/keywords and post the fingerprint as a new **comment** (never edit the issue's original body). If the issue isn't code-related (e.g. a feature request with no file references), skip it.

### Finding → issue mapping

- **Title**: short summary derived from the finding's Description.
- **Body**: Description, Recommendation, File:Line citation, Severity, Effort, followed by the hidden fingerprint marker (see below). Since the skill authors the whole body for issues it creates, the marker lives directly in the body — no need for the comment-based approach backfill uses for human-authored issues.
- **Labels**: one `severity:` label, one `effort:` label, and one or more `category:` labels. A finding's Category cell is split on `/` first — `/project-review` findings can carry compound categories (e.g. "Architectural decay / dead code", observed directly in the `t` repo's `PROJECT_REVIEW.md`), and each component becomes its own `category:` label on the issue.

### Label seeding

Full vendored table, 18 labels total (11 category + 4 severity + 3 effort), matching `/project-review`'s own closed Phase 2 dimension list / severity scale / effort scale. This is the union of `PeteRichardson/LabelKit`'s existing 15 labels plus the 3 identified gaps (`category: Performance & resource hygiene`, `category: Security hygiene`, `severity: Critical`):

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

severity: Critical   #b60205
severity: High        #d73a4a
severity: Medium      #fbca04
severity: Low         #0e8a16

effort: L   #1d76db
effort: M   #5319e7
effort: S   #c5def5
```

Because category/severity/effort are closed vocabularies defined in `/project-review`'s own SKILL.md, this table should need no runtime additions in practice. Before creating any issue, the skill still checks the target repo has all 18 (`gh label list`) and creates any missing ones (`gh label create`) as a defensive fallback — cheap, and it's the same self-healing posture already adopted for `/project-review`'s finding-ID scan, protecting against a future edit to the dimension list rather than anything expected to fire today.

### Dedup / fingerprinting

Marker format, an HTML comment (invisible in rendered GitHub UI):

```html
<!-- project-review-finding
file: Sources/t/EisenhowerConsoleView.swift
category: Architectural decay
keywords: leftMaxWidth, rightMaxWidth, EisenhowerConsoleView, Priority, quadrant mapping, hardcoded array
-->
```

- **Storage location**: body, for issues this skill creates (it owns the whole body). New comment, for issues `backfill` retrofits (never touches the original human-authored body).
- **Search**: `gh issue list --search "<file path>" --state all` — includes closed issues, consistent with `backfill` also covering closed issues (a closed "fixed" issue reappearing as a live finding is meaningful signal, not noise to filter out).
- **Scoring**: for every candidate the file-path search returns, extract keywords from the *new* finding the same way the marker's keywords were originally produced (literal identifiers/symbol names the finding cites, plus a couple of concept terms), then score plain Jaccard overlap (`|intersection| / |union|`) against the candidate's stored keyword list. No embeddings or fuzzy-matching library — deliberately simple and inspectable, since the keywords are literal tokens rather than free prose.
- **Selection**: sort candidates by score descending. Show only the top result, plus any others within a small delta of it (a real tie) — not every candidate. Below a low floor (~20% overlap) with nothing else close, skip straight to auto-create.
- **Pause UX**: when a likely match exists, pause and show its title, direct issue URL (so it can be opened in a browser to compare), and the overlap score, then ask whether to create anyway or skip. When nothing clears the floor, create without pausing.

### Backfill mechanics

1. `gh issue list --state all --json number,title,body,comments,...` for the whole repo.
2. For each issue with no fingerprint marker in its body or any comment: ask the LLM to determine whether it references specific code in this repo, and if so, its likely file(s), one or more categories from the closed vocabulary, and keywords.
3. Skip issues that don't look code-related — not forcing every issue into this scheme.
4. Post a new comment containing the fingerprint marker for everything else.

### Error handling

- `docs/reviews/PROJECT_REVIEW.md` missing → tell the user to run `/project-review` first; stop rather than guessing at findings.
- `gh` unauthenticated or API errors → surface and stop; no silent retry loops.
- A finding's File:Line no longer matches current source (file edited since the review ran) → not validated against the working tree; it's carried through as descriptive text in the issue body only, never blocks issue creation.
- `-f` naming an ID not present in the current doc → report it as skipped, continue with the rest.

### Testing / validation plan

This is a protocol document, not code — "testing" means a real dry run before trusting the default bulk-create flow. The `t` repo already has a live `PROJECT_REVIEW.md` (F1–F16) from this session; run `/make-issues -f F1` (a single finding) first and confirm label creation, body/marker formatting, and that a second run against the same finding correctly detects the duplicate via the search+scoring path, before running the default bulk flow against the rest.

## Open questions

- Should a match against a **closed "wontfix"** issue be surfaced differently from a match against a closed "fixed" one during the pause-and-confirm step (e.g. an explicit "this was already rejected" note)? Not structurally required — can be a wording difference in the confirm prompt decided at implementation time rather than a design fork now.
