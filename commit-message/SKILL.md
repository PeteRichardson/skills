---
name: commit-message
description: Generate a conventional commit message from staged or changed files. Use when the user types /commit-message or /commit, asks for a commit message, says "write a commit for this", or finishes a feature and wants a message to paste into their Git client.
---

# Conventional Commit Message Generator

When invoked, analyze the current git state and generate a high-quality conventional commit message to copy into your Git client.

## Step 1: Read the diff

Run these to understand what changed:

```bash
git status
git diff --staged
git diff
```

**Determine what to use for the commit message:**

| Situation | What to do |
|-----------|-----------|
| Files are staged | Use `git diff --staged` only. Ignore unstaged changes. |
| Nothing staged, but files changed | Use `git diff` for all changed files. Show a warning (see below). |
| Nothing staged, nothing changed | Tell the user there's nothing to commit and stop. |

**Warning to show when nothing is staged:**

> ⚠️ **No files are staged.** The message below is based on all changed (unstaged) files. Stage the files you want before committing in your Git client.

## Step 2: Generate the message

Produce a conventional commit with a **title** and an optional **body**.

### Title format

```
<type>(<scope>): <short description>
```

- **type**: one of `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`
- **scope**: the module, file, or subsystem affected — omit if truly global or obvious
- **description**: imperative mood, lowercase, no period, ≤72 chars total for the full title line

### Body (include when helpful)

Separate from title with a blank line. Explain *why*, not *what* (the diff shows what). Include:
- Motivation or context a future reader would want
- Non-obvious side effects or constraints
- Breaking changes: `BREAKING CHANGE: <description>`

Keep body lines ≤72 chars.

### Type selection guide

| Type | When to use |
|------|------------|
| `feat` | New capability visible to users or callers |
| `fix` | Bug correction |
| `refactor` | Restructuring without behavior change |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `docs` | Documentation only |
| `chore` | Build, deps, tooling, config |
| `style` | Formatting, whitespace, no logic change |
| `ci` | CI/CD pipeline changes |
| `build` | Build system changes |

### Scope selection guide

Use the affected module, directory, or feature area (e.g. `auth`, `parser`, `api`, `cli`). Skip scope for sweeping cross-cutting changes.

## Step 3: Present the message

Show the proposed commit message in a code block:

```
feat(auth): add JWT token refresh on 401 response

Previously, expired tokens caused the user to be silently logged out.
Now the client detects a 401, attempts a refresh, and retries the
original request once before prompting re-authentication.
```

If the type or scope has one or two genuine alternatives, briefly mention them. Don't hedge on every word.

That's it — no offer to run `git commit`. The user will paste this into their Git client.

## What not to do

- Don't run `git commit` or `git add` — message generation only
- Don't invent context you can't see in the diff
- Don't use past tense ("added", "fixed") — use imperative ("add", "fix")
- Don't include ticket numbers or branch names unless visible in the diff or mentioned by the user
