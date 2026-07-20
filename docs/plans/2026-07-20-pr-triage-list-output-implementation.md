# `/pr-triage list` Output Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `pr-triage/SKILL.md` so `/pr-triage list` shows real per-PR detail (title, critical marker, link, resolution) instead of bare counts, and so full-queue repeat runs pick up newly-opened critical PRs.

**Architecture:** This is a single Markdown file of natural-language protocol instructions, not application code — there is no compiler or test runner to catch mistakes, so every edit must be checked by literally re-reading the new prose as an executor would and, where possible, tracing it against concrete fixture data. Four sections of `pr-triage/SKILL.md` change: the frontmatter-schema/writer instructions (Phase 5), the `list` subcommand (Phase 0), the repeat-run reconciliation rule, and the human-facing docs below the `---` divider. No other skill file changes.

**Tech Stack:** Markdown + YAML frontmatter, interpreted by Claude Code at `/pr-triage` invocation time. Live data comes from the `gh` CLI. No build/lint/test tooling exists in this repo (see `AGENTS.md`) — verification is fixture-and-trace based, not automated.

## Global Constraints

- Never merge, push, rebase, or force-push anything — this skill only reads (`gh pr list`, `gh pr diff`, `git log`) and writes under `.claude/tmp/pr-triage/` (existing Rules section, must not regress).
- `list` (and `clean`) must keep making exactly **one** `gh pr list` call per invocation, never one call per file (existing principle, restated in the approved spec's Goals).
- No ANSI color codes or OSC 8 hyperlinks anywhere in `list`'s output — confirmed by direct testing on 2026-07-20 that response-text escape codes always render as literal garbage, and Bash-tool-routed escape codes require a manual, non-sticky `Ctrl+O` per invocation with no way to force it open (see `docs/specs/2026-07-20-pr-triage-list-output-design.md` Non-goals). Plain absolute paths and URLs only.
- The approved spec's frontmatter schema (`generated` + ordered `prs: [{number, critical}]`) is fixed — do not add fields to it (see Task 3 below for how the repeat-run skip-optimization is achieved without a new field).
- There is exactly one pre-existing `.claude/tmp/pr-triage/*.md` report file anywhere using the old flat-array (`prs: [7, 8, 12]` + top-level `critical: <count>`) format. This design carries no backward-compatibility logic for it — per the approved spec, the user deletes that file by hand. Not a task in this plan; just don't let old-format handling creep into any task below.
- Any fixture directories created for verification are scratch and must never be committed — create them outside this repo (e.g. under `/tmp` or the session scratchpad), never under `claude-skills/.claude/tmp/`.
- Commit convention: `feat(pr-triage): ...` / `docs(pr-triage): ...`, scoped to the skill directory (per `AGENTS.md` Commits section).
- Line numbers cited below (e.g. `SKILL.md:27-34`) are accurate against the file as of this plan's writing, before any task below has run. Earlier tasks add lines, which shifts line numbers for everything after them. Match by the literal quoted old text, not by line number, when a later task's target has moved.

---

### Task 1: Frontmatter schema + Phase 5 writer instructions

**Files:**
- Modify: `pr-triage/SKILL.md:96-106`

**Interfaces:**
- Produces: the frontmatter shape every later task (2 and 3) reads — `generated: <ISO 8601>` plus an ordered `prs` array of `{number: <int>, critical: <bool>}` objects, order = Phase 3/severity-override recommended merge sequence, entries never removed once added.

- [ ] **Step 1: Replace the frontmatter block and its explanatory sentence**

  In `pr-triage/SKILL.md`, replace this exact text (currently lines 96–106):

  ```
  Then write `.claude/tmp/pr-triage/<filename>`, starting with a YAML frontmatter block so `list` can report status without re-parsing the whole report:

  ```yaml
  ---
  generated: <ISO 8601 timestamp>
  prs: [7, 8, 12]
  critical: 1
  ---
  ```

  `prs` is the full list of PR numbers this snapshot covers; `critical` is the count promoted via the severity override in Phase 3's tiebreaker logic. Then the body:
  ```

  with:

  ```
  Then write `.claude/tmp/pr-triage/<filename>`, starting with a YAML frontmatter block so `list` can report status without re-parsing the whole report:

  ```yaml
  ---
  generated: <ISO 8601 timestamp>
  prs:
    - number: 7
      critical: false
    - number: 8
      critical: true
    - number: 12
      critical: false
  ---
  ```

  `prs` is an ordered array covering every PR this snapshot tracks, one entry per PR, in the Phase 3/severity-override recommended merge order (order is irrelevant for entries that later merge or close — `list` re-sorts those by resolution date instead, see Phase 0). `critical` on each entry records whether Phase 3's severity override promoted that PR — set it once at write time from Phase 3's own determination, never recomputed from anything else. Entries are never removed from `prs`, even after the PR merges or closes — see Repeat-run mode below for why. Then the body:
  ```

- [ ] **Step 2: Trace the new block against a concrete example**

  Work through this by hand and confirm each line holds before moving on:

  - A full-queue run triaging PRs #7, #8, #12, where Phase 3 promoted #8 to the critical tier and #7, #12 stayed in the normal pool, in recommended order #8 (critical, merges first per severity override), #12, #7 (blast-radius order among the rest) → the `prs` array must read:
    ```yaml
    prs:
      - number: 8
        critical: true
      - number: 12
        critical: false
      - number: 7
        critical: false
    ```
  - Confirm nothing else in Phase 5 (the Summary table, Recommended merge sequence, Severity overrides section) needs to change — they already describe the same Phase 3 data in prose/table form and don't reference the old flat `prs`/`critical` frontmatter fields anywhere in their own text. Read `pr-triage/SKILL.md:106-113` and confirm this directly (no edit needed there).

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/pete/projects/claude-skills
  git add pr-triage/SKILL.md
  git commit -m "feat(pr-triage): store prs as ordered {number, critical} entries in frontmatter"
  ```

---

### Task 2: Rewrite the `/pr-triage list` subcommand

**Files:**
- Modify: `pr-triage/SKILL.md:27-34`

**Interfaces:**
- Consumes: Task 1's frontmatter shape — `generated` (ISO 8601 string) and `prs: [{number: int, critical: bool}]`.
- Produces: the exact output format later verified against `docs/specs/2026-07-20-pr-triage-list-output-design.md`'s sample block — filename/timestamp/path header line, an **Outstanding** group, an optional `---` separator, a **Merged/closed** group, no color, no OSC 8.

- [ ] **Step 1: Replace the `list` bullet**

  In `pr-triage/SKILL.md`, replace this exact text (currently lines 27–34, the entire `list` bullet through "Stop here; don't run a triage."):

  ```
  * **`/pr-triage list`** — for every file in `.claude/tmp/pr-triage/` (create the directory first if absent — an empty listing isn't an error), read its frontmatter (`prs`, `critical`, `generated`) rather than the full report. Then make **one** `gh pr list --state all --json number,state` call covering the union of every `prs` array across all files, and classify each file's PRs as merged/closed vs still open against that single result — don't make a separate API call per file. Report each file as:

    ```
    PR_TRIAGE-7-8-12.md   3 PRs, 1 critical, 1 merged, 2 outstanding [#7, #8]
    PR_TRIAGE.md          5 PRs, 0 critical, 3 merged, 2 outstanding [#9, #14]
    ```

    Sort newest-generated first (from the frontmatter `generated` timestamp, not file mtime — mtime can be misleading if files are ever copied or touched). If a file has no frontmatter (e.g. hand-edited or from an older version of this skill), fall back to filename and last-modified time only, and note it's missing status. Stop here; don't run a triage.
  ```

  with:

  ```
  * **`/pr-triage list`** — for every file in `.claude/tmp/pr-triage/` (create the directory first if absent — an empty listing isn't an error), read its frontmatter (`prs`, `generated`) rather than the full report. Then make **one** `gh pr list --state all --json number,state,title,url,mergedAt,closedAt` call covering the union of every `prs[].number` across all files, and classify each file's PRs against that single result — don't make a separate API call per file. Titles and URLs come from this live call, not from the report body, so a since-renamed PR still shows its current title.

    For each file, print the filename, its `generated` timestamp, and its resolved absolute path on one line, then two groups below it — always both shown in full, no flag to hide either:

    ```
    PR_TRIAGE-7-8.md  (generated 2026-07-18 14:32)  /Users/pete/project/.claude/tmp/pr-triage/PR_TRIAGE-7-8.md
        #8  ‼ Add rate limiting to /api/upload       https://github.com/org/repo/pull/8
        #7    Fix login redirect loop                https://github.com/org/repo/pull/7
        ---
        #5  ‼ Fix data loss on export bug            merged 2026-07-19  https://github.com/org/repo/pull/5
        #9    Old experimental sync flag             closed 2026-07-16  https://github.com/org/repo/pull/9
        #3    Add CSV export                         merged 2026-07-15  https://github.com/org/repo/pull/3
    ```

    - **Outstanding** (PRs the live result doesn't report as `MERGED` or `CLOSED`): one line per entry, in `prs` array order (the file's recommended-merge order), prefixed with `‼` when that entry's frontmatter `critical` is `true`, unprefixed otherwise. No color — plain text only.
    - A `---` separator line, only if both groups are non-empty.
    - **Merged/closed**: one line per entry, newest resolution first — sort by `mergedAt` for PRs the live result reports as `MERGED`, by `closedAt` for `CLOSED`. Same `‼` prefix convention, driven by the frontmatter `critical` flag, so a PR that was critical keeps that marker after it resolves. Each line ends with `merged <date>` or `closed <date>` per the live result's own `state` field — `CLOSED` is "abandoned without merging," never fold it into a `merged` count.
    - Each `#N Title` line ends with the PR's plain `url` from the live result — plain text, not a rendered hyperlink. (Raw OSC 8 codes in response text render as literal garbage rather than a clickable link — see Global Constraints.)
    - If a file's `prs` array is empty, print just its filename/timestamp/path line — no separator, no empty group headers.

    Sort files newest-generated first (from the frontmatter `generated` timestamp, not file mtime — mtime can be misleading if files are ever copied or touched). If a file has no frontmatter (e.g. hand-edited or from an older version of this skill), fall back to filename and last-modified time only, and note it's missing status. Stop here; don't run a triage.
  ```

- [ ] **Step 2: Build fixtures in a scratch directory (not this repo)**

  ```bash
  mkdir -p /tmp/pr-triage-list-test/.claude/tmp/pr-triage
  cd /tmp/pr-triage-list-test
  ```

  Write `.claude/tmp/pr-triage/PR_TRIAGE-7-8.md`:

  ```yaml
  ---
  generated: 2026-07-18T14:32:00Z
  prs:
    - number: 8
      critical: true
    - number: 7
      critical: false
    - number: 5
      critical: true
    - number: 9
      critical: false
    - number: 3
      critical: false
  ---
  ```

  (Body content below the frontmatter doesn't matter for this test — `list` never reads it. Add a single line `Fixture only.` so the file isn't empty.)

- [ ] **Step 3: Write the fixture "live" `gh` result the instructions would have fetched**

  Save this as `/tmp/pr-triage-list-test/fixture-gh-result.json` — this stands in for the output of `gh pr list --state all --json number,state,title,url,mergedAt,closedAt` for PRs #3, #5, #7, #8, #9, so the test doesn't depend on any real GitHub repo:

  ```json
  [
    {"number": 8, "state": "OPEN", "title": "Add rate limiting to /api/upload", "url": "https://github.com/org/repo/pull/8", "mergedAt": null, "closedAt": null},
    {"number": 7, "state": "OPEN", "title": "Fix login redirect loop", "url": "https://github.com/org/repo/pull/7", "mergedAt": null, "closedAt": null},
    {"number": 5, "state": "MERGED", "title": "Fix data loss on export bug", "url": "https://github.com/org/repo/pull/5", "mergedAt": "2026-07-19T10:00:00Z", "closedAt": null},
    {"number": 9, "state": "CLOSED", "title": "Old experimental sync flag", "url": "https://github.com/org/repo/pull/9", "mergedAt": null, "closedAt": "2026-07-16T09:00:00Z"},
    {"number": 3, "state": "MERGED", "title": "Add CSV export", "url": "https://github.com/org/repo/pull/3", "mergedAt": "2026-07-15T08:00:00Z", "closedAt": null}
  ]
  ```

- [ ] **Step 4: Dispatch a fresh agent to execute the new `list` instructions against the fixture**

  Use the `Agent` tool (`subagent_type: "general-purpose"`) with this prompt:

  > Read `/Users/pete/projects/claude-skills/pr-triage/SKILL.md`, find the `/pr-triage list` bullet in Phase 0, and follow its instructions exactly against this fixture. The file to report on is `/tmp/pr-triage-list-test/.claude/tmp/pr-triage/PR_TRIAGE-7-8.md` — read its frontmatter directly. Instead of actually calling `gh`, use the fixed JSON at `/tmp/pr-triage-list-test/fixture-gh-result.json` as if it were that call's result. Produce exactly the output `list` would print for this one file — nothing else, no commentary. Return only that output text.

- [ ] **Step 5: Diff the agent's output against the expected block**

  Expected output (order and spacing matter — the fixture's `prs` array order is #8, #7, #5, #9, #3, so outstanding keeps that order and merged/closed sorts by resolution date descending):

  ```
  PR_TRIAGE-7-8.md  (generated 2026-07-18 14:32)  /tmp/pr-triage-list-test/.claude/tmp/pr-triage/PR_TRIAGE-7-8.md
      #8  ‼ Add rate limiting to /api/upload       https://github.com/org/repo/pull/8
      #7    Fix login redirect loop                https://github.com/org/repo/pull/7
      ---
      #5  ‼ Fix data loss on export bug            merged 2026-07-19  https://github.com/org/repo/pull/5
      #9    Old experimental sync flag             closed 2026-07-16  https://github.com/org/repo/pull/9
      #3    Add CSV export                         merged 2026-07-15  https://github.com/org/repo/pull/3
  ```

  If the agent's output diverges (wrong order, missing `‼`, a `MERGED`/`CLOSED` PR miscounted, or any escape code present), the Step 1 prose is ambiguous at that exact point — fix the wording in `pr-triage/SKILL.md` and repeat Steps 4–5. Don't move on with a known mismatch.

- [ ] **Step 6: Clean up the fixture**

  ```bash
  rm -rf /tmp/pr-triage-list-test
  ```

- [ ] **Step 7: Commit**

  ```bash
  cd /Users/pete/projects/claude-skills
  git add pr-triage/SKILL.md
  git commit -m "feat(pr-triage): show per-PR titles, links, and critical markers in list output"
  ```

---

### Task 3: Full-queue repeat runs re-enumerate and skip unchanged PRs

**Files:**
- Modify: `pr-triage/SKILL.md:124-126`

**Interfaces:**
- Consumes: Task 1's frontmatter — specifically the file's own `generated` timestamp (no new field is added to support this task; see Global Constraints).
- Produces: the rule Phase 1 (already fetches `updatedAt` per PR at `pr-triage/SKILL.md:44`, unchanged) and Phase 2/4 must follow on a repeat run — re-enumerate on full-queue runs, and skip re-diffing a PR whose live `updatedAt` is not later than the file's `generated`.

- [ ] **Step 1: Replace the Repeat-run mode section**

  Replace this exact text (currently lines 124–126):

  ```
  ## Repeat-run mode

  If a file matching the current invocation's scope already exists in `.claude/tmp/pr-triage/` (`PR_TRIAGE.md` for a full run, `PR_TRIAGE-<numbers>.md` for a scoped run), read it first. Mark PRs no longer open as `MERGED` or `CLOSED`, re-rank the remaining queue against the current base, and note which recommendations changed since the last run and why (usually: a merge happened, or a PR was updated). A full-queue run and a scoped run are tracked separately — don't treat one as a substitute for the other's history.
  ```

  with:

  ```
  ## Repeat-run mode

  If a file matching the current invocation's scope already exists in `.claude/tmp/pr-triage/` (`PR_TRIAGE.md` for a full run, `PR_TRIAGE-<numbers>.md` for a scoped run), read it first. Mark PRs no longer open as `MERGED` or `CLOSED`, re-rank the remaining queue against the current base, and note which recommendations changed since the last run and why (usually: a merge happened, or a PR was updated). A full-queue run and a scoped run are tracked separately — don't treat one as a substitute for the other's history.

  **Full-queue repeat runs** (`PR_TRIAGE.md`) always re-run Phase 1 in full — re-enumerate every currently-open PR rather than trusting the existing file's `prs` array, since a critical PR opened after the last run must not stay invisible until the next fresh (non-repeat) triage. Any PR Phase 1 returns that isn't already in the file's `prs` array is new: give it the full Phase 2–4 treatment (diff, overlap, severity check). For a PR already in `prs`, compare its live `updatedAt` (from this same Phase 1 call) against the file's own frontmatter `generated` timestamp — if `updatedAt` is not later than `generated`, nothing about that PR has changed since this snapshot was written, so skip re-diffing it in Phase 2/4 and reuse its last-known overlap and severity classification. Cost scales with the number of genuinely new or since-updated PRs, not the full queue.

  **Scoped repeat runs** (`PR_TRIAGE-<numbers>.md`) stay locked to the PR numbers already in the file's `prs` array — this mode exists specifically so the user can burn down a chosen subset without new PRs jumping the queue. Don't re-enumerate beyond those numbers.
  ```

- [ ] **Step 2: Trace the skip-optimization against a concrete example**

  Work through this by hand and confirm it holds:

  - `PR_TRIAGE.md` has `generated: 2026-07-18T14:32:00Z` and `prs` includes `{number: 7, critical: false}`.
  - A repeat run's Phase 1 call returns PR #7 with `updatedAt: 2026-07-10T00:00:00Z` (before `generated`) → `updatedAt` is not later than `generated`, so #7 is skipped in Phase 2/4 and its stored overlap/severity data is reused.
  - The same repeat run returns PR #14, not present in the file's `prs` at all → #14 is new, gets full Phase 2–4 treatment regardless of any timestamp.
  - The same repeat run returns PR #8 (already in `prs`) with `updatedAt: 2026-07-19T00:00:00Z` (after `generated`) → #8 got updated since the snapshot, so it is **not** skipped; it goes through Phase 2–4 again.
  - Confirm Phase 1's existing `gh pr list` call (`pr-triage/SKILL.md:44`) already requests `updatedAt` — re-read that line and confirm no field needs adding there.

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/pete/projects/claude-skills
  git add pr-triage/SKILL.md
  git commit -m "feat(pr-triage): re-enumerate and skip-unchanged on full-queue repeat runs"
  ```

---

### Task 4: Update human-facing docs to match

**Files:**
- Modify: `pr-triage/SKILL.md:3` (frontmatter `description`)
- Modify: `pr-triage/SKILL.md:179-184` (Usage section `list` example)

**Interfaces:**
- Consumes: Task 2's exact output format (reused verbatim as the doc example).
- Produces: nothing consumed elsewhere — this is the last task.

- [ ] **Step 1: Update the frontmatter `description`**

  Replace this exact substring on line 3:

  ```
  Supports `/pr-triage list` (with per-file status: PR count, critical count, merged vs. outstanding), `/pr-triage open`, and `/pr-triage clean` [--all] to find and tidy up past runs.
  ```

  with:

  ```
  Supports `/pr-triage list` (per-file breakdown of outstanding vs. merged/closed PRs, each with title and link), `/pr-triage open`, and `/pr-triage clean` [--all] to find and tidy up past runs.
  ```

- [ ] **Step 2: Update the Usage section's `list` example**

  Replace this exact text (currently lines 179–184):

  ```
  `list` shows each snapshot's status at a glance — PR count, critical-override count, and how many of its PRs have since merged vs. are still outstanding:

  ```
  PR_TRIAGE-7-8-12.md   3 PRs, 1 critical, 1 merged, 2 outstanding [#7, #8]
  PR_TRIAGE.md          5 PRs, 0 critical, 3 merged, 2 outstanding [#9, #14]
  ```
  ```

  with:

  ```
  `list` shows each snapshot's outstanding and merged/closed PRs at a glance — title, critical marker, and link — without opening the file:

  ```
  PR_TRIAGE-7-8.md  (generated 2026-07-18 14:32)  /Users/pete/project/.claude/tmp/pr-triage/PR_TRIAGE-7-8.md
      #8  ‼ Add rate limiting to /api/upload       https://github.com/org/repo/pull/8
      #7    Fix login redirect loop                https://github.com/org/repo/pull/7
      ---
      #5  ‼ Fix data loss on export bug            merged 2026-07-19  https://github.com/org/repo/pull/5
      #9    Old experimental sync flag             closed 2026-07-16  https://github.com/org/repo/pull/9
      #3    Add CSV export                         merged 2026-07-15  https://github.com/org/repo/pull/3
  ```
  ```

- [ ] **Step 3: Read the whole file once more, end to end**

  Confirm no other passage still references the old flat `prs: [7, 8, 12]` / top-level `critical: <count>` schema, or the old count-only `list` summary line format. In particular re-check `pr-triage/SKILL.md`'s Phase 5 body bullets (around line 108–113) and the "Not yet implemented" note (around line 197) — neither should need a change, but confirm rather than assume.

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/pete/projects/claude-skills
  git add pr-triage/SKILL.md
  git commit -m "docs(pr-triage): update list example and description for new output format"
  ```

---

## Self-review notes (completed during planning, kept for the record)

- **Spec coverage:** every Goal in `docs/specs/2026-07-20-pr-triage-list-output-design.md` maps to a task — frontmatter schema (Task 1), output format incl. no-color/no-OSC8 (Task 2), single-`gh`-call principle (Task 2, restated), full-queue repeat-run discovery (Task 3), docs (Task 4). The `view` subcommand and `clean`→`prune` rename are explicit Non-goals/Observations in the spec and correctly have no task here.
- **Gap found and resolved during planning:** the spec's Repeat-run section says PRs with an unchanged `updatedAt` "can skip re-diffing," but the approved frontmatter schema stores no prior `updatedAt` to compare against. Resolved without reopening the approved schema: compare the live `updatedAt` against the file's existing `generated` timestamp instead (Task 3) — if the PR hasn't been touched since the snapshot was written, it hasn't changed, full stop.
- **Type/shape consistency:** the `prs` entry shape `{number, critical}` introduced in Task 1 is the exact shape Task 2 and Task 3 read (`prs[].number`, `prs[].critical`) — no renamed fields between tasks.
