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

**Swift (Xcode), xcode-tools MCP available** (Claude is running inside
Xcode, or the `xcode-tools` MCP server is connected): prefer the MCP tools
over `xcodebuild`. They use the scheme, test plan, and run destination the
user has selected in Xcode, and return structured results.
- `XcodeListTargets` first. If no target has `isTestTarget: true`, there is
  nothing to run — report `Tests: ⚠️ no test target` (see Step 3) and
  suggest `/add-tests`, which can propose one. Don't report this as a
  build failure.
- All tests: `RunAllTests`
- Tests related to changed files: `GetTestList`, grep its
  `fullTestListPath` file for `TEST_FILE_PATH` matching the changed test
  files (or test names matching the changed types), then `RunSomeTests`
  with those `targetName` / `testIdentifier` pairs. Best effort — fall
  back to `RunAllTests`.
- If the build fails before tests run, get the errors with
  `XcodeListNavigatorIssues` (or `GetBuildLog`) and show them.

**Swift (Xcode), no MCP:**
`xcodebuild test -scheme <SchemeName> -destination 'platform=macOS'`
- List schemes with `xcodebuild -list`; ask the user if more than one could
  hold the tests
- Pick the destination from the target's platform — an iOS app needs
  `-destination 'platform=iOS Simulator,name=<device>'`
  (`xcrun simctl list devices available` lists the simulators)
- If the scheme has no test action, `xcodebuild` fails with "Scheme X is
  not currently configured for the test action" — report that as "no test
  target", not as a test failure
- Run only some tests with `-only-testing:<Target>/<Suite>/<test>`

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
2. Each failing test name and the assertion, panic, or crash that failed
   (for Swift: the failing `#expect`/`#require` or `XCTAssert*`, or the
   crash, e.g. a force-unwrap of `nil`)
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
Tests: ✅ 42 passed, 0 failed   (<command or tool>, 1.3s)
Tests: ⚠️  38 passed, 4 failed  — see above
Tests: ❌ Build failed before tests ran — see above
Tests: ⚠️  No test target — nothing to run (/add-tests can propose one)
```

---

## What not to do

- Don't modify source code or tests to make tests pass
- Don't skip or filter out failing tests without the user asking
- Don't run tests that require infrastructure (databases, network)
  without warning the user first
- Don't assume `make test` is correct without checking the Makefile target