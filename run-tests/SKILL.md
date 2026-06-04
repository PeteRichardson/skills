---
name: run-tests
description: Detect the test framework, run the test suite, and report results. Use when the user types /run-tests, says "run the tests", "do the tests pass", or wants to verify tests are green before committing. Also used by /pre-commit in verify mode.
---

# Run Tests

Detect the test framework, run tests scoped to the current changes where
possible, report results clearly, and help diagnose failures.

---

## Step 1: Detect language and test command

```bash
cat Cargo.toml 2>/dev/null | head -20
cat Package.swift 2>/dev/null | head -5
ls *.xcodeproj 2>/dev/null || ls *.xcworkspace 2>/dev/null
cat pyproject.toml 2>/dev/null | grep -A10 '\[tool.pytest'
cat pytest.ini 2>/dev/null
ls Makefile 2>/dev/null && grep "^test:" Makefile 2>/dev/null
```

**Rust:** `cargo test`
- For a workspace: `cargo test --workspace`
- To run only tests related to changed files, use the module path:
  `cargo test <module_name>` (best effort — fall back to full suite)

**Swift (SPM):** `swift test`
- For a specific target: `swift test --filter <TestTargetName>`

**Swift (Xcode):** `xcodebuild test -scheme <SchemeName> -destination 'platform=macOS'`
- Read the scheme name from the `.xcodeproj` or ask the user if ambiguous

**Python:** `pytest` (preferred) or `python -m pytest`
- For changed files only: `pytest tests/test_foo.py tests/test_bar.py`
- With verbose output: `pytest -v`

If a `Makefile` has a `test:` target, prefer `make test` as it likely
encodes project-specific setup.

---

## Step 2: Run the tests

Run the detected command. Stream or capture output — show it in full if
it's short (<50 lines), summarize if long.

**On success:** Show the pass summary (N tests, N passed) and say:
> ✅ All tests passing.

**On failure:** Show:
1. The number of failures
2. Each failing test name and the assertion or panic that failed
3. Relevant context (file, line) — don't dump the full stack unless
   it's short

Then ask:
> Tests failing. Want to investigate and fix, or proceed anyway?

If the user wants to investigate, help diagnose: read the failing test,
read the relevant source, reason about the mismatch.

---

## Step 3: Report

Close with one of:

```
Tests: ✅ 42 passed, 0 failed   (cargo test, 1.3s)
Tests: ⚠️  38 passed, 4 failed  — see above
Tests: ❌ Build failed before tests ran — see above
```

---

## What not to do

- Don't modify source code or tests to make tests pass
- Don't skip or filter out failing tests without the user asking
- Don't run tests that require infrastructure (databases, network)
  without warning the user first
- Don't assume `make test` is correct without checking the Makefile target