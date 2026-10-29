---
name: add-tests
description: Analyze changed code, identify missing test coverage, and propose a test plan for approval before writing any tests. Use when the user types /add-tests, says "what tests do I need", "do I have test coverage for this", or has just finished writing new code and wants to plan tests. Does not write tests until the user approves the proposal.
---

# Add Tests

Analyze the current changes, identify gaps in test coverage, propose a
named test plan, and write tests only after the user approves. The goal
is a proposal the developer can read quickly and selectively approve —
not an exhaustive list of every conceivable test.

---

## Step 1: Detect language and test conventions

```bash
cat Cargo.toml 2>/dev/null | head -20
cat Package.swift 2>/dev/null | head -20
ls *.xcodeproj 2>/dev/null || ls *.xcworkspace 2>/dev/null
cat pyproject.toml 2>/dev/null | head -20
cat pytest.ini 2>/dev/null
cat setup.cfg 2>/dev/null | grep -A5 '\[tool:pytest\]'
```

**Rust:** Tests live in inline `#[cfg(test)]` modules within the source
file, and/or in `tests/` as integration tests. Framework: `cargo test`.

**Swift:** Tests live in a separate test target (`*Tests`, typically a
`Tests/` or `*Tests/` directory), never in the source file. Framework:
Swift Testing (`import Testing`) is the default for new tests; use XCTest
only when the target already uses it. UI tests use XCUIAutomation in a
UI-testing target. Run via `swift test` (SPM) or `/run-tests` (Xcode).

For an Xcode project with the xcode-tools MCP available, list targets with
`XcodeListTargets` — test targets have `isTestTarget: true`. A project can
have **no test target at all**; that is a gap to propose in Step 5, not a
reason to stop.

**Python:** Tests live in `tests/` or alongside source as `test_*.py`.
Framework: pytest (preferred), unittest. Run via `pytest`.

---

## Step 2: Understand what changed

```bash
git diff --staged
git diff
git diff --staged --name-only
git diff --name-only
```

Use staged files if any are staged; otherwise use all changed files.
Read the actual diff — not just file names — to understand what new
behavior was introduced or modified.

---

## Step 3: Find existing tests

```bash
# Rust
find . -name "*.rs" | xargs grep -l "#\[cfg(test)\]" 2>/dev/null
find . -path "*/tests/*.rs" 2>/dev/null

# Swift
find . -name "*Tests.swift" -o -name "*Spec.swift" 2>/dev/null | grep -v .git
grep -rlE '^import (Testing|XCTest)' --include='*.swift' . 2>/dev/null
# Xcode + MCP: GetTestList lists every test with its file path

# Python
find . -name "test_*.py" -o -name "*_test.py" 2>/dev/null | grep -v .git
```

Read relevant existing test files to understand:
- What's already covered
- The established test style and naming conventions in this project
- What helper utilities or fixtures already exist

---

## Step 4: Identify coverage gaps

For each changed source file, reason about:
- What new behavior was introduced (new functions, new code paths, new
  error cases)
- What existing behavior was modified (regression risk)
- What's already covered by existing tests

Focus on behavior, not lines. A function with three distinct behaviors
needs three test cases, not one.

**Don't flag as gaps:**
- Private helpers that are fully exercised through public API tests
- Trivial getters/setters with no logic
- Generated or derived code
- Code the developer has already indicated they don't want tested

**Swift: testability.** A test target sees only `internal` and `public`
declarations, through `@testable import <Module>`. `private` and
`fileprivate` code is reachable only through the types that use it. Logic
inside a SwiftUI `View` body, an `SKScene` subclass, or an app delegate is
hard to test directly; when the important behavior is there, say so in the
proposal and test the plain types it calls instead. Don't propose moving
code just to make it testable — that is a refactor for the user to decide.

---

## Step 5: Propose the test plan

Present a structured proposal.

**No test target yet (Swift/Xcode).** Put this first in the proposal, as
its own approvable item:

```
### New test target: `<AppTarget>Tests`
**Template:** unit-test bundle, testing system Swift Testing
**Host:** <AppTarget> (so `@testable import <AppModule>` works)
**Why:** the project has no test target, so no test below can run without it
```

Find the template identifier and its options with `XcodeListTemplates`.
If the user rejects the target, none of the Swift tests can be written —
say so rather than writing them somewhere else.

For each proposed test:

```
### `test_name` (or @Test func testName / func testName / def test_name)
**What it tests:** [the specific behavior or invariant]
**Setup:** [inputs, state, or fixtures needed]
**Assert:** [what the test checks]
**Why:** [what bug or edge case this would catch — skip if obvious]
```

Group by source file. Mark each as one of:
- **Core** — tests primary happy-path behavior; high value
- **Edge case** — tests boundary or error conditions; medium value
- **Regression** — guards against a specific known-bad behavior

Don't propose:
- Tests that duplicate existing coverage
- Tests of implementation details that would break on refactor
- Exhaustive permutation tests unless the logic specifically warrants it

End the proposal with:

> **Proposed: N tests across M files.**
> Cut any you don't want, or say "approve all" to proceed.
> You can also say "approve core only" to skip edge cases.

---

## Step 6: Write approved tests

Wait for explicit approval. Accepted responses:
- "Approve all" → write everything proposed
- "Approve core only" → write only Core tests
- List of names to approve → write only those
- Edits or additions → incorporate and write

**Rust:** Add tests to the `#[cfg(test)]` module at the bottom of the
source file, or create `tests/test_name.rs` for integration tests.
Follow the project's existing style — if tests use `assert_eq!` and
descriptive names, match that.

**Swift:** If a new test target was approved, create it first with
`XcodeNewTarget` (xcode-tools MCP), then confirm it appears in
`XcodeListTargets`. Without the MCP, tell the user to add it in Xcode
(File ▸ New ▸ Target ▸ Unit Testing Bundle) and stop until it exists —
don't hand-edit `project.pbxproj`.

- **Swift Testing** (default): `@Test` functions, grouped in a `struct`
  (optionally `@Suite("…")`), not a class. Assert with `#expect(...)`; use
  `try #require(...)` to unwrap or to stop when a precondition fails. Use
  `@Test(arguments: [...])` in place of copy-pasted cases, and
  `#expect(throws: SomeError.self) { ... }` for errors. Put shared setup in
  the struct's `init`. Mark a suite `@MainActor` when it touches
  main-actor types (SwiftUI views, `SKScene`).
- **XCTest** (only where the target already uses it): methods on an
  `XCTestCase` subclass, `XCTAssertEqual`, `XCTAssertThrowsError`, etc.
- **UI tests**: XCUIAutomation in a UI-testing target, only when the
  behavior can't be reached below the UI.

For randomness (e.g. a random generator or distribution), inject a seeded
generator if the code already accepts one; otherwise assert on properties
that hold for every value (ranges, invariants), not on exact values. Match
existing naming style.

**Python:** Add functions to the appropriate `test_*.py` file. Use
`assert` statements or `pytest.raises` for exceptions. Use fixtures
if the project already has them.

After writing, show a summary of what was written and where.

---

## Step 7: Offer to run tests

After writing:

> Tests written. Run `/run-tests` to verify they pass?

---

## What not to do

- Don't write any tests before the user approves the proposal
- Don't propose tests for every conceivable input — focus on meaningful behavior
- Don't invent test infrastructure that doesn't exist in the project —
  the one exception is a test target the user approved in Step 5
- Don't write tests that test the language or framework, not the code
- Don't exceed the scope of what changed in this diff