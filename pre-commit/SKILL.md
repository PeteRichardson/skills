---
name: pre-commit
description: Final verification pass before generating a commit message. Checks that tests exist, tests pass, and docs are current. Use when the user types /pre-commit or says "ready to commit". Expects all checks to be green — flags mean the development workflow needs attention, not that fixes should happen here.
---

# Pre-Commit Verification

Run a final check across tests, test results, and documentation. This is
a verification pass — not a fix-it pass. If anything is red, the
appropriate skill to fix it is named. Fix it there, then re-run
`/pre-commit`.

---

## Step 0: Establish diff scope and isolate staged changes

### Check git state

```bash
git status
git diff --staged --name-only
git diff --name-only
```

### Handle unstaged changes

| Situation | Action |
|-----------|--------|
| Files staged, nothing unstaged | Proceed directly |
| Files staged, unstaged changes also present | Stash unstaged changes (see below) |
| Nothing staged, files changed | Warn and ask (see below) |
| Nothing changed | Tell the user, stop |

**If unstaged changes are present alongside staged changes:**

Inform the user:
> Unstaged changes detected alongside staged files. Stashing them so
> verification runs against exactly what will be committed.
>
> If the checks fail after stashing but passed before, that means the
> commit is incomplete — the unstaged changes were doing work that
> should be staged too.
>
> ⚠️ If this session is interrupted before the stash is popped, run
> `git stash pop` to restore your changes. Stash will be named
> `pre-commit-isolation`.

**Xcode projects:** if the stash would include anything under
`*.xcodeproj/` or `*.xcworkspace/` (check `git diff --name-only`), Xcode
reloads the project from disk when it changes under it, and can write its
in-memory copy back over the restored file. Add to the message above:

> ⚠️ The stash includes Xcode project files (`project.pbxproj`). If Xcode
> asks whether to keep its version or revert to the version on disk,
> choose **Revert** — after the stash is popped, the disk version is yours.

Then stash:

```bash
git stash push --keep-index --message "pre-commit-isolation"
```

`--keep-index` preserves staged changes in the working tree while
stashing everything else. The working tree now matches exactly what
will be committed.

Proceed with all checks. After Step 4 (regardless of results), always
pop the stash:

```bash
git stash pop
```

Confirm the pop succeeded. If it fails (rare merge conflict), tell
the user:
> Stash pop encountered a conflict. Run `git stash pop` manually
> to restore your unstaged changes.

**If nothing is staged but files are changed:**

Ask:
> No files are staged. Options:
> - Stage the files you want to commit, then re-run `/pre-commit`
> - Proceed anyway, checking all changed files (not recommended —
>   results may not reflect your actual commit)

Don't proceed until the user responds. Defaulting to unstaged files
risks a false green. This is the one place `/pre-commit` should pause
rather than continue.

---

## Step 1: Test coverage

Detect language (see `/add-tests` Step 1 for detection logic).

Find existing test files and reason about coverage of the in-scope
source files. Flag any source file with no apparent test coverage.

```
Tests exist:  ✅ coverage apparent for all changed files
              ⚠️  no coverage found for: foo.rs, bar.rs
                  → run /add-tests to plan and write them
              ⚠️  no test target in the project
                  → run /add-tests to propose one
```

Changes to non-code files only (asset catalogs, `.xcstrings`,
entitlements, `project.pbxproj` alone) need no test coverage — don't flag
them.

---

## Step 2: Test results

Detect and run the test suite (see `/run-tests` for detection logic).
Run once. Report pass or fail.

```
Tests pass:   ✅ 42 passed, 0 failed
              ❌ 4 failing — run /run-tests to diagnose
              ⚠️  skipped (build error) — run /run-tests to diagnose
              ⚠️  skipped (no test target) — run /add-tests
```

A project that builds but has no tests is ⚠️, never ✅. For an Xcode
project, a green build is not a green test run.

---

## Step 3: Documentation

Check design doc currency against the diff (see `/update-docs` Step 2
for the assessment logic). Don't invoke `/design-doc` here — just
assess and flag.

```bash
head -10 docs/design.md 2>/dev/null
git log --oneline -1 -- docs/design.md
```

```
Design doc:   ✅ current
              ⚠️  may be stale — run /update-docs
```

---

## Step 4: Pop stash (if stashed in Step 0)

If unstaged changes were stashed in Step 0, pop now regardless of
check results:

```bash
git stash pop
```

Confirm success. If conflict, prompt manual recovery (see Step 0).

---

## Step 5: Summary

Print the gate:

```
Pre-commit verification
───────────────────────
Tests exist:   ✅
Tests pass:    ✅
Design doc:    ✅
───────────────────────
✅ All clear — run /commit-message
```

Or if anything is flagged:

```
Pre-commit verification
───────────────────────
Tests exist:   ⚠️  missing for: lexer.rs → /add-tests
Tests pass:    ❌  4 failing → /run-tests
Design doc:    ✅
───────────────────────
⚠️  Address flagged items, then re-run /pre-commit
```

Never say "run `/commit-message`" if any check is red. Never silently
pass a check that failed.

---

## What not to do

- Don't fix anything — name the skill that fixes it
- Don't write tests or update docs inline
- Don't run `/commit-message` automatically — the user runs it
- Don't forget to pop the stash — always pop, even if checks fail