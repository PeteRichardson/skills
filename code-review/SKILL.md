---
name: code-review
description: Comprehensive code review of a repository scope, a GitHub pull request, or the changes on the current branch. Runs one review engine — open-code-review-delegate (default for changes and PRs), this skill's own protocol (default for a scope), or mattpocock-skills:code-review — and always writes one report format that /make-issues can file. Analyzes code across HIGH (security, memory, crashes), IDIOM (language best practices), MEDIUM (inefficiencies), and LOW (style) categories. Issues ranked by importance; all HIGH shown plus top IDIOM+MEDIUM up to 10 total. Reports saved as markdown snapshots in docs/reviews/ (not committed). Use when you want to review a folder/file, pick one issue at a time, and work through them incrementally across multiple sessions. Also use when the user types /code-review 68, /code-review #68, or /code-review PR68, says "review PR 68", "review this pull request", "code review the PR before I merge it", or passes a GitHub pull request URL. Also use when /code-review is typed with no argument, or another skill (such as /implement or /implement-spec) says to review the work on the current branch, or the user says "review my changes" or "review since main".
---

# Comprehensive Code Review

Analyze a specified scope of code (folder, file, or pattern) — or the change proposed by a GitHub pull request, or the changes on the current branch — and generate a prioritized report of issues, categorized by severity and importance. Reports are session-independent markdown snapshots, allowing you to reference issues by name and work through them incrementally.

## Quick Start

```
/code-review src/          # review a scope of the working tree
/code-review 68            # review what PR #68 proposes
/code-review               # review the changes on this branch
```

A review has three parts: a **target** (what to review), an **engine** (who finds the issues), and **one report format** (what every engine's findings become). See [Engines](#engines).

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

### Review the changes on this branch
```
/code-review
/code-review --since <ref>
```

- **No argument, on a branch other than the default branch** — the commits since the merge base with `origin/<default>`. This is what Matt Pocock's `/implement` and `/implement-spec` get when they say "run /code-review" at the end of their work.
- **No argument, on the default branch** — the uncommitted changes (staged, unstaged, untracked). If there are none, ask for a scope or a PR. Don't review the whole repo by default.
- **`--since <ref>`** — the commits since `<ref>` (a sha, branch, or tag), compared against the merge base, like `git diff <ref>...HEAD`.
- **Output**: `docs/reviews/code-review_CHANGE-<label>_[DATE].md`. `<label>` is the branch name (`/` → `-`), or `workspace` for uncommitted changes.
- **Which lines can be findings**: the same rule as PR mode — see [Which lines can be findings](#which-lines-can-be-findings).

On a branch with commits **and** uncommitted changes, review the commits and say that the uncommitted changes are not in the report. Never stash, commit, or check out anything to include them.

### Choose the engine
```
/code-review [TARGET] --engine ocr|native|matt
```

Default: `ocr` for a PR or a change, `native` for a scope. See [Engines](#engines).

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

Everything below this section — engines, tiers, IDIOM scoring, the reporting rule, the report format — is identical in every mode. PR mode differs only in **where the code comes from** and **which lines are eligible to be findings**.

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

This rule holds for every **diff target**: a PR, and a change (branch, `--since`, uncommitted). In it, "the PR" means the change under review.

Report findings only on lines the PR **added or modified**. The point of PR mode is to answer "is this change sound," not to re-litigate the files it happens to touch.

**One exception:** a problem the PR *causes* on a line it didn't touch — a changed function contract that breaks an existing caller, a renamed field an untouched serializer still writes. Report those with an extra `**Introduced by:**` field naming the hunk responsible. A finding on an untouched line without that field is out of scope by definition.

Pre-existing issues on untouched lines aren't ranked and don't consume report slots. List at most **three** of them under **Out of scope (pre-existing)** at the end of the report — name and location only, no evidence blocks. The reader wants to know they were seen and set aside. The cap is what stops that section from growing back into the scope-mode report PR mode exists to avoid.

That section is a pointer, not a work queue: `/make-issues` deliberately skips it, since entries with no tier, severity, or evidence can't become an issue without inventing all three. `/code-review <path>` in scope mode is how one becomes filable.

## Engines

An engine finds the issues. This skill does everything else: it resolves the target, picks the engine, converts the engine's findings into one list, tiers and scores that list, and writes the report. So the report format, the tiers, and the reporting rule are the same for every engine, and `/make-issues` reads every report the same way.

Never edit an engine's own skill file. The `ocr` and `matt` engines are other authors' skills; they update on their own, and this skill reads or calls them as they are.

### Which engine runs

| Target | Default engine | Other engines |
|---|---|---|
| Scope (`src/`, a file, a glob) | `native` | none — `ocr` and `matt` review a diff only, never a whole file |
| PR (`68`) | `ocr` | `native`; `matt` only on a checkout of the PR (see below) |
| Change (no argument, `--since`) | `ocr` | `native`, `matt` |

`--engine` overrides the default. When the default is `ocr` and `ocr --version` fails, use `native` and say so once in the report header — a missing tool is a degraded run, not an error.

### `native` — this skill's own protocol

Read the code of the target and find issues with the tier definitions in [Issue Categories & Importance](#issue-categories--importance). This is the engine that has always been here.

### `ocr` — open-code-review-delegate

Read `~/.claude/skills/open-code-review-delegate/SKILL.md` and run its **Steps 1–5** only. Do not run its Step 6 (its own report) or Step 7 (it applies fixes — this skill never changes code). Give its `preview` the mode that matches the target:

| Target | `ocr delegate preview` flags |
|---|---|
| PR | `--format json --from <merge base sha> --to <PR head sha>` (after the `git fetch origin pull/<n>/head` of PR mode — nothing is checked out) |
| Branch change | `--format json --from <merge base with origin/<default>> --to HEAD` |
| `--since <ref>` | `--format json --from <ref> --to HEAD` |
| Uncommitted change | `--format json` (workspace mode) |

Its output is a list of comments: `path`, `content`, `start_line`, `end_line`, `category`, `severity`. Its preview also lists `excluded_files` with a reason (for example `unsupported_ext` for Markdown). Every excluded file goes into the report's skipped-files list, with its reason, so the reader knows it was not reviewed. Its coverage numbers (`total_files`, `reviewed_files`, `skipped_files`) go into the Summary.

### `matt` — mattpocock-skills:code-review

Call it with the Skill tool (`mattpocock-skills:code-review`) and give it the fixed point as its argument: the merge base for a branch change, or the `--since` ref. It reviews `<fixed point>...HEAD`, so it needs the code checked out:

- **PR target** — it cannot review a PR that is not checked out, and this skill never checks one out. Say so and stop: `gh pr checkout <n>`, then `/code-review --engine matt` on that branch.
- **Uncommitted change** — its diff does not include uncommitted work. Say so and stop.
- It needs `docs/agents/issue-tracker.md` in the repo. When that file is missing it stops and names `/setup-matt-pocock-skills`. Pass that on, and offer `--engine ocr` instead.

Its output is two prose sections, `## Standards` and `## Spec`. Each item is one raw finding. Keep the axis it came from: every finding from this engine gets an `**Axis:** Standards` or `**Axis:** Spec` line in the report. Its own text says not to merge or rerank the two axes; this wrapper does rank them together, because one ranked list is what `/make-issues` can file. The **Axis:** line is how the reader still sees which check found what.

### Convert the findings

Every engine's output becomes one list of raw findings: `path`, line or lines, what is wrong, an evidence snippet (copied from the file at the reviewed commit, never paraphrased), the engine's own severity and category if it gave them, and the axis (`matt` only).

Then apply this skill's tiers to every raw finding. The engine's severity is a starting point; the tier definitions in this file decide:

| Engine says | Starting tier |
|---|---|
| `ocr` `critical`, `high` | HIGH |
| `ocr` `medium` | MEDIUM |
| `ocr` `low` | LOW |
| `ocr` no severity | Decide from the tier definitions |
| `matt` Spec: implementation looks wrong | HIGH when the impact is severe (wrong data, crash, security), otherwise MEDIUM |
| `matt` Spec: requirement missing or partial | MEDIUM |
| `matt` Spec: scope creep | LOW |
| `matt` Standards: hard violation of a documented standard | MEDIUM |
| `matt` Standards: baseline smell (always a judgement call) | LOW |

A finding about a language idiom (from any engine, whatever its starting tier) becomes **IDIOM**, scored on the three IDIOM dimensions, with its derived severity. MEDIUM and IDIOM findings get their importance scores here, by this skill, not by the engine. Then the [reporting rule](#reporting-rule) picks what the report shows.

Drop a raw finding without a file and a line the engine named — this skill does not guess a location. Drop a duplicate (two engines' items, or two items of one engine, about the same line and the same defect); keep the one with the better evidence.

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
    ├── code-review_CHANGE-feat-retry_2026-10-12.md  (change mode — also gitignored)
    └── PROJECT_REVIEW.md               (from /project-review — committed, not gitignored)
```

**Key points:**
- Reports are not committed (`docs/reviews/code-review*.md` is gitignored) — this pattern deliberately excludes `PROJECT_REVIEW.md`, which `/project-review` writes to the same directory and which you do want committed and tracked over time
- Issues referenced by **memorable names** (e.g., "Memory leak in Allocator")
- Allows cross-session continuation: come back days later and reference by name
- Each date has a separate report; `/code-review --refresh` generates a new dated report
- Frontmatter (`git_sha`, `generated_at`, `scope`) lets `/project-review` check whether findings are still current before treating them as evidence — see "Integration with /project-review" below
- PR reports add a `pr:` frontmatter key, and change reports a `change:` key. The **presence** of either is the marker meaning "this report describes code that isn't on the base branch yet" — three downstream consumers key on it (see [Report Structure](#report-structure))
- Every report records its `engine:`

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
engine: native
---

# Code Review: [SCOPE]

**Timestamp:** YYYY-MM-DD
**Engine:** native | ocr | matt
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
- Total files scanned: N (with `ocr`: reviewed R, skipped S, coverage C%)
- Skipped files: path — reason (one line each; omit the line when none were skipped)
- Next step: Pick one issue by name and ask "Let's fix [issue name]"
- Or file them all: `/make-issues docs/reviews/code-review_[SCOPE]_[DATE].md`
```

A finding from the `matt` engine adds one line after **Location:**:

```markdown
**Axis:** Standards | Spec
```

`/make-issues` ignores lines it does not know, so this needs no parser change.

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

### Change mode differences

Change mode adds the same three things as PR mode, with its own frontmatter:

```yaml
---
git_sha: 9f8e7d6           # HEAD at review time (local, so /make-issues' HEAD check works)
generated_at: 2026-10-12T14:32:00-07:00
scope: branch feat/retry since 1a2b3c4
engine: ocr
change: branch             # branch | since | workspace — presence marks an unmerged change
change_base_sha: 1a2b3c4   # the merge base, or the --since ref resolved to a sha
---
```

For `workspace`, `change_base_sha` is `HEAD` and the line numbers are those of the working tree.

## Next in the pipeline

Which stage this skill occupies depends on the mode. **Scope mode is stage 1** (find the work) of the review → issue → PR → merge pipeline (`~/.claude/skills/WORKFLOW.md`), alongside `/project-review`. **PR mode is stage 6** (the line-level pass before merging), so it hands off differently. **Change mode** reviews work before it is a PR, so it hands off like PR mode.

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

### Change mode

When another skill called this one (Matt's `/implement` or `/implement-spec` say "use /code-review to review the work"), print no next step — that skill fixes the findings next, as its own text says. Otherwise:

> Next: fix these on this branch before you open the PR, or `/make-issues docs/reviews/code-review_CHANGE-feat-retry_2026-10-12.md` for anything that should not block it.

### Both diff modes

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

1. **Resolving the target** — PR mode if the argument is `68` / `#68` / `PR68` / a PR URL; change mode for no argument or `--since <ref>`; scope mode otherwise
2. **Choosing the engine** — `--engine`, or the default for the target (see [Engines](#engines))
3. **Discovering files** — scope mode: files in the scope matching code file extensions. PR mode: the PR's changed files, via `gh pr view` + `git fetch origin pull/<n>/head`. Change mode: the files changed since the base (with `ocr`, its preview gives them)
4. **Detecting languages** from file extensions
5. **Checking file count** against the 30-file threshold (PR mode: `changedFiles`)
6. **Running the engine** — `native` reads the files (scope mode: the working tree; PR mode: `git show <headSha>:<path>` plus `gh pr diff` for the hunk boundaries, never checking anything out); `ocr` and `matt` run as described in [Engines](#engines)
7. **Converting and analyzing** the findings, so that every engine's output is:
   - Identify all issues in each category (HIGH, IDIOM, MEDIUM, LOW)
   - Score IDIOM issues on three dimensions
   - Rank IDIOM+MEDIUM by composite importance
   - In PR and change mode, restrict findings to added/modified lines, except those carrying `Introduced by:`
8. **Generating markdown report** with ranked issues, prefixed with a frontmatter block recording `git_sha` (scope and change mode: `git rev-parse HEAD`; PR mode: the PR head sha), `generated_at` (current timestamp), `scope` (the SCOPE argument, `PR #<n>`, or the change), and `engine` — this lets `/project-review` check per-file staleness later. PR mode also records `pr`, `pr_base_ref`, and `pr_base_sha`; change mode records `change` and `change_base_sha`
9. **Saving to docs/reviews/** with ephemeral status (not committed)
10. **Managing session state** to track which issues you've fixed

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

**PR and change reports are excluded from that ingestion.** `/project-review` audits the repo as it exists; a PR or change report describes code that isn't on the base branch yet, so treating it as evidence would attribute unmerged findings to `main`. Phase 1.5 skips any report whose frontmatter carries `pr:` or `change:`. Two other consumers key on the same markers: `pipeline-status` leaves PR and change reports (`code-review_PR*`, `code-review_CHANGE-*`) out of its stage-1 "is there a current review" check (a stage-6 review isn't stage-1 work), and `/make-issues` compares against the PR head rather than local `HEAD` in its staleness pre-check, which would otherwise warn on every PR report since the two are different branches by construction.

## Limitations

- **Large codebases**: Scoping to a specific folder/file is recommended for repos >1000 files
- **Token budget**: Analyzing many files at once may exceed API limits; use `--language` or folder scoping to reduce scope
- **Line number drift**: After many edits, old reports' line numbers become inaccurate; use `--refresh` to rescan
- **PR mode reads only**: no tests are run against the PR — that's CI's job, and needing it is what would force a worktree. One PR per run; merge-order questions across several PRs are `/merge-order`'s

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Found X files (threshold: 30)" | Reduce scope, use `--language`, or filter by file type |
| No issues detected | Check file extensions, verify language detection in console output |
| Can't find an old issue | Use `--refresh` to generate a new report with current line numbers |
| Line numbers don't match | Report is stale; run `--refresh` after many edits |
| PR mode line numbers don't match your checkout | Expected — they're at the PR head, not your `HEAD`. `git fetch origin pull/<n>/head && git checkout -b review-<n> FETCH_HEAD` to see them |
| `/code-review 68` says it can't resolve the PR | Check `gh auth status` and that you're in the right repo. The skill won't fall back to treating `68` as a path |
| Report says files were skipped with `unsupported_ext` | The `ocr` engine does not review that file type (for example Markdown). Use `--engine native` to include it |
| `--engine matt` stops on a PR | It reviews only checked-out code. `gh pr checkout <n>`, then `/code-review --engine matt` |
| PR mode reports nothing on files you know it changed | Findings are limited to added/modified lines. Pre-existing problems appear (capped at 3) under **Out of scope** |

## Future Enhancements

- `--language [LANG]` flag to override auto-detection
- `.status.json` tracking to see which issues you've fixed over time
- PR mode `--refresh` showing what changed since the last report, rather than just regenerating
- `--exclude [CATEGORY]` to filter out certain issue types
- Git hook integration for pre-commit reviews
- Cached analysis for unchanged files