---
name: project-review
description: Thorough tech debt and architecture audit of the current codebase. Produces docs/reviews/PROJECT_REVIEW.md with file-cited findings, severity, effort estimates, and a required "looks bad but is actually fine" section. Use when the user asks for a debt audit, codebase health check, architecture review, code quality assessment of an entire repo, or asks conversationally what to work on next in this project — e.g. "what should I work on next", "what needs to be done in this repo", "find issues to fix", "audit this codebase", "I just inherited/resurrected this repo, where should I start". Triggers on repo-wide triage intent, not on requests about a single file or function.
disable-model-invocation: false
---

<!--
  Base skill: ksimback/tech-debt-skill (MIT license)
  https://github.com/ksimback/tech-debt-skill

  Local customizations for Peter's stack and priorities:
    - Phase 1.5: ingest existing /code-review reports as evidence (not merged rows)
    - Phase 2, dimension 10: UX & CLI ergonomics (new)
    - Phase 2, dimension 11: Idiom debt (new — learning-value framing, mirrors the /code-review skill)
    - Phase 3: idiom-floor note for ranking + "Related tactical findings" appendix
    - Stack-specific tooling: added Swift and C/C++ (upstream only covered TS/JS, Python, Rust, Go)
    - Model-invocation enabled with conversational trigger phrases (upstream was explicit-only)
  Everything else is unmodified from upstream. Re-diff against upstream periodically
  in case the base skill improves; these additions are designed to layer cleanly on top.
-->

# Project Review

A skill that conducts a deliberate, opinionated audit of an entire codebase and produces `docs/reviews/PROJECT_REVIEW.md` with cited findings.

When invoked via `/project-review`, follow the protocol below. Everything from here through the `---` divider is the protocol to execute. The section after the divider is documentation for humans installing or maintaining this skill.

---

## Operating principles

Find what's actually wrong. Not diplomatic. Not surface-only. Don't pattern-match to generic best practices without grounding in this specific repo. No sycophancy. No "overall the codebase is well-structured" filler.

Cite `file:line` for every concrete finding. Vague claims like "the code generally..." don't count. Read code before judging it — a pattern that looks wrong in isolation may be load-bearing.

## Phase 1: Orient

Do not skip this. Forming opinions before understanding the system produces bad audits.

1. Read the README, package manifest (`package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` / `Package.swift` / `CMakeLists.txt`), and any architecture docs in `/docs` or `/adr`.
2. Map the directory structure and identify the major modules / layers.
3. Run `git log --oneline -200` and `git log --stat --since="6 months ago"` to see what's actually changing and where churn concentrates.
4. Identify entry points, hot paths, and cold corners.
5. List the top 20 largest files by line count, and the 20 files most frequently modified in the last 6 months. The intersection is where debt usually hides.
6. Publish a plan using your environment's task-tracking mechanism (e.g. a todo/plan list) so the user can see progress through the phases.

Write a 1–2 paragraph mental model of the architecture before proceeding. If your model contradicts the README, flag it — that itself is a finding.

## Phase 1.5: Ingest existing /code-review reports (evidence, not rows)

Check `docs/reviews/` for prior `/code-review` output. If any exist:

1. Read each report's frontmatter for `git_sha` and `generated_at`. If a report has no frontmatter, treat it as fully stale and skip it — regenerate isn't your job, just note it in Open Questions.
2. For each report, run `git log --oneline <sha>..HEAD -- <file>` per cited file to check whether that specific file has changed since the report was generated. Discard findings for files that have changed; keep findings for files that haven't. This is per-file staleness, not per-report — a report can still be mostly valid even if a couple of its files have since moved on.
3. Do **not** copy individual `/code-review` findings into this audit's Findings table. Instead, use them as evidence for judgment calls in Phase 2:
   - If the same category of tactical issue (e.g. non-idiomatic error handling, a repeated anti-pattern) recurs across 3+ files in one or more `/code-review` reports, that recurrence is itself an architectural signal. Roll it up into a single finding under the relevant Phase 2 dimension (usually Consistency rot or Idiom debt), citing the pattern and referencing the report rather than restating every instance.
   - Otherwise, leave it out of the table entirely. It belongs to `/code-review`'s document, not this one.
4. In Phase 3, add a **Related tactical findings** line pointing at the relevant `docs/reviews/*.md` report(s) rather than duplicating their contents.

The goal: this audit stays architectural and macro. `/code-review` stays the tactical, line-level record. Ingesting `/code-review` data should only ever *promote* a pattern to architectural status when the evidence supports it — never dilute this report with line-item noise.

## Phase 2: Audit across these dimensions

Use `rg`, `ast-grep`, and language-native tooling to find concrete examples. Cite `path/to/file.ext:LINE` for every finding.

1. **Architectural decay** — circular deps, layering violations, god files (>500 LOC) and god functions, duplicated logic across 3+ sites where an abstraction should exist, abstractions that exist but nobody uses, dead code (unused exports, unreachable branches, stale commented-out blocks).
2. **Consistency rot** — multiple ways of doing the same thing (HTTP clients, error handling, logging, config loading, validation, date handling). Naming drift. Folder structure that no longer reflects what the code actually does.
3. **Type & contract debt** — `any` / `unknown` / `as any` / `# type: ignore` / loose dicts. Untyped API boundaries. Missing schema validation at trust boundaries.
4. **Test debt** — run coverage if available; identify gaps on critical paths. Tests that assert implementation rather than behavior. Skipped or flaky tests. High-churn files with no tests.
5. **Dependency & config debt** — `npm audit` / `pip-audit` / `cargo audit` for CVEs. Unused deps. Duplicate deps doing the same job. Env var sprawl (referenced but not documented; defaults inconsistent across envs).
6. **Performance & resource hygiene** — N+1 queries, sync work in async paths, blocking I/O on hot paths, uncleaned listeners or handles, unnecessary serialization, algorithmically inefficient choices (e.g. O(n²) where O(n log n) is straightforward, repeated re-computation of invariant values, unnecessary allocations in hot loops).
7. **Error handling & observability** — swallowed exceptions, blanket catches, errors logged but not handled, inconsistent error shapes across modules, missing structured logs on critical paths.
8. **Security hygiene** — hardcoded secrets, string-concat SQL, missing input validation at trust boundaries, permissive auth or CORS, weak crypto.
9. **Documentation drift** — README claims that don't match reality, comments that contradict adjacent code, public APIs without docstrings.
10. **UX & CLI ergonomics** — confusing, inconsistent, or non-standard CLI argument/flag names; missing or unhelpful `--help` output; error messages that describe the problem but not what to do next; silent flag conflicts or precedence surprises; inconsistent verb/noun conventions across subcommands; poor discoverability of existing features. Applies to CLI tools, TUIs, and any dev-facing interface; write "N/A — no user-facing interface" for pure libraries rather than skipping the section.
11. **Idiom debt** — code that works but isn't idiomatic for its language: patterns a fluent Rust/Swift/Python/C++ engineer would flag on sight, or that would raise an eyebrow in a technical interview (e.g. manual `fopen`/`fclose` in C++ instead of RAII, index-loop iteration instead of iterators/ranges, manual `Option` unwrapping instead of combinators, force-unwraps in Swift where optional binding is idiomatic). Tag these `IDIOM` rather than folding them into Consistency rot — they're flagged for language-fluency value as much as for maintenance cost, and should be called out even when their maintenance-impact severity alone would be Low.

## Phase 3: Deliverable

Write to `docs/reviews/PROJECT_REVIEW.md` with this structure:

* **Executive summary** — max 10 bullets, ranked by impact.
* **Architectural mental model** — your understanding of the system as it actually is.
* **Findings table** — columns: `ID | Category | File:Line | Severity (Critical/High/Medium/Low) | Effort (S/M/L) | Description | Recommendation`. Aim for 30–80 findings; padding past that is noise. `IDIOM`-category findings carry a ranking floor of Medium regardless of maintenance-impact severity, since language-fluency value counts as impact here — note the true maintenance severity in the description if it's lower.
* **Related tactical findings** — 1–3 bullets pointing at relevant `docs/reviews/*.md` reports (still-fresh per Phase 1.5) for line-level detail this audit intentionally doesn't restate. Omit this section if no `/code-review` reports exist yet.
* **Top 5 "if you fix nothing else, fix these"** — with concrete diff sketches or refactor outlines, not vague advice.
* **Quick wins** — Low effort × Medium+ severity, as a checklist.
* **Things that look bad but are actually fine** — calls you considered flagging and chose not to, with reasoning. **This section is required.** If it's empty, you didn't look hard enough.
* **Open questions for the maintainer** — things you couldn't tell were debt vs. intentional.

## Rules

* Cite `file:line` for every concrete finding.
* If unsure whether something is debt or intentional, ask in the open questions section — don't assert.
* Don't recommend rewrites. Recommend specific, scoped changes.
* Don't pad. If a category has nothing material, write "Nothing material" and move on.
* No sycophancy. Tell the user what's broken.

## Stack-specific tooling

Detect the stack from the manifest and run the relevant tools. Run them in parallel when possible.

* **TypeScript / JavaScript** — `npm audit`, `npx knip` (dead exports), `npx madge --circular` (circular deps), `npx depcheck` (unused deps), `tsc --noEmit` for type drift.
* **Python** — `pip-audit`, `ruff check`, `vulture` (dead code), `pydeps --show-cycles`, `mypy --strict` for type drift.
* **Rust** — `cargo audit`, `cargo udeps`, `cargo machete`, `cargo clippy -- -W clippy::pedantic`.
* **Go** — `govulncheck`, `go vet`, `staticcheck`, `golangci-lint run`.
* **Swift** — `swiftlint` (style and idiom violations), `swift build` warnings (treat unaddressed warnings as findings), `periphery scan` (dead code/unused declarations), `swift package show-dependencies` for dependency graph review.
* **C / C++** — `clang-tidy` (idiom, modernization, bug-prone patterns), `cppcheck`, `clang --analyze` (Clang Static Analyzer), `include-what-you-use` for header/include hygiene where practical.

If a tool isn't installed, note it in the audit and move on rather than blocking. Do not install dev tools globally without permission.

## Large repos: spawn subagents

If the repo is >50k LOC or has >5 top-level modules, and your environment supports dispatching parallel subagents, spawn one per module and synthesize their reports. Serial reading on a large repo eats the context window before findings can be written.

Each subagent gets: scope (one module), the dimensions list above, the citation requirement, and a 200-finding cap. The main agent merges, dedupes, and ranks.

If parallel subagent dispatch isn't available, read serially but prioritize the highest-signal areas first (largest files, highest-churn files from Phase 1) so the audit still produces cited findings within the context budget.

## Repeat-run mode

If `docs/reviews/PROJECT_REVIEW.md` already exists, read it first. Mark resolved findings as `RESOLVED`, update stale ones, and tag new findings with `NEW`. This turns the audit into a living document tracked over time.

---

# Project documentation

Everything below is for humans installing, using, or contributing to this skill. It is not part of the audit protocol.

## Installation

Personal install (available across all your projects — recommended, since this is meant to run on any repo you inherit or resurrect). Use your agent CLI's global skills directory, e.g. `~/.claude/skills` for Claude Code or `~/.codex/skills` for Codex:

```bash
mkdir -p ~/.claude/skills/project-review
# copy this file to ~/.claude/skills/project-review/SKILL.md
```

Or for a project-only install (just this repo, overriding the global one):

```bash
mkdir -p .claude/skills/project-review
cp /path/to/this/SKILL.md .claude/skills/project-review/SKILL.md
```

Verify it loaded — the check is CLI-specific, e.g. for Claude Code:

```bash
echo "/skills" | claude
```

## Usage

In your agent CLI, in the repo you want audited:

```
/project-review
```

Output goes to `docs/reviews/PROJECT_REVIEW.md`. First run takes 5–20 minutes depending on repo size; subsequent runs in repeat-run mode are faster.

Scope to a subdirectory for a large or unfamiliar repo:

```
/project-review src/payments
```

## How this fits with `/code-review`

`/project-review` is whole-repo and architectural — run it first on a newly inherited or resurrected repo to find where the debt actually concentrates (god modules, dependency rot, doc drift, missing tests). Then use `/code-review` on the specific files or folders it flags, for line-level, iterative fixing with idiom scoring and a "what's next" workflow. Don't run `/code-review` on an entire unfamiliar repo cold — that's what this skill's Phase 1 orientation is for.

The two outputs are kept deliberately separate rather than merged into one ranked list: `/project-review` stays architectural/macro, `/code-review` stays tactical/line-level. `/project-review` reads `/code-review`'s reports (Phase 1.5) purely as evidence — a tactical pattern that recurs across enough files gets rolled up into a single architectural finding here, but individual `/code-review` line items are never copied into this report's table. See the **Related tactical findings** section of the output for pointers back to the relevant `/code-review` reports instead.

**Required change to `/code-review` for this to work:** its saved reports in `docs/reviews/*.md` need frontmatter recording the commit they were generated against, so this skill can check per-file staleness:

```yaml
---
git_sha: a1b2c3d
generated_at: 2026-07-10T14:32:00-07:00
scope: src/
---
```

Without this, Phase 1.5 treats the report as stale and ignores it rather than guessing.

## Philosophy (from upstream)

Most "code review" prompts produce a bulleted list of generic best-practice violations dressed up as findings. This skill is built to avoid that failure mode. Three design choices do most of the work:

**Forced orientation before judgment.** Phase 1 isn't optional decoration. Without a real mental model of the architecture, every Phase 2 finding is just pattern-matching against generic heuristics. Reading `git log` for churn data is what surfaces the files that *actually* have debt versus the files that just look messy.

**File:line citations on every finding.** This is the single biggest quality lever. A finding without a citation is a vibe. Vibes don't get fixed.

**The "looks bad but is actually fine" section is required.** This is the one most people remove when adapting the prompt. Don't. Forcing the model to surface the calls it considered making and chose not to is what separates a real audit from a checklist regurgitation. If that section is empty, the audit is shallow.

The skill also explicitly forbids recommending rewrites and forbids padding categories. Both are common LLM failure modes — rewriting is easier than diagnosing, and padding makes outputs feel thorough when they aren't.

## Adaptation notes

**Project-level overrides.** A `.claude/skills/project-review/SKILL.md` (or your agent CLI's equivalent project-local skills path) in a specific repo overrides the global one. Useful for a repo that needs still-more-custom dimensions on top of these.

**Mid-audit course correction.** After Phase 1 completes, you can interrupt with: *"Before Phase 2, tell me what surprised you in Phase 1 and what you want to investigate that isn't in the dimensions list."*

**Tuning severity calibration.** If the model is over- or under-flagging, edit the Phase 2 dimensions list to add explicit thresholds (e.g. tighten "god files (>500 LOC)" for small personal projects where 500 LOC is already most of the codebase).

## Limitations

This is a static audit, not a security audit or a business-logic reviewer. It can't tell intentional simplicity from accidental simplicity — the open-questions section exists for exactly that reason.

For very large repos (>200k LOC), even subagent dispatch can produce shallow results — scope to a module instead.

## License

MIT, inherited from upstream (ksimback/tech-debt-skill). Local additions (dimensions 10–11, Swift/C/C++ tooling) are yours to modify freely.

## Credits

Base protocol built on the Claude Code Agent Skills standard by ksimback (https://github.com/ksimback/tech-debt-skill). Local UX/CLI, idiom-debt, and Swift/C/C++ additions layered on top for a solo-developer, multi-language personal project workflow.