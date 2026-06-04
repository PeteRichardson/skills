---
name: comment
description: Generate and insert descriptive comments into code without modifying
  any logic. Use when the user types /comment, asks to "add comments", "document
  this code", "comment the sorting function", or wants doc-comments, docstrings,
  or inline comments added to a file or specific section.
---

# Code Comment Generator

Analyze the specified code and insert high-quality comments. Use tone, style,
syntax, and format appropriate for the language and project.

**CRITICAL CONSTRAINT: You may only insert comments or make minimum-justified
changes to existing comments (see Step 3: Handling existing comments). You must
not modify, reformat, reorder, delete, or otherwise alter any non-comment code.
If you strip all comments from both the original and the result, the remaining
code must be byte-for-byte identical (modulo whitespace required to indent an
inserted comment).**

---

## Step 1: Determine the scope

This skill accepts an optional hint via `$ARGUMENTS`.

- **No hint provided**: Comment the entire current file.
- **Hint provided** (e.g., `/comment the sorting logic`): Parse the hint to identify
  the target — a specific function/class name, a logical section, or a module.

If the hint is ambiguous, ask the user to clarify before proceeding.

### Resolving the scope from a hint

When the hint names a type (class, struct, enum, protocol, interface):
- Include the type declaration itself **and** all associated implementation
  blocks, extensions, conformances, and trait implementations, even if they
  appear in different locations in the file.
- If associated code spans multiple files (e.g., Swift extensions in separate
  files), note this to the user and ask whether to expand scope.

When the hint names a function or method (indicated by `()` or a recognizable
function name):
- Target that specific function/method body and its signature.
- If the name is overloaded, comment all overloads unless the user specifies
  otherwise.

---

## Step 2: Read the target code

Determine the file to read using the first applicable source:
1. A filename mentioned by the user in the invocation
2. The file currently open or most recently edited in context
3. If neither is clear, ask the user before proceeding

Read it fully before writing any comments:

```bash
cat <path/to/file>
```

Understand the logic, control flow, and any non-obvious patterns. Do not make
any changes during this step.

---

## Step 3: Insert comments — only comments

### Core principles

**Explain *why*, not *what*.** The code already shows what it does. Comments should
explain the reasoning behind an implementation — why a particular approach was
chosen, what constraint motivated it, what invariant must hold.

**Don't comment obvious things.** A comment that restates the code adds clutter,
incurs maintenance cost, and can become misleading when the code changes.

**If the code is too unclear to comment, say so — don't fix it.** If you cannot
explain a section without also changing it, stop and ask the user: describe what
is unclear and why, and let them decide how to proceed. Do not refactor or rewrite.

---

### Handling existing comments

Before writing any comment, check whether one already exists at that location.

**If a comment already exists:**
- Read it carefully and assess whether it is still accurate and adequate.
- **Preserve it unchanged** unless one of the following is true:
  - The code it describes has materially changed (new algorithm, new
    behavior, changed parameters, added/removed dependencies)
  - It is factually wrong or actively misleading
  - It is so incomplete that it omits something a reader would need

**If none of those conditions are met, leave the comment alone.** Do not
reword it, reformat it, or "improve" the phrasing. A comment that says the
same thing in different words is a noise commit.

**If a condition is met**, make the minimum change that addresses it:
- Add a sentence for new behavior rather than rewriting the whole comment
- Correct the specific incorrect claim rather than replacing the block
- Do not change parts of the comment that are still accurate

**What not to do:**
- Don't rewrite a correct comment because you'd phrase it differently
- Don't reformat a comment to match your preferred style if it's consistent
  with the file's existing style
- Don't "improve" grammar or wording unless it causes genuine ambiguity

This policy applies to docstrings as well — update only the specific field
(e.g., a renamed parameter) rather than regenerating the entire docstring.

---

### What to comment

**Complex or non-obvious logic**
If a reader would stop and wonder "why is this done this way?", comment it.
Unidiomatic code especially needs explanation — a comment saves future readers
from "simplifying" something that is actually essential.

**Assumptions and preconditions**
State any assumptions required for the code to function correctly: expected input
ranges, required initialization order, invariants that must hold.

**Non-obvious external references**
Link to the spec, RFC, Stack Overflow answer, or algorithm source that explains
why the code does what it does.

---

### Docstrings / doc-comments for functions and classes

Add a structured doc-comment in the language's native format for every public
function, class, and module that lacks one:

| Language | Format | Key tags |
|---|---|---|
| Python | docstring (Google, NumPy, or reST) | `Args:`, `Returns:`, `Raises:` |
| JavaScript / TypeScript | JSDoc (`/** ... */`) | `@param`, `@returns`, `@throws` |
| Java | Javadoc (`/** ... */`) | `@param`, `@return`, `@throws` |
| Swift | Doc comment (`/// ...`) | `- Parameter`, `- Returns`, `- Throws` |
| Rust | Doc comment (`/// ...`) | prose + `# Examples` |
| C/C++ | Doxygen (`/** ... */`) | `@param`, `@return` |

Follow language-specific conventions (PEP 257 for Python, Javadoc for Java, etc.)
and match the existing style in the file.

A good docstring covers:
- **One-line summary** — present tense, action verb ("Return the sum of…")
- **Parameters** — name, type, purpose, constraints
- **Return value** — what is returned and when
- **Exceptions/errors** — what can be raised and why
- **Usage example** — for non-trivial functions

---

### Formatting

- Leave a space after the comment delimiter (`// comment`, `# comment`)
- Indent comments to match the surrounding code
- Match the capitalization and punctuation style already in the file

---

### What *not* to do

- **Don't restate the code** — `i = i + 1 // increment i` adds nothing
- **Don't delete dead code** — that's a separate task; leave it alone
- **Don't add TODO/FIXME markers** — you didn't write this code; don't editorialize
- **Don't fix bugs, refactor, or reformat** — insert comments only
- **Don't introduce a new comment style mid-file** — match what's already there

## Step 4: Report

After inserting comments, briefly tell the user:
- Which functions/sections received new comments
- Which existing comments were modified and why (one line per change)
- Which existing comments were left unchanged (no need to list each one —
  just confirm that preservation was applied)

Do not show a diff or reprint the whole file unless the user asks.
