---
name: design-doc
description: Generate or update a technical design document (docs/design.md) from an existing codebase. Use when the user types /design-doc, asks to "document the architecture", "generate a design doc", "write up how this project works", "create a technical overview", or wants to capture the current state of a project as a design document. Also invoke when starting a new project and wanting to establish a living design doc, or when the design doc is stale and needs to reflect recent changes. Synthesizes code structure, README, CLAUDE.md, and existing ADRs into cohesive prose.
---

# Generate Design Document

When invoked, analyze the codebase and produce a `docs/design.md` that
accurately describes the project's architecture, key design decisions, and
structure. This is a *living document* — it should be updated as the
project evolves, not written once and forgotten.

The output is prose-first: narrative paragraphs with supporting structure.
Not a dump of file names. Not bullet points of every function. A document
a new contributor (or future you) could read in 15 minutes and understand
how the system fits together.

---

## Step 1: Gather context

Read in this order, stopping to understand each before moving on:

### 1a. Existing documentation
```bash
cat README.md 2>/dev/null
cat CLAUDE.md 2>/dev/null
cat docs/design.md 2>/dev/null   # existing design doc, if any
```

If `docs/design.md` already exists, note what's there — the goal is to
update it, not overwrite everything. Preserve sections that are still
accurate; revise or replace sections that are stale.

### 1b. Project structure
```bash
find . -type f -name "*.swift" -o -name "*.py" -o -name "*.ts" \
  -o -name "*.rs" -o -name "*.go" -o -name "*.js" \
  | grep -v node_modules | grep -v .build | grep -v .git \
  | head -80
```

Also get the directory tree:
```bash
find . -type d | grep -v node_modules | grep -v .build \
  | grep -v .git | grep -v __pycache__ | sort | head -60
```

### 1c. Key source files
Read the most important files — entry points, core modules, main data
types/models, configuration. Prioritize:
- Entry point (main.swift, main.py, index.ts, main.rs, etc.)
- Core data model files
- Primary business logic files
- Configuration / dependency injection setup
- Any file that many others import

Don't try to read everything. Focus on files that reveal *how the system
is structured*, not every implementation detail.

### 1d. Dependencies
```bash
cat Package.swift 2>/dev/null    # Swift
cat package.json 2>/dev/null     # Node/JS
cat Cargo.toml 2>/dev/null       # Rust
cat requirements.txt 2>/dev/null # Python
cat go.mod 2>/dev/null           # Go
cat *.podspec 2>/dev/null        # CocoaPods
```

### 1e. Existing ADRs
```bash
ls docs/decisions/ 2>/dev/null
cat docs/decisions/README.md 2>/dev/null
```

If ADRs exist, read each one. They contain *why* decisions were made —
that context belongs in the design doc, not just the outcome.

---

## Step 2: Understand the system

Before writing, form a clear mental model:

1. **What does this program do?** One sentence.
2. **Who/what uses it?** A human via CLI? A daemon? An iOS app? An API?
3. **What are the major components?** Name them. Understand their
   responsibilities and how they communicate.
4. **What is the data flow?** Trace a typical request/operation from
   input to output through the system.
5. **What external systems does it depend on?** Files, databases,
   APIs, hardware, OS services?
6. **What design patterns are in use?** (e.g., pipeline, actor model,
   event-driven, MVVM, service layer)

If any of these are unclear from the code, note them as open questions
in the document rather than guessing.

---

## Step 3: Write docs/design.md

Create or update `docs/design.md` using this structure. Adapt section
names to fit the project — don't include sections that don't apply.

```markdown
# [Project Name] — Design Document

*Last updated: YYYY-MM-DD*

---

## Overview

[2–4 sentences. What this program does, who uses it, and why it exists.
This is the elevator pitch for the codebase.]

## Goals and Non-Goals

**Goals:**
- [What this project is explicitly trying to do]

**Non-Goals:**
- [What this project deliberately does not do — important for
  understanding scope and why certain approaches weren't taken]

---

## Architecture

[Narrative description of the overall structure. How are the major
components organized? What is the primary architectural pattern?
This should be prose, not a file listing.]

### Components

[For each major component/module, a paragraph covering:
- What it does (its responsibility)
- What it depends on
- What depends on it
- Any key design choices specific to this component]

**[Component Name]**
[Description...]

**[Component Name]**
[Description...]

### Data Flow

[Walk through a representative operation from start to finish.
"When the user runs X, the program does Y, which triggers Z..."
This is often the most useful section for understanding a system.]

---

## Key Design Decisions

[This section synthesizes the ADRs into a coherent narrative.
For each significant decision, explain:
- The context that made it a real decision
- What was chosen and why
- The trade-off acknowledged

Link to the relevant ADR for full detail: see [ADR-0001](decisions/0001-slug.md)]

---

## External Dependencies

[Table or list of significant external libraries/services with a
one-line note on why each is used. Skip trivial utilities.]

| Dependency | Purpose |
|------------|---------|
| [name] | [why it's here, not just what it is] |

---

## Data Model

[Only if the project has non-obvious data structures. Describe the
key types/entities and their relationships in prose. Code snippets
are OK here if they clarify structure.]

---

## Configuration and Environment

[How is the program configured? Environment variables, config files,
flags? What does a developer need set up to run it?]

---

## Open Questions

[Honest list of things not yet decided, known weaknesses, or areas
where the design might need to evolve. This section makes the doc
trustworthy — a doc with no open questions is either perfect or lying.]

- [ ] [Question or known issue]

---

## Document History

| Date | Change |
|------|--------|
| YYYY-MM-DD | Initial document generated from codebase |
```

---

## Writing guidelines

**Prose over bullets.** The architecture section should read like an
explanation from a knowledgeable colleague, not a list of file names.
Use bullet points only for lists that are genuinely enumerable (dependencies,
open questions, goals).

**Explain *why*, not just *what*.** The code already shows what exists.
The design doc's job is to explain the choices behind the structure.
"The pipeline architecture was chosen because..." is more valuable than
"The system uses a pipeline."

**Be honest about trade-offs.** If a component has a known weakness or
the current approach has limitations, say so in Open Questions. A design
doc that pretends everything is perfect loses credibility.

**Incorporate ADR rationale.** Don't just list that decisions were made —
weave the reasoning into the narrative where it explains the architecture.
Reference the ADR for full detail, but the design doc should be readable
without reading every ADR.

**Scale to the codebase.** A 500-line script needs a shorter design doc
than a 50-file system. Don't pad; don't truncate important context.
Typical length: 400–1000 words of prose.

**Don't invent.** If you can't determine something from the code, note it
as an open question rather than guessing.

---

## Step 4: Create the docs directory if needed

```bash
mkdir -p docs/decisions   # also creates docs/
```

Write the file to `docs/design.md`.

---

## Step 5: Present a summary

Tell the developer:
1. The path written
2. Which sections were generated vs. updated (if updating existing doc)
3. Any open questions you flagged that they should answer
4. Whether any ADRs were incorporated and which ones

Then ask: **"Does this capture the project accurately? Anything
missing or incorrect?"**

If they want revisions, edit in place.

---

## Step 6: Offer next steps

After confirmation, offer:

- "Want me to stage this for your next commit?"
- If no ADRs exist yet: "This project has no ADRs yet. Want to run
  `/capture-decision` to start capturing the decisions behind some of
  these design choices?"
- If the README seems thin relative to the design doc: "The README
  looks light compared to what's in the design doc — want me to
  update it too?"

---

## What not to do

- Don't list every file and function — that's not a design doc, that's
  an index
- Don't invent architectural decisions not visible in the code or ADRs
- Don't write a generic template with placeholder text — every section
  should reflect this specific codebase
- Don't make the document longer than it needs to be
- Don't skip the Open Questions section — it's what separates a useful
  doc from a polished fiction
