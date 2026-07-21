---
name: code-review
description: Comprehensive code review of a repository scope. Analyzes code across HIGH (security, memory, crashes), IDIOM (language best practices), MEDIUM (inefficiencies), and LOW (style) categories. Issues ranked by importance; all HIGH shown plus top IDIOM+MEDIUM up to 10 total. Reports saved as markdown snapshots in docs/reviews/ (not committed). Use when you want to review a folder/file, pick one issue at a time, and work through them incrementally across multiple sessions.
---

# Comprehensive Code Review

Analyze a specified scope of code (folder, file, or pattern) and generate a prioritized report of issues, categorized by severity and importance. Reports are session-independent markdown snapshots, allowing you to reference issues by name and work through them incrementally.

## Quick Start

```
/code-review src/
```

Scans all code files in `src/`, generates a report in `docs/reviews/code-review_src_YYYY-MM-DD.md`, and displays it.

## Commands

### Scan a scope
```
/code-review [SCOPE]
```

- **SCOPE**: folder path (`src/`), file path (`src/memory.cpp`), glob (`src/**/*.rs`)
- **Output**: Report saved to `docs/reviews/code-review_[SCOPE]_[DATE].md`
- **Display**: Issues printed to console, ready to work through

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
    └── PROJECT_REVIEW.md               (from /project-review — committed, not gitignored)
```

**Key points:**
- Reports are not committed (`docs/reviews/code-review*.md` is gitignored) — this pattern deliberately excludes `PROJECT_REVIEW.md`, which `/project-review` writes to the same directory and which you do want committed and tracked over time
- Issues referenced by **memorable names** (e.g., "Memory leak in Allocator")
- Allows cross-session continuation: come back days later and reference by name
- Each date has a separate report; `/code-review --refresh` generates a new dated report
- Frontmatter (`git_sha`, `generated_at`, `scope`) lets `/project-review` check whether findings are still current before treating them as evidence — see "Integration with /project-review" below

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
```

## When to use

- **Starting a code review of a new/unfamiliar codebase** — Get a comprehensive overview of all issues
- **Learning a language** — Focus on IDIOM issues (`--focus idiom`)
- **Security review** — Focus on HIGH issues (`--focus high`)
- **Picking up where you left off** — Reference issues by name from saved report
- **Routine code quality checks** — Refresh the review (`--refresh`) after a while

## Safety & Limits

### File count threshold
If the specified scope contains more than 30 code files, the skill will ask for confirmation before proceeding. This prevents accidentally scanning huge codebases.

If you see this, either:
- Narrow the scope: `/code-review src/foo/` instead of `/code-review .`
- Use a language filter: `/code-review src/ --language rust`
- Or confirm that you want to scan all files

### Language detection
Auto-detected from file extensions (`.cpp` → C++, `.py` → Python, `.rs` → Rust, etc.)

If the detection is wrong, it can be adjusted in future versions with a `--language [LANG]` flag.

## Implementation Details

The skill works by:

1. **Discovering files** in the specified scope matching code file extensions
2. **Detecting languages** from file extensions
3. **Checking file count** against the 30-file threshold
4. **Reading file contents** and sending to Claude for analysis
5. **Analyzing via Claude API** using a detailed system prompt that instructs Claude to:
   - Identify all issues in each category (HIGH, IDIOM, MEDIUM, LOW)
   - Score IDIOM issues on three dimensions
   - Rank IDIOM+MEDIUM by composite importance
   - Return structured JSON data
6. **Generating markdown report** with ranked issues, prefixed with a frontmatter block recording `git_sha` (`git rev-parse HEAD`), `generated_at` (current timestamp), and `scope` (the SCOPE argument) — this lets `/project-review` check per-file staleness later
7. **Saving to docs/reviews/** with ephemeral status (not committed)
8. **Managing session state** to track which issues you've fixed

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

## Limitations

- **Large codebases**: Scoping to a specific folder/file is recommended for repos >1000 files
- **Token budget**: Analyzing many files at once may exceed API limits; use `--language` or folder scoping to reduce scope
- **Line number drift**: After many edits, old reports' line numbers become inaccurate; use `--refresh` to rescan

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Found X files (threshold: 30)" | Reduce scope, use `--language`, or filter by file type |
| No issues detected | Check file extensions, verify language detection in console output |
| Can't find an old issue | Use `--refresh` to generate a new report with current line numbers |
| Line numbers don't match | Report is stale; run `--refresh` after many edits |

## Future Enhancements

- `--language [LANG]` flag to override auto-detection
- `.status.json` tracking to see which issues you've fixed over time
- `--since COMMIT` for diff-based review of recent changes
- `--exclude [CATEGORY]` to filter out certain issue types
- Git hook integration for pre-commit reviews
- Cached analysis for unchanged files