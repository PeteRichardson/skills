# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A collection of personal Claude Code skills. Each top-level directory is one skill containing a `SKILL.md` (plus occasional support files, e.g. `onote/troubleshooting.md`, `onote/README.md`). There is no build, lint, or test tooling — the "code" is Markdown instructions executed by Claude.

**Live deployment:** skills live in two real roots: this repo, and `~/.agents/skills` (Matt Pocock's skills, installed by `npx skills`, tracked in `~/.agents/.skill-lock.json`; never edit those). Hermes (`skills.external_dirs` in `~/.hermes/config.yaml`) and Pi (`skills` in `~/.pi/agent/settings.json`) read both roots directly. Claude Code has no setting for extra roots, so `~/.claude/skills` holds only symlinks into both roots, made by `skills-link` in `shell_scripts.sh`, plus a symlink for `WORKFLOW.md`, which eight skills read at `~/.claude/skills/WORKFLOW.md`. Any edit to a `SKILL.md` here takes effect immediately in new sessions — there is no publish step. A **new** skill needs `skills-link` run; renaming or deleting a directory breaks its symlink.

**Names must not collide** across the two roots: Hermes and Pi load neither of two skills with one name. When a name collides, this repo keeps the name and the other skill is removed from the lock file and from `~/.agents/skills`. This was done for `code-review` on 2026-11-06; Matt's version is vendored as `code-review/engines/matt-code-review.md`, the `--engine matt` of `/code-review`.

**`WORKFLOW.md`** documents how seven of these skills chain into one pipeline — `/project-review` + `/code-review` → `/make-issues` → `/issue-triage` → `/fix-order` → `/work-issue` → `/merge-order` → manual merge — and where Matt Pocock's skills join it. Read it before changing any of those seven, or `/pipeline`, which detects where a repo sits in that chain. Each of the seven ends its run by naming the next command (their "Next in the pipeline" sections); those hand-offs and `pipeline/pipeline-status`'s detection cascade both need updating if a stage's inputs, outputs, or artifact paths change.

## Skill conventions

Frontmatter fields used across this repo:

- `name`: matches the directory name (kebab-case). The slash command is `/<name>`.
- `description`: doubles as the invocation trigger — it must spell out the slash command and the natural-language phrases that should activate the skill ("Use when the user types /X, says '...'").
- `disable-model-invocation: true`: user-invoked only; Claude won't auto-trigger it (e.g. `project-review`).
- `user-invocable: false` + `disable-model-invocation: true`: background knowledge skills that are only referenced by other skills, never invoked directly.

Skills compose by referencing each other by slash command or name rather than duplicating logic: `pre-commit` reuses `/run-tests` detection logic, `update-docs` delegates to `/design-doc`. When changing a skill, grep the other `SKILL.md` files for its name to find dependents — renames must update those references.

Structural patterns to preserve when editing:

- Skills are written as step-by-step protocols ("Step 1 / Step 2"), often with decision tables for branching situations and explicit "What not to do" sections.
- Some skills (e.g. `project-review`) separate the protocol Claude executes from human maintainer documentation with a `---` divider; keep content on the correct side.
- Read-only skills (e.g. `commit-message` generates a message but never runs `git commit`) state their boundaries explicitly — don't loosen them.
- `project-review` derives from `ksimback/tech-debt-skill` (MIT); keep the attribution comment.

## Commits

Conventional commits with the skill directory as scope: `feat(onote): ...`, `refactor(readme): ...`, `chore(commit): ...`.
