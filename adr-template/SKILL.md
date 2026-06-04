---
name: adr-template
description: Template and structure for Architecture Decision Records (ADRs). Background knowledge skill — loaded automatically when writing or formatting an ADR document. Not user-invocable; used by the capture-decision skill and whenever Claude formats a decision record.
disable-model-invocation: true
user-invocable: false
---

# ADR Template

When writing an Architecture Decision Record, use this structure exactly. Every ADR is a standalone markdown file. Do not deviate from this structure — consistency across ADRs is what makes them useful over time.

## File naming convention

```
docs/decisions/NNNN-short-slug-of-decision.md
```

- `NNNN` is a zero-padded 4-digit sequence number (0001, 0002, ...)
- The slug is lowercase, hyphen-separated, describing the decision in 3–6 words
- Examples:
  - `0001-use-swiftlog-for-logging.md`
  - `0002-sqlite-for-local-cache.md`
  - `0003-async-await-over-combine.md`

To determine the next sequence number, list existing files in `docs/decisions/` and increment the highest number. If the directory doesn't exist, create it and start at `0001`.

## ADR file template

```markdown
# NNNN: [Title — the decision stated plainly]

**Status:** Accepted
**Date:** YYYY-MM-DD
**Deciders:** [who was involved — can be just "Peter" for solo projects]

---

## Context and Problem

[2–4 sentences describing the situation that forced a decision.
What were you trying to accomplish? What constraint or requirement
made this non-trivial? What question were you trying to answer?]

## Requirements

[Bullet list of the concrete requirements or constraints that
shaped the decision. These come from the conversation — what the
developer said they needed the solution to do or support.]

- Requirement 1
- Requirement 2
- ...

## Options Considered

### Option A: [Name]

[One paragraph. What it is, why it was considered.]

**Pros:**
- ...

**Cons:**
- ...

### Option B: [Name]

[Same structure.]

**Pros:**
- ...

**Cons:**
- ...

[Add more options as needed. Only include options that were actually
discussed — don't invent alternatives that weren't part of the
conversation.]

## Decision

**Chosen: [Option name]**

[2–4 sentences explaining why this option was selected over the
others. Be specific about which requirements tipped the decision.
This is the most important section — future readers need to
understand the reasoning, not just the outcome.]

## Consequences

**Positive:**
- ...

**Negative / Trade-offs:**
- ...

**Neutral / Watch:**
- [Things to keep an eye on; decisions this might force later]

---

*Generated from conversation on YYYY-MM-DD*
```

## Guidelines for filling in the template

- **Context and Problem**: Write this from the developer's perspective at the time of the decision, not in hindsight. Use the original question that started the discussion if possible.
- **Requirements**: Extract these from what the developer said they needed — "I want to be able to watch logs from Console while it runs" becomes a requirement bullet. Don't invent requirements not discussed.
- **Options Considered**: Only include options that actually came up in the conversation. If only two options were discussed, only list two.
- **Decision**: Never be vague here. "We chose X because it best met requirements Y and Z, and trade-off W was acceptable because..." is good. "We chose X because it seemed better" is not.
- **Consequences**: Negative consequences and trade-offs are as important as positive ones. A decision with no downsides probably wasn't a real decision.
