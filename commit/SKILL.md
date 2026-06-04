---
name: commit
description: Generate a conventional commit message from staged or recent changes and optionally run `git commit`. Use this skill when the user types /commit, asks for a commit message, says "let's commit this", "write a commit for this", or finishes a feature and wants to check in their work.
---

# Conventional Commit Message Generator

When invoked, analyze the current git state and generate a high-quality conventional commit message, then offer to commit.

## Step 1: Read the diff

Run these to understand what changed:

```bash
git diff --staged        # what's staged
git diff                 # unstaged changes (for context)
git status               # overall picture
```

If nothing is staged, note this and show `git status` output so the user knows — don't try to guess or commit everything blindly.

## Step 2: Generate the message

Produce a conventional commit with a **title** and an optional **body**.

### Title format

```
<type>(<scope>): <short description>
```

- **type**: one of `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`
- **scope**: the module, file, or subsystem affected — omit if it's truly global or obvious from the description
- **description**: imperative mood, lowercase, no period, ≤72 chars total for the full title line

### Body (include when helpful)

Separate from the title with a blank line. Use the body to explain *why* the change was made, not *what* (the diff shows what).

**Prefer bullet points over prose.** Use `-` as the bullet prefix (not `*` or `•`). Each bullet should be a single thought. Example:

```
- previously expired tokens caused silent logout
- now retries once with refreshed token before prompting re-auth
- BREAKING CHANGE: refresh endpoint must be configured separately
```

Include bullets for:
- Motivation or context a future reader would want
- Non-obvious side effects or constraints
- Any breaking changes: `BREAKING CHANGE: <description>`

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

Use the name of the affected module, directory, or feature area. Examples: `auth`, `parser`, `api`, `cli`, `db`, `ui`. Skip scope for sweeping cross-cutting changes.

## Step 3: Present the message

Show the proposed commit message in a code block, clearly separated so the user can read and copy it easily:

```
feat(auth): add JWT token refresh on 401 response

- expired tokens previously caused silent logout with no feedback
- client now detects 401, refreshes token, and retries once
- prompts re-authentication only if refresh also fails
```

Then ask: **"Looks good to commit, or would you like to adjust anything?"**

Offer a few quick alternatives if the type or scope is ambiguous — don't hedge on every word, just mention the one or two genuine choices.

## Step 4: If the user approves

**Shell-agnostic method (required when there is a body; works in nushell, bash, zsh, fish):**

1. Use the **Write tool** to write the commit message to `.git/COMMIT_EDITMSG`. The Write tool is shell-independent — do not use shell redirects or heredocs. This file lives inside the project so no extra permissions are needed.
2. Run: `git commit -F .git/COMMIT_EDITMSG`

The file content should be the title, a blank line, then the body — exactly as shown in Step 3.

**Title-only shortcut (no body):** A single `-m` flag is fine in all shells:
```bash
git commit -m "chore(deps): bump serde to 1.0.197"
```

Do NOT use `-m "<title>" -m "<body>"` when the body spans multiple lines — this breaks in nushell.

After committing, confirm success by showing the one-line output of `git log --oneline -1`.

## What not to do

- Don't stage files on the user's behalf — only commit what's already staged
- Don't invent context you can't see in the diff
- Don't use past tense ("added", "fixed") — use imperative ("add", "fix")
- Don't include the ticket number or branch name unless it's visible in the diff or the user mentions it
