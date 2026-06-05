# Skill: `/review` — Comprehensive Repository Code Review

## Overview
`/review` analyzes a code repository (or folder/file) and generates a prioritized list of issues across four categories: HIGH (critical), IDIOM (language best practices), MEDIUM (inefficiencies/edge cases), and LOW (style). The report is a clean markdown snapshot, session-independent, allowing you to reference issues by name across days or weeks and work through them iteratively.

## Design Principles

1. **Session independence**: Reports are ephemeral files (not committed), readable across sessions
2. **Importance-based ranking**: Within IDIOM and MEDIUM, rank by composite importance score (not category alone)
3. **Learning-focused**: IDIOM issues highlight patterns you should master for language expertise and interview readiness
4. **Incremental fixing**: Reference issues by name, ask "I fixed that one, what's next?" to continue without re-scanning

## Categories

### HIGH (all shown, always)
Critical issues that must be addressed:
- Security vulnerabilities (SQL injection, buffer overflows, unauthorized access)
- Memory safety (leaks, use-after-free, dangling pointers)
- Crashes and deadlocks
- Correctness bugs with severe impact

**Shown:** All HIGH issues, no filtering.

### IDIOM (scored and ranked)
Language idioms and best practices. Not idiomatic code signals knowledge gaps.

**Scoring (1–9 points total):**
- **Interview knowledge** (1–3): 1=nice to have, 2=expected, 3=red flag if missing
- **Code simplification** (1–3): 1=slightly cleaner, 2=notably simpler, 3=drastically reduces code
- **Scope & impact** (1–3): 1=single site, 2=reduces bugs, 3=widespread/prevents major issues

**Example: Optional chaining in Swift**
- Interview: +1 (nice to have, not gating)
- Simplification: +3 (eliminates nested if-lets)
- Impact: +3 (multiple nil-check sites)
- **Total: 7/10**

**Example: RAII in C++**
- Interview: +3 (red flag if you don't know it)
- Simplification: +2 (cleaner than manual cleanup)
- Impact: +3 (prevents leaks across many sites)
- **Total: 8/10**

### MEDIUM (scored and ranked)
Inefficiencies, error handling gaps, edge cases, and maintainability issues.

**Scoring:** Ranked by scope and impact:
- Scope: 1 (single site), 2 (multiple functions/files)
- Impact: Performance, bug likelihood, maintenance burden
- **Total: 2–6 points**

### LOW (shown only if room)
Style issues, naming conventions, missing comments. Lowest priority.

**Shown:** Only if total issues < 10 and capacity remains.

## Report Structure

```markdown
# Code Review: [SCOPE]

**Timestamp:** YYYY-MM-DDTHH:MM:SSZ
**Scope:** [path] | **Focus:** [all|high|idiom|medium|low]
**Summary:** X HIGH • Y IDIOM • Z MEDIUM • W LOW
**Reporting:** All HIGH + top (10 - num_HIGH) IDIOM+MEDIUM by importance + fill with LOW if needed

---

## 🔴 HIGH (X issues)

### 1. [Memorable issue name]
**Location:** path/file.ext:LINE
**Category:** [Security|Memory|Correctness|Concurrency]
**Issue:** [Clear description of what's wrong]
**Severity:** High | **Impact:** [Consequence]
**Evidence:**
\`\`\`[language]
[Current code snippet]
\`\`\`

---

## 🟠 IDIOM + 🟡 MEDIUM (ranked by importance, Y of Z shown)

### N. [Memorable issue name] (IDIOM|MEDIUM) — Importance: S/10
**Location:** path/file.ext:LINE
**Category:** [e.g., "C++ idiom", "Error handling", "Performance"]

**For IDIOM issues:**
- Interview knowledge: +X (1=nice to have, 2=expected, 3=red flag)
- Code simplification: +X (1=slightly cleaner, 2=notably simpler, 3=drastically reduces)
- Scope & impact: +X (1=single site, 2=reduces bugs, 3=widespread)

**Current approach:**
\`\`\`[language]
[Current code]
\`\`\`

**Idiomatic approach:**
\`\`\`[language]
[Better code]
\`\`\`

**Why this matters:**
[Explanation of the idiom, why it's better, and what it teaches you]

---

## 🟢 LOW (0 shown, W available)
(Only if there is capacity after HIGH + IDIOM+MEDIUM)

---

## Summary
- **Total files scanned:** N
- **Lines of code:** M
- **Issues by category:** X HIGH • Y IDIOM • Z MEDIUM • W LOW
- **Next step:** Pick one issue by name and ask "Let's fix [issue name]" or "I fixed that one, what's next?"
```

## File Storage

**Location:** `docs/reviews/[SCOPE]_[TIMESTAMP].md`
- Replace `/` with `_` in scope (e.g., `src/` → `src_`)
- Timestamp: `YYYY-MM-DD` (e.g., `src_2025-06-04.md`)

**In .gitignore:**
```
docs/reviews/
docs/tmp/
```

**Ephemeral:** Reports are not committed. They live on disk for cross-session reference but are not version-controlled.

## Commands

### Initial scan
```
/review [SCOPE]
```
- **SCOPE:** Folder path, file path, or glob pattern (e.g., `src/`, `src/memory.cpp`, `src/**/*.py`)
- **Output:** Generates `docs/reviews/[SCOPE]_[TIMESTAMP].md`
- **Behavior:** Full scan of all files in scope, all issue categories

**Example:**
```
/review src/
/review src/memory.cpp
/review src/**/*.rs
```

### Focus filter
```
/review [SCOPE] --focus [high|idiom|medium|low|all]
```
- **high**: Only HIGH severity issues
- **idiom**: Only IDIOM issues (useful for language learning sprints)
- **medium**: Only MEDIUM issues
- **low**: Only LOW issues
- **all**: All categories (default)

**Example:**
```
/review src/ --focus idiom
/review . --focus high
```

### Continue mid-session (in-memory state)
```
"I fixed [issue name], what's next?"
```
- Updates in-memory tracking of which issues you've addressed
- Shows next unaddressed issue from current report
- Does not modify the saved report file

**Example:**
```
"I fixed the memory leak in Allocator, what's next?"
"Let's work on the next one"
```

### Locate issue across sessions
```
"Show me [issue name] again"
```
- Reads issue from saved report
- Attempts to locate it in current code (handles line number drift)
- If line numbers have shifted significantly, offers search/regex alternatives

**Example:**
```
"Show me the SQL injection in parse_user_id again"
"Let's tackle the optional chaining issue"
```

### Refresh scan (new report)
```
/review [SCOPE] --refresh
```
- Generates a new report file
- Optionally asks which issues from previous report you've already fixed (so they don't reappear)
- Useful when line numbers have drifted after many fixes

**Example:**
```
/review src/ --refresh
```

## Prompting Strategy

The system prompt to Claude should:

1. **Auto-detect language** from file extensions (.cpp/.h → C++, .py → Python, .rs → Rust, .swift → Swift, etc.)

2. **Scan all files** in the specified scope

3. **For each issue identified:**
   - Assign category (HIGH, IDIOM, MEDIUM, LOW)
   - For IDIOM: score on three dimensions (interview, simplification, impact)
   - For MEDIUM: estimate importance (scope + impact)
   - Include file + line number
   - Show current code snippet
   - For IDIOM: show idiomatic alternative + explanation

4. **Rank IDIOM+MEDIUM** by importance score (descending)

5. **Report all HIGH + top (10 - num_HIGH) IDIOM+MEDIUM + LOW if room**

6. **Output in markdown** format as specified above

### System Prompt Template

```
You are a code reviewer analyzing [LANGUAGE] code in [SCOPE].

Your goal is to identify and rank issues in four categories:

## HIGH: Critical issues (all shown)
Security bugs, memory leaks, crashes, deadlocks, correctness issues with severe impact.

## IDIOM: Language best practices (scored 1–9 points)
Patterns that competent [LANGUAGE] programmers use. Not idiomatic code signals knowledge gaps.
Score on three dimensions:
- Interview knowledge (1–3): 1=nice to have, 2=expected, 3=red flag if missing
- Code simplification (1–3): 1=slightly cleaner, 2=notably simpler, 3=drastically reduces code
- Scope & impact (1–3): 1=single site, 2=reduces bugs, 3=widespread/prevents major issues

For each IDIOM issue, show the current pattern and the idiomatic alternative with explanation.

## MEDIUM: Inefficiencies, error handling, edge cases (scored by importance)
Missing nil checks, error handling gaps, performance bottlenecks, maintenance issues.
Score by scope (how many places affected) and impact (consequences if not fixed).

## LOW: Style, naming, comments
Lowest priority. Only shown if there is capacity after HIGH + IDIOM+MEDIUM.

## Output requirements:
1. Scan all files in [SCOPE]
2. Identify all issues in each category
3. Score IDIOM issues on the three dimensions (show breakdown)
4. Rank IDIOM+MEDIUM by total importance (highest first)
5. Report all HIGH + top (10 - num_HIGH) IDIOM+MEDIUM + LOW if needed
6. For each issue: memorable title, file:line, code snippets, explanation
7. Format in markdown as specified in the skill doc

Focus on teaching good patterns, not just fixing bad ones. Make issue titles memorable so they can be referenced later (e.g., "Memory leak in Allocator", "Optional chaining in nil checks").
```

## State Management

### In-memory (session-only)
- Tracks which issues have been marked as "fixed" during the current session
- Cleared when the session ends
- Used to show next issue and avoid re-suggesting fixed ones

### Saved (cross-session)
- Report file itself (markdown) is the primary artifact
- Optional: `.status.json` file tracking which issues were fixed in which sessions (for future enhancements)

### Never committed
- Both report and status are in .gitignore
- Ephemeral per-developer, not shared

## Workflow Example

**Session 1 (June 4):**
```
/review src/
→ Generates docs/reviews/src_2025-06-04.md
→ Reports: 5 HIGH • 3 IDIOM • 4 MEDIUM • 2 LOW
→ Showing all 5 HIGH + 3 IDIOM + 4 MEDIUM (12 total, over cap of 10)
→ Wait, that's 12. The rule is "all HIGH + up to 10 total IDIOM+MEDIUM+LOW"
→ So: all 5 HIGH (5 slots used), then 5 IDIOM+MEDIUM by importance, then fill with LOW if needed
→ Actually, let me re-read: "all HIGH, then the IDIOM and MEDIUM issues are ordered by importance and then the top 10 is filled out"
→ Interpretation: Show all HIGH + top (10 - num_HIGH) IDIOM+MEDIUM by importance + LOW if needed
→ So: 5 HIGH + 5 IDIOM+MEDIUM (highest scoring first) = 10 total. Done. No LOW shown.
```

User picks: "Let's fix the memory leak in Allocator"
```
→ Claude shows the code, explains the fix
→ User implements fix, commits
```

User asks: "I fixed that one, what's next?"
```
→ Marks issue as ✓ in memory
→ Shows next unaddressed issue from report (SQL injection in parse_user_id)
```

Fix and commit that one.

User asks: "I fixed that one, what's next?"
```
→ Shows next issue (optional chaining in nil checks)
```

**Session 2 (June 10, days later):**
User opens report file and picks an issue:
```
"Show me the inefficient loop in process_batch"
→ Claude reads report, locates issue in current code (line numbers may have drifted)
→ Helps fix it
```

After several fixes, line numbers are very stale:
```
/review src/ --refresh
→ Generates new report: docs/reviews/src_2025-06-10.md
→ Reports new issues + notes which old issues are now fixed
```

## Edge Cases & Decisions

### Line number drift
When an issue is referenced across sessions and line numbers have shifted:
1. First attempt: regex/grep search in current code to find the pattern
2. If multiple matches: show them and ask which one
3. If no match: suggest re-running `--refresh`

### Stale issues
After many fixes, the report becomes less accurate:
- Line numbers shift significantly
- Some issues may already be fixed but report doesn't know
- Solution: `/review [SCOPE] --refresh` generates new report

### Large codebases
If a scope has thousands of files:
- Consider warning the user about token budget
- Optionally filter by file type or size
- Document any limitations in the generated report

### Language detection
- Auto-detect from file extensions
- If ambiguous or wrong, user can add `--language [LANG]` flag (future enhancement)

## Metrics for Success

1. **Clarity**: Issue names are memorable and referenceable
2. **Actionability**: Each issue has code snippet + clear explanation
3. **Learning**: IDIOM issues teach you language patterns with breakdown of why they matter
4. **Cross-session usability**: Report file persists, can be read and referenced days later
5. **Iterative workflow**: "I fixed that one, what's next?" works smoothly

## Future Enhancements

- `--language [LANG]` flag if auto-detection is wrong
- `.status.json` tracking which issues fixed when (for historical comparison)
- Diff-based review: `/review src/ --since COMMIT` to review only changed files
- Filtering by issue type: `/review src/ --exclude style,naming`
- Integration with git hooks for pre-commit review
