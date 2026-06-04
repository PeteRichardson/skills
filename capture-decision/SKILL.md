---
name: capture-decision
description: Capture an architectural or technical decision from the current conversation as a structured ADR (Architecture Decision Record). Use when the user types /capture-decision, says "let's record this decision", "capture this", "document this choice", or indicates they've reached a conclusion after evaluating options (e.g. "ok, let's go with X"). Also invoke when the user asks to record why something was chosen, document a trade-off discussion, or preserve the reasoning behind a technical choice.
---

# Capture Decision

When invoked, synthesize the current conversation into a well-structured
Architecture Decision Record and write it to `docs/decisions/`.

This skill captures the *reasoning* behind a decision — the original
question, the requirements that shaped it, the options considered, and why
one was chosen. The goal is that someone reading the ADR six months later
can fully reconstruct the thinking, even without the conversation.

---

## Step 1: Identify what decision was made

Read back through the conversation and identify:

1. **The original question or problem** — what prompted the discussion?
   Use the developer's own words where possible. ("Is OSLog or swift-log
   better for this use case?" is better than "Logging library selection.")

2. **The decision** — what was ultimately chosen? Look for signals like
   "let's go with X", "I think X is the right call", "ok, X it is",
   or the user invoking this skill after a discussion concludes.

3. **Whether this is one decision or two** — if the conversation covered
   multiple distinct choices, ask the user before proceeding:
   "I see two separate decisions here: [A] and [B]. Should I write one
   ADR covering both, or two separate ADRs?"

If the conversation is ambiguous about what was decided, ask:
"Before I write this up — just to confirm, the decision is to use [X]
for [purpose], correct?"

---

## Step 2: Extract the components

Pull these from the conversation:

**Requirements** — things the developer explicitly said they needed:
- Direct quotes or close paraphrases from the conversation
- Non-negotiable constraints mentioned
- "Nice to have" items that influenced the decision
- Do NOT invent requirements that weren't discussed

**Options considered** — libraries, approaches, or architectures that
came up in the conversation:
- What each option is and why it was in the running
- Pros and cons as they emerged in the discussion
- Only include options that were actually discussed

**Decision rationale** — why the chosen option won:
- Which requirements it best satisfied
- Which trade-offs were considered acceptable and why
- Any tipping-point reasons that settled the discussion

**Consequences** — what the decision means going forward:
- What becomes easier
- What becomes harder or is given up
- Anything to watch out for later

---

## Step 3: Determine the file path

List existing ADRs to get the next sequence number:

```bash
ls docs/decisions/ 2>/dev/null | grep -E '^[0-9]{4}-' | sort | tail -1
```

If `docs/decisions/` doesn't exist, create it and start at `0001`.

Construct the filename:
- Format: `NNNN-short-slug-of-decision.md`
- Slug: lowercase, hyphen-separated, 3–6 words describing the decision
- Example: `0003-use-swiftlog-for-structured-logging.md`

---

## Step 4: Write the ADR

Use the `adr-template` skill's structure. Fill every section.

Key quality standards from `adr-best-practices`:
- The Context section should open with the original question if possible
- Requirements must be traceable to things actually said in the conversation
- Options Considered must include at least the options that came up — never
  invent options, but never omit options that were discussed
- The Decision rationale must explain *why*, not just *what*
- Consequences must include trade-offs and downsides, not just benefits

Write the file to `docs/decisions/NNNN-slug.md`.

---

## Step 5: Update the index

Read `docs/decisions/README.md`. If it doesn't exist, create it with this
header:

```markdown
# Architecture Decision Records

This directory captures significant technical and architectural decisions
made during development, along with the context and reasoning behind them.

| # | Title | Status | Date |
|---|-------|--------|------|
```

Add a row for the new ADR:
```
| [NNNN](NNNN-slug.md) | [Title] | Accepted | YYYY-MM-DD |
```

Keep the table sorted by number.

---

## Step 6: Present a summary

Show the developer:

1. The path of the file written
2. A brief (3–5 line) summary of what was captured:
   - The decision
   - The key reason it was chosen
   - The main trade-off acknowledged

3. Ask: **"Does this accurately capture the decision? Anything to
   add or correct before we move on?"**

If the developer wants changes, edit the file in place — don't rewrite
from scratch.

---

## Step 7: Offer to stage the files

After the developer confirms the ADR looks right, offer:

"Want me to stage the new ADR and index for your next commit? Or
I can run `/commit` now if you'd like to checkpoint this decision."

Do not stage or commit without explicit confirmation.

---

## What not to do

- Don't invent requirements, options, or reasoning not present in the
  conversation
- Don't write a vague Decision section ("chose X because it seemed better")
- Don't skip the Consequences section or list only positives
- Don't write multiple decisions into one ADR without asking first
- Don't commit without the user confirming the content
- Don't use jargon the user didn't use in the conversation
