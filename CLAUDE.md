# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A collection of personal Claude Code skills. Each top-level directory is one skill containing a `SKILL.md` (plus occasional support files, e.g. `onote/troubleshooting.md`, `onote/README.md`). There is no build, lint, or test tooling — the "code" is Markdown instructions executed by Claude.

**Live deployment:** `~/.claude/skills` is a symlink to this repo. Any edit to a `SKILL.md` here takes effect immediately in new Claude Code sessions — there is no install or publish step. Renaming or deleting a directory removes that skill.

## Skill conventions

Frontmatter fields used across this repo:

- `name`: matches the directory name (kebab-case). The slash command is `/<name>`.
- `description`: doubles as the invocation trigger — it must spell out the slash command and the natural-language phrases that should activate the skill ("Use when the user types /X, says '...'").
- `disable-model-invocation: true`: user-invoked only; Claude won't auto-trigger it (e.g. `project-review`).
- `user-invocable: false` + `disable-model-invocation: true`: background knowledge skills that are only referenced by other skills, never invoked directly (`adr-template`, `adr-best-practices`).

Skills compose by referencing each other by slash command or name rather than duplicating logic: `pre-commit` reuses `/run-tests` detection logic, `update-docs` delegates to `/design-doc`, `capture-decision` builds on `adr-template` and `adr-best-practices`. When changing a skill, grep the other `SKILL.md` files for its name to find dependents — renames must update those references.

Structural patterns to preserve when editing:

- Skills are written as step-by-step protocols ("Step 1 / Step 2"), often with decision tables for branching situations and explicit "What not to do" sections.
- Some skills (e.g. `project-review`) separate the protocol Claude executes from human maintainer documentation with a `---` divider; keep content on the correct side.
- Read-only skills (e.g. `commit-message` generates a message but never runs `git commit`) state their boundaries explicitly — don't loosen them.
- `project-review` derives from `ksimback/tech-debt-skill` (MIT); keep the attribution comment.

## Commits

Conventional commits with the skill directory as scope: `feat(onote): ...`, `refactor(readme): ...`, `chore(commit): ...`.
