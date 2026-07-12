---
name: onote
description: Summarize a Claude session into a structured Obsidian-ready .md file. Use when you want to capture learnings from a conversation, preserve decisions made, and create a reference note for future recall. Triggered by /onote or "create an obsidian note" or "turn this session into a note". Extracts significant learnings, captures concrete artifacts (code, commands, links), includes decision trade-offs, and organizes with confidence levels and YAML frontmatter suitable for Obsidian vaults.
---

# Onote: Session-to-Obsidian Skill

Summarize Claude conversations into structured Obsidian notes that preserve learnings, decisions, and actionable artifacts.

## When to Use

Type `/onote` or ask to "create an Obsidian note from this session" when you want to:
- Convert a learning session into a permanent reference you'll re-read
- Capture decisions and why you made them (prevents circular rework)
- Extract code examples, commands, and tool recommendations
- Flag unresolved questions for follow-up
- Create notes that link together if multiple topics emerged

## How to Use

**Trigger the skill:**
```
/onote
```

Or describe what aspect of the session to capture:
```
/onote focus on the Rust async patterns
```

**The skill will:**
1. Analyze the full conversation for context, questions asked, and answers given
2. Extract 3–5 significant learnings (applying explicit criteria)
3. Organize findings into a structured markdown file with YAML frontmatter
4. Save the file directly to the vault: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/technical/`
5. Suggest related notes if the session spans multiple domains

---

## Output Structure

The generated .md file follows this template:

```yaml
---
tags: [session-summary, your-topic-tag]
date: YYYY-MM-DD
related: [[related-note-1]], [[related-note-2]]
status: raw
confidence: {high|medium|low}
---

# [Session Title / Topic]

## Context & Problem Statement
[What problem were you trying to solve? What constraints/assumptions apply? What prior knowledge did you have?]

## Key Learnings

### Learning 1: [Concise Title]
**Core insight:** [1-2 sentence summary of what you learned]

**Confidence:** [Confirmed | Provisional | Hypothesis]

**Key details:**
- Detail 1
- Detail 2

**Example / Code:**
\`\`\`language
code snippet or command
\`\`\`

**References:**
- [Link to relevant doc/tool]
- [Stack Overflow, GitHub, etc.]

**Gotchas/Caveats:**
- Important caveat 1
- When this doesn't apply

---

### Learning 2: [Next learning...]
[Same structure as above]

## Decisions Made

| Decision | Chosen | Rejected | Reason |
|----------|--------|----------|--------|
| [What decision?] | [Option A] | [Option B] | [Why A won] |

## Questions Remaining
- [Unresolved question 1 — impact/importance]
- [Unresolved question 2]

## Next Steps / Actions
- [ ] Concrete action 1 (with tool/command if needed)
- [ ] Concrete action 2
- [ ] Follow-up session on [topic] when you have time
```

---

## Criteria for "Significant Learning"

A learning is **significant** if it meets any of these:
- ✅ **New concept/pattern:** You discovered or understood something you didn't know before (e.g., "Tokio's work-stealing scheduler vs. thread pools")
- ✅ **Changed your approach:** You learned a better or different way to do something (e.g., "Use `await` at call site, not at function def")
- ✅ **Solved a problem:** You got a concrete answer to a blocker (e.g., "HID reports decode as [raw bytes]; use hidapi to parse")
- ✅ **Tool/command you'll reuse:** You learned a command, library, or workflow you'll use again (e.g., `git reset --soft HEAD~1`)
- ✅ **Mental model shift:** Your understanding of how something works fundamentally changed

A learning is **not significant** if:
- ❌ It's just confirmation of what you already knew
- ❌ It's meta-commentary about the conversation itself ("you did a good job explaining")
- ❌ It's a small clarification that won't resurface

**Collapse or split:**
- If the session spans multiple domains (e.g., Rust async + macOS file permissions), create separate notes and link them
- If two learnings are closely related, nest them under one heading with subheadings
- If a learning is a tangent that took 20% of the conversation, consider a separate "Bonus Note: [Topic]" section or separate file

---

## What to Capture in "Concrete Artifacts"

For each learning, include:

1. **Code snippets** (if applicable)
   - Executable example showing the concept
   - Minimal viable example, not production code
   - Language-specific idioms if relevant

2. **Commands or tool usage**
   - Exact command with flags
   - What the output means
   - Common variations or aliases

3. **Links & references**
   - Official docs (GitHub README, RFC, etc.)
   - Blog posts or tutorials that clicked for you
   - Stack Overflow or forum threads that solved it

4. **Gotchas / caveats**
   - Edge cases that matter
   - Version-specific quirks
   - Preconditions or assumptions

5. **Trade-offs explicitly stated**
   - If A is simpler but slower, say so
   - If B requires more setup but is more reliable, note it

---

## Confidence Levels

Tag each learning with a confidence flag so you know what to trust:

- **[Confirmed]** — Tested, verified, or from official documentation
- **[Provisional]** — Tested once; makes sense; probably correct but not deeply validated
- **[Hypothesis]** — Theory based on the session; needs real-world testing before relying on it

Example:
```
### Learning: Shell initialization order in zsh
**Confidence:** [Confirmed]
Verified by testing in my own .zshrc and confirmed in Zsh documentation.
```

---

## Decision Log Template

When you made choices in the session (library vs. library, architecture vs. architecture, tool vs. tool), capture them in a **Decisions Made** table so you don't re-explore dead ends:

| Decision | Chosen | Rejected | Reason |
|----------|--------|----------|--------|
| Which spacemouse USB bridge? | jfedor2/magellan-spacemouse (Pico-based) | Custom Rust-to-Swift | Already feature-complete; less code to maintain |
| Async runtime? | Tokio | async-std | Work-stealing suits low-latency; Tokio ecosystem larger |

This prevents circular rework and documents trade-offs for future you.

---

## Obsidian-Friendly Features

- **YAML frontmatter** with `tags`, `date`, `related`, `status` for easy filtering and linking
- **Markdown links** in `related: [[note-name]]` format — Obsidian will auto-create backlinks
- **Status flag** (`raw`, `refined`, `archived`) — helps you track which notes are polished vs. rough captures
- **Hierarchical headers** — Obsidian's outline view makes skimming easy
- **Code blocks with language tags** — renders syntax-highlighted
- **Tables for decisions** — simple, scannable

---

## Workflow Tips

1. **Right after a learning session**, run `/onote` while context is fresh
2. **Use `related:` field** to link related notes — e.g., if you split "Rust async" and "macOS file perms" into two notes, link them
3. **Revisit notes in a month** — promote `status: raw` → `status: refined` if it's still accurate; move to `archived` if superseded
4. **Update confidence** if you later test a `[Provisional]` learning and it holds up (→ `[Confirmed]`)
5. **Add next-step actions** — if the note ends with "I need to try X," put it in the **Next Steps** section so you don't forget

---

## Example: Real Session Note

See `references/example-onote.md` for a full worked example of what an Obsidian-ready note looks like.

---

## Session Analysis Process

When you invoke `/onote`, Claude will:

1. **Extract the problem statement** — What were you trying to solve or understand? What was the context?
2. **Map the conversation flow** — What questions did you ask? What answers did you get? What changed your thinking?
3. **Identify learnings** — Apply the "significant" criteria above; collapse redundancy
4. **Pull concrete artifacts** — Code snippets, commands, links, gotchas from the responses
5. **Capture decisions** — What did you choose and why? What did you reject?
6. **Flag confidence** — Is this confirmed or provisional?
7. **List next steps** — What do you need to do next to validate or act on this?
8. **Create the .md file** — Write it directly to `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/technical/` with a sensible filename

---

## Tips for Best Results

- **Be specific in your `/onote` request** if the session covers multiple topics. E.g., `/onote focus on the Rust patterns, skip the networking troubleshooting` (which could be a separate note)
- **The more focused the session, the better the note** — A 10-exchange conversation on one topic makes a cleaner note than a 60-exchange stream-of-consciousness covering 5 things
- **Review the generated .md before dropping it in Obsidian** — If you want to rename it, adjust tags, or split it into multiple notes, do that first
- **Use the YAML frontmatter as a filter** — Tag notes appropriately so you can later search by `#rust`, `#hardware`, etc., in Obsidian
