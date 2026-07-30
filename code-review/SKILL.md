---
name: code-review
description: Comprehensive code review of a repository scope or a GitHub pull request. Analyzes code across HIGH (security, memory, crashes), IDIOM (language best practices), MEDIUM (inefficiencies), and LOW (style) categories. Issues ranked by importance; all HIGH shown plus top IDIOM+MEDIUM up to 10 total. Reports saved as markdown snapshots in docs/reviews/ (not committed). Use when you want to review a folder/file, pick one issue at a time, and work through them incrementally across multiple sessions. Also use when the user types /code-review 68, /code-review #68, or /code-review PR68, says "review PR 68", "review this pull request", "code review the PR before I merge it", or passes a GitHub pull request URL.
---

# Comprehensive Code Review

Analyze a specified scope of code (folder, file, or pattern) — or the change proposed by a GitHub pull request — and generate a prioritized report of issues, categorized by severity and importance. Reports are session-independent markdown snapshots, allowing you to reference issues by name and work through them incrementally.

## Quick Start

```
/code-review src/          # review a scope of the working tree
/code-review 68            # review what PR #68 proposes
```

Scans the target, generates a report in `docs/reviews/code-review_[TARGET]_YYYY-MM-DD.md`, and displays it.

## Commands

### Scan a scope
```
/code-review [SCOPE]
```

- **SCOPE**: folder path (`src/`), file path (`src/memory.cpp`), glob (`src/**/*.rs`)
- **Output**: Report saved to `docs/reviews/code-review_[SCOPE]_[DATE].md`
- **Display**: Issues printed to console, ready to work through

### Review a pull request
```
/code-review [PR]
```

- **PR**: bare number (`68`), `#`-prefixed (`#68`), `PR`-prefixed (`PR68`), or a full GitHub PR URL
- **Output**: Report saved to `docs/reviews/code-review_PR[N]_[DATE].md`
- **Scope of findings**: only lines the PR added or modified — see [PR mode](#pr-mode) below

Requires `gh` authenticated. The working tree is never touched: nothing is checked out, no branch is created, no worktree is added.

**Mode detection:** a bare integer, `#N`, `PRN`, or a PR URL is always a PR, never a path. If `gh pr view` can't resolve it, say what was tried and stop — don't fall back to treating it as a scope, since that turns an auth or wrong-repo problem into a confusing "no files found" error.

### Focus on specific categories
```
/code-review [SCOPE] --focus [CATEGORY]
```

- `high` — Only HIGH severity issues (security, memory, crashes)
- `idiom` — Only IDIOM issues (language best practices; great for learning)
- `medium` — Only MEDIUM issues (inefficiencies, error handling)
- `low` — Only LOW issues (style, naming)
- `all` — All categories (default)

**Examples:**
```
/code-review src/ --focus idiom      # Language learning sprint
/code-review src/ --focus high       # Security review
```

### Refresh the report
```
/code-review [SCOPE] --refresh
```

Generates a new report with current line numbers. Use when the previous report's line numbers have drifted after several fixes.

In PR mode, `--refresh` re-fetches the PR head — which may have gained commits since the last run — and writes a new dated report against it.

### Continue mid-session
```
I fixed [ISSUE NAME], what's next?
```

Marks the issue as addressed in this session and shows the next unaddressed issue from the report.

**Example:**
```
I fixed the memory leak in Allocator, what's next?
```

### Look up a specific issue
```
Show me [ISSUE NAME] again
```

Retrieves the issue from the saved report and locates it in current code (handles line number drift).

**Example:**
```
Show me the SQL injection in parse_user_id again
```

## PR mode

Everything below this section — tiers, IDIOM scoring, the reporting rule, the report format — is identical in both modes. PR mode differs only in **where the code comes from** and **which lines are eligible to be findings**.

### Gathering the code

```bash
gh auth status                     # hard requirement; stop with a clear message if it fails
gh pr view <n> --json number,title,state,isDraft,author,baseRefName,headRefName,\
                     headRefOid,baseRefOid,additions,deletions,changedFiles,url
git fetch origin pull/<n>/head     # works for fork PRs too; creates no local branch
git merge-base <baseRefOid> <headRefOid>
gh pr diff <n>                     # the hunks
git show <headSha>:<path>          # full-file context, per changed file
```

Read full files for context via `git show` against the fetched sha. Nothing is checked out, so the working tree stays exactly as it was and there's no teardown step to forget.

Diff against the **merge base**, not the base branch tip. Otherwise commits that landed on the base branch after this PR branched get attributed to the PR.

| PR state | What to do |
|---|---|
| Open | Proceed |
| Draft | Proceed; note draft status in the report header |
| Merged or closed | Say so and ask before continuing — legitimate, but usually a mistake |

The 30-file threshold applies to `changedFiles`. Deleted files are reviewed from the diff alone (there's no file at head to read). Skip binaries, lockfiles, and generated files, and **list what was skipped** so the reader knows they weren't silently dropped.

### Which lines can be findings

Report findings only on lines the PR **added or modified**. The point of PR mode is to answer "is this change sound," not to re-litigate the files it happens to touch.

**One exception:** a problem the PR *causes* on a line it didn't touch — a changed function contract that breaks an existing caller, a renamed field an untouched serializer still writes. Report those with an extra `**Introduced by:**` field naming the hunk responsible. A finding on an untouched line without that field is out of scope by definition.

Pre-existing issues on untouched lines aren't ranked and don't consume report slots. List at most **three** of them under **Out of scope (pre-existing)** at the end of the report — name and location only, no evidence blocks. The reader wants to know they were seen and set aside. The cap is what stops that section from growing back into the scope-mode report PR mode exists to avoid.

That section is a pointer, not a work queue: `/make-issues` deliberately skips it, since entries with no tier, severity, or evidence can't become an issue without inventing all three. `/code-review <path>` in scope mode is how one becomes filable.

## Issue Categories & Importance

Two axes, not four peers: **HIGH / MEDIUM / LOW are severity tiers.** **IDIOM is a category** (language-fluency value), scored separately and always reported alongside its own derived severity rather than being a fourth tier on the same axis — this matches how `/project-review` treats IDIOM findings (a category with a Medium severity floor), so a finding filed from either skill gets consistent severity/category labels downstream.

### HIGH (always shown, no filtering)
Critical issues that block shipping or break things:
- Security vulnerabilities (SQL injection, buffer overflows, unauthorized access)
- Memory safety (leaks, use-after-free, dangling pointers)
- Crashes and deadlocks
- Correctness bugs with severe impact

**All HIGH issues are always reported.**

### IDIOM (scored & ranked)
Language idioms and best practices. Not idiomatic code signals knowledge gaps.

**Scored on three dimensions (1–9 points total):**
- **Interview knowledge** (1–3): 1=nice to have, 2=expected, 3=red flag if missing
- **Code simplification** (1–3): 1=slightly cleaner, 2=notably simpler, 3=drastically reduces code
- **Scope & impact** (1–3): 1=single site, 2=reduces bugs, 3=widespread/prevents major issues

**Examples:**
- **RAII in C++**: interview +3 (red flag if missing), simplification +2, impact +3 = **8/10**
- **Optional chaining in Swift**: interview +1, simplification +3, impact +3 = **7/10**

**Derived severity:** every IDIOM finding also gets a severity computed from its total score — **≥ 7/10 → High, otherwise → Medium** (never Low; mirrors `/project-review`'s Medium floor for its own IDIOM category). Show both the category and the derived severity in the report (see Report Structure) so the finding carries the same two labels a `/project-review` finding would.

### MEDIUM (scored & ranked)
Inefficiencies, error handling gaps, edge cases, maintainability issues:
- Missing nil/error checks
- Performance bottlenecks (O(n²) loops, N+1 queries)
- Incomplete error handling
- High cyclomatic complexity

**Scored by scope and impact (2–6 points).**

### LOW (shown if space remains)
Style issues, naming conventions, missing comments. Lowest priority.

### Reporting rule
**All HIGH + top (10 - num_HIGH) IDIOM+MEDIUM by importance score + LOW if room**

Example:
- 5 HIGH issues → all shown (5 slots used)
- Top 5 IDIOM+MEDIUM by score → show next 5
- Total: 10 issues shown
- If <5 IDIOM+MEDIUM exist, fill remainder with LOW issues

## File Storage & Persistence

Reports are saved as **ephemeral markdown files** (not committed to git):

```
docs/
├── .gitignore (contains: reviews/code-review*.md)
└── reviews/
    ├── code-review_src_2025-06-04.md   (initial report)
    ├── code-review_src_2025-06-10.md   (refreshed report)
    ├── code-review_app_2025-06-05.md   (different scope)
    ├── code-review_PR68_2026-07-30.md  (PR mode — same pattern, so also gitignored)
    └── PROJECT_REVIEW.md               (from /project-review — committed, not gitignored)
```

**Key points:**
- Reports are not committed (`docs/reviews/code-review*.md` is gitignored) — this pattern deliberately excludes `PROJECT_REVIEW.md`, which `/project-review` writes to the same directory and which you do want committed and tracked over time
- Issues referenced by **memorable names** (e.g., "Memory leak in Allocator")
- Allows cross-session continuation: come back days later and reference by name
- Each date has a separate report; `/code-review --refresh` generates a new dated report
- Frontmatter (`git_sha`, `generated_at`, `scope`) lets `/project-review` check whether findings are still current before treating them as evidence — see "Integration with /project-review" below
- PR reports add a `pr:` frontmatter key. Its **presence** is the marker meaning "this report describes code that isn't on the base branch yet" — three downstream consumers key on it (see [Report Structure](#report-structure))

## Workflow Example

### Session 1 (Day 1)
```
/code-review src/
```
→ Generates `docs/reviews/code-review_src_2025-06-04.md`
→ Reports 5 HIGH + 5 IDIOM+MEDIUM (highest scoring) + 0 LOW

Pick the first issue:
```
Let's fix the memory leak in Allocator
```
→ You and Claude work through the bug together
→ You implement and commit

Continue:
```
I fixed that one, what's next?
```
→ Shows next issue (SQL injection in parse_user_id)

Repeat for each issue.

### Session 2 (Day 5, new session)
Reference the old report directly:
```
Show me the optional chaining issue again
```
→ Claude reads saved report, locates issue in current code
→ Helps you fix it

```
I fixed that one, what's next?
```
→ Shows next unaddressed issue

After several fixes, line numbers drift:
```
/code-review src/ --refresh
```
→ New report: `docs/reviews/code-review_src_2025-06-10.md`
→ Clean slate with current line numbers

## Report Structure

Reports are markdown with a YAML frontmatter block followed by the findings:

```markdown
---
git_sha: a1b2c3d
generated_at: 2026-07-10T14:32:00-07:00
scope: src/
---

# Code Review: [SCOPE]

**Timestamp:** YYYY-MM-DD
**Issues found:** X HIGH • Y IDIOM • Z MEDIUM • W LOW
**Reporting:** All HIGH + top (10 - num_HIGH) IDIOM+MEDIUM + LOW if needed

## 🔴 HIGH (X issues)

### 1. [Memorable issue name]
**Location:** path/file.ext:LINE
**Severity:** High | **Impact:** [consequence]
**Issue:** [What's wrong]
**Evidence:**
\`\`\`[language]
[Current code snippet]
\`\`\`

[... more HIGH issues ...]

## 🟠 IDIOM + 🟡 MEDIUM (ranked by importance, Y of Z shown)

### N. [Issue name] (MEDIUM) — Importance: S/6
**Location:** path/file.ext:LINE
**Score breakdown:** Scope & impact: +S

### N. [Issue name] (IDIOM) — Severity: High|Medium — Importance: S/10
**Location:** path/file.ext:LINE
**Score breakdown:**
- Interview knowledge: +X
- Code simplification: +X
- Scope & impact: +X

[Show current code AND idiomatic alternative with explanation]

[... more IDIOM+MEDIUM issues ...]

## Summary
- Total files scanned: N
- Next step: Pick one issue by name and ask "Let's fix [issue name]"
- Or file them all: `/make-issues docs/reviews/code-review_[SCOPE]_[DATE].md`
```

### PR mode differences

The structure above is unchanged. PR mode adds three things.

**1. Frontmatter is a superset** of the three scope-mode keys, so every existing consumer keeps working without a new parser:

```yaml
---
git_sha: 9f8e7d6           # the PR head sha — the commit the line numbers refer to
generated_at: 2026-07-30T14:32:00-07:00
scope: PR #68
pr: 68                     # presence of this key marks an unmerged-branch report
pr_base_ref: main
pr_base_sha: 1a2b3c4       # the merge base, not the base branch tip
---
```

`git_sha` must be the **PR head sha**, not local `HEAD`. That's what keeps `/project-review`'s and `/make-issues`' per-file staleness checks pointed at the commit the line numbers were computed against, rather than at a commit that never contained this code.

The header block gains PR title, author, state (marking drafts), and ± line counts.

**2. Findings on untouched lines carry `**Introduced by:**`** naming the hunk responsible:

```markdown
### 3. [Issue name] (MEDIUM) — Importance: S/6
**Location:** path/caller.ext:LINE  *(not modified by this PR)*
**Introduced by:** path/api.ext:LINE — [the change that breaks this]
```

**3. An Out of scope section**, capped at three entries, after the Summary:

```markdown
## Out of scope (pre-existing)

Not introduced by this PR and not counted above:
- [Issue name] — path/file.ext:LINE
- [Issue name] — path/other.ext:LINE
```

## Next in the pipeline

Which stage this skill occupies depends on the mode. **Scope mode is stage 1** (find the work) of the review → issue → PR → merge pipeline (`~/.claude/skills/WORKFLOW.md`), alongside `/project-review`. **PR mode is stage 6** (the line-level pass before merging), so it hands off differently.

### Scope mode

After displaying the report, print the next step as the last line:

> Next: fix one now ("Let's fix [issue name]"), or `/make-issues docs/reviews/code-review_src_2026-07-21.md` to file the whole report as GitHub issues.

Use the real report path, not a placeholder — `/make-issues` needs it verbatim, since only `/project-review`'s report has a default path. Vary it only for these cases:

* **No GitHub remote** — omit the `/make-issues` half; the fix-one-now path still applies.
* **`--focus idiom` run** — mention that IDIOM findings carry a derived severity, so they order alongside everything else once filed rather than landing in a separate bucket.

### PR mode

Point at the branch, not at stage 2 — a finding about a PR is usually cheapest to fix inside that PR:

> Next: fix these on the branch so they land with the PR (`git fetch origin pull/68/head && git checkout -b review-68 FETCH_HEAD`), or `/make-issues docs/reviews/code-review_PR68_2026-07-30.md` for anything you'd rather not block the merge on.

`/make-issues` is the fallback for **ranked** findings that shouldn't hold up the merge. Filing a stage-6 finding as an issue means it comes back around as its own PR later — the right call for genuine scope creep, the wrong one for "this PR has a bug." So lead with the branch.

The **Out of scope (pre-existing)** entries are not filable and `/make-issues` skips them by design: they carry no tier, severity, or evidence, so filing one means inventing all three. If any of them looks worth tracking, add a third line pointing at scope mode for the file in question — `/code-review path/to/file.ext` produces a real finding that `/make-issues` can then file.

## When to use

- **Starting a code review of a new/unfamiliar codebase** — Get a comprehensive overview of all issues
- **Learning a language** — Focus on IDIOM issues (`--focus idiom`)
- **Security review** — Focus on HIGH issues (`--focus high`)
- **Picking up where you left off** — Reference issues by name from saved report
- **Routine code quality checks** — Refresh the review (`--refresh`) after a while
- **Before merging a PR** — `/code-review 68` for the stage-6 line-level pass, with a report you can work from. Use the built-in `/review` instead when you just want a quick prose read and don't need an artifact

## Safety & Limits

### File count threshold
If the specified scope contains more than 30 code files, the skill will ask for confirmation before proceeding. This prevents accidentally scanning huge codebases.

If you see this, either:
- Narrow the scope: `/code-review src/foo/` instead of `/code-review .`
- Use a language filter: `/code-review src/ --language rust`
- Or confirm that you want to scan all files

In PR mode the same threshold applies to the PR's `changedFiles`. There's no narrowing option there — either confirm, or review the PR in parts by asking for specific paths.

### PR mode preconditions
`gh` must be authenticated (`gh auth status`). A PR that can't be resolved stops the run with what was tried. Merged and closed PRs prompt before proceeding.

### Language detection
Auto-detected from file extensions (`.cpp` → C++, `.py` → Python, `.rs` → Rust, etc.)

If the detection is wrong, it can be adjusted in future versions with a `--language [LANG]` flag.

## Implementation Details

The skill works by:

1. **Resolving the target** — PR mode if the argument is `68` / `#68` / `PR68` / a PR URL, scope mode otherwise
2. **Discovering files** — scope mode: files in the scope matching code file extensions. PR mode: the PR's changed files, via `gh pr view` + `git fetch origin pull/<n>/head`
3. **Detecting languages** from file extensions
4. **Checking file count** against the 30-file threshold (PR mode: `changedFiles`)
5. **Reading file contents** and sending to Claude for analysis — scope mode reads the working tree; PR mode reads `git show <headSha>:<path>` plus `gh pr diff` for the hunk boundaries, and never checks anything out
6. **Analyzing via Claude API** using a detailed system prompt that instructs Claude to:
   - Identify all issues in each category (HIGH, IDIOM, MEDIUM, LOW)
   - Score IDIOM issues on three dimensions
   - Rank IDIOM+MEDIUM by composite importance
   - In PR mode, restrict findings to added/modified lines, except those carrying `Introduced by:`
   - Return structured JSON data
7. **Generating markdown report** with ranked issues, prefixed with a frontmatter block recording `git_sha` (scope mode: `git rev-parse HEAD`; PR mode: the PR head sha), `generated_at` (current timestamp), and `scope` (the SCOPE argument, or `PR #<n>`) — this lets `/project-review` check per-file staleness later. PR mode also records `pr`, `pr_base_ref`, and `pr_base_sha`
8. **Saving to docs/reviews/** with ephemeral status (not committed)
9. **Managing session state** to track which issues you've fixed

## Session State Management

During a session, the skill maintains in-memory state of:
- Which issues you've marked as "fixed" (via "I fixed X, what's next?")
- The current report path and scope
- Which issues are left to address

This state is **cleared when the session ends** — it's not persistent. The saved markdown report is the persistent artifact you reference across sessions.

## Making the Most of It

### Learning idioms
```
/code-review src/ --focus idiom
```
Review only the language best practices. The three-dimension scoring helps you understand why each idiom matters.

### Fast security review
```
/code-review src/ --focus high
```
Get straight to critical issues without noise from style or inefficiencies.

### Iterative improvement
Use the "I fixed X, what's next?" flow to work through issues one at a time. Great for:
- Incremental refactoring
- Learning from fixes
- Distributed work across multiple sessions

### Cross-session continuation
Save the report path and reference issues by name days or weeks later. The skill will attempt to locate the issue in current code even if line numbers have drifted.

## Integration with `/project-review`

`/code-review` is the tactical, line-level counterpart to `/project-review` (whole-repo, architectural). Run `/project-review` first on an unfamiliar or newly inherited repo to find where debt concentrates; then run `/code-review` on the specific files or folders it flags for the line-by-line grind.

`/project-review` reads saved `/code-review` reports as evidence — a pattern recurring across 3+ files gets rolled up into one architectural finding there — but never copies individual line items into its own output. The `git_sha`/`generated_at`/`scope` frontmatter above is what makes that possible: `/project-review` diffs each cited file against that commit to decide whether a finding is still valid before using it. Reports with no frontmatter, or where the cited file has changed since, are treated as stale and skipped rather than guessed at.

Keeping the frontmatter accurate is the only thing this skill needs to do to support that integration — no other behavior changes.

**PR reports are excluded from that ingestion.** `/project-review` audits the repo as it exists; a PR report describes code that isn't on the base branch yet, so treating it as evidence would attribute unmerged findings to `main`. Phase 1.5 skips any report whose frontmatter carries `pr:`. Two other consumers key on the same marker: `pipeline-status` leaves PR reports out of its stage-1 "is there a current review" check (a stage-6 review isn't stage-1 work), and `/make-issues` compares against the PR head rather than local `HEAD` in its staleness pre-check, which would otherwise warn on every PR report since the two are different branches by construction.

## Limitations

- **Large codebases**: Scoping to a specific folder/file is recommended for repos >1000 files
- **Token budget**: Analyzing many files at once may exceed API limits; use `--language` or folder scoping to reduce scope
- **Line number drift**: After many edits, old reports' line numbers become inaccurate; use `--refresh` to rescan
- **PR mode reads only**: no tests are run against the PR — that's CI's job, and needing it is what would force a worktree. One PR per run; merge-order questions across several PRs are `/pr-triage`'s

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Found X files (threshold: 30)" | Reduce scope, use `--language`, or filter by file type |
| No issues detected | Check file extensions, verify language detection in console output |
| Can't find an old issue | Use `--refresh` to generate a new report with current line numbers |
| Line numbers don't match | Report is stale; run `--refresh` after many edits |
| PR mode line numbers don't match your checkout | Expected — they're at the PR head, not your `HEAD`. `git fetch origin pull/<n>/head && git checkout -b review-<n> FETCH_HEAD` to see them |
| `/code-review 68` says it can't resolve the PR | Check `gh auth status` and that you're in the right repo. The skill won't fall back to treating `68` as a path |
| PR mode reports nothing on files you know it changed | Findings are limited to added/modified lines. Pre-existing problems appear (capped at 3) under **Out of scope** |

## Future Enhancements

- `--language [LANG]` flag to override auto-detection
- `.status.json` tracking to see which issues you've fixed over time
- `--since COMMIT` for diff-based review of recent local changes (PR mode's line-scoping logic, pointed at a local range)
- PR mode `--refresh` showing what changed since the last report, rather than just regenerating
- `--exclude [CATEGORY]` to filter out certain issue types
- Git hook integration for pre-commit reviews
- Cached analysis for unchanged files