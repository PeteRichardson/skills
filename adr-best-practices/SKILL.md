---
name: adr-best-practices
description: Best practices and quality standards for Architecture Decision Records. Background knowledge skill — loaded automatically when writing, reviewing, or evaluating an ADR. Not user-invocable; used by the capture-decision skill to ensure quality output.
disable-model-invocation: true
user-invocable: false
---

# ADR Best Practices

This skill defines quality standards for ADRs in this project. Apply these
when writing or reviewing any decision record.

---

## The core purpose of an ADR

An ADR captures the *reasoning* behind a decision, not just the outcome.
The code already shows *what* was built. An ADR answers:

- What problem were we solving?
- What did we consider?
- Why did we choose this and not that?
- What do we give up by making this choice?

If someone reads an ADR six months later and still can't answer those four
questions, the ADR failed.

---

## What makes a good ADR

### Capture the original question
The best ADRs start with the question that was actually asked. "Is OSLog or
swift-log a better fit?" is more useful context than "We evaluated logging
libraries." The original question reveals what the developer was actually
trying to solve, which may be different from what was ultimately decided.

### Requirements come from the conversation
Requirements in an ADR should be traceable to things the developer
explicitly said during the discussion. Don't infer requirements. Don't
generalize. If the developer said "I need to be able to tail a log file
while the program runs," that goes in verbatim (or close to it). Specificity
is what makes it useful later.

### Include roads not taken
Future developers (including the same developer six months later) often
wonder "why didn't we just use X?" The Options Considered section answers
that preemptively. A dismissed option with one sentence of reasoning is far
more useful than no mention at all.

### Be honest about trade-offs
Every real decision has costs. If the Consequences section lists only
positives, it's incomplete. The most useful part of an ADR is often the
honest "this approach means we'll have to deal with Y someday."

### One decision per ADR
An ADR that covers multiple decisions is hard to reference and hard to
supersede. If a conversation covered two distinct choices (e.g., logging
library AND log format), write two ADRs.

### Write for your future self
The audience is you, six months from now, wondering why the code looks the
way it does. Write with that reader in mind.

---

## What makes a bad ADR

- **Vague decisions**: "We chose swift-log because it's better" — better how?
- **Missing trade-offs**: A decision with no downsides wasn't a real decision
- **Invented requirements**: Requirements that weren't actually discussed
- **Missing alternatives**: Options Considered with only one option listed
- **Outcome without reasoning**: Just documenting what was chosen, not why
- **Too long**: If it takes more than 3 minutes to read, it won't be read

---

## ADR lifecycle

**Accepted** — current decision, actively followed  
**Superseded by NNNN** — replaced by a newer ADR; link to the replacement  
**Deprecated** — no longer relevant (e.g., the feature was removed)  
**Proposed** — under discussion, not yet finalized

When a decision changes, do not edit the old ADR. Write a new one and mark
the old one as "Superseded by NNNN." The history of *why* the decision
changed is as valuable as the original decision.

---

## Index file

Maintain a `docs/decisions/README.md` that lists all ADRs:

```markdown
# Architecture Decision Records

| # | Title | Status | Date |
|---|-------|--------|------|
| [0001](0001-use-swiftlog-for-logging.md) | Use swift-log for logging | Accepted | 2026-03-30 |
| [0002](0002-sqlite-for-local-cache.md) | SQLite for local cache | Accepted | 2026-04-01 |
```

Update this index every time a new ADR is written.

---

## Quality checklist

Before finalizing an ADR, verify:

- [ ] The original question or problem is stated clearly
- [ ] Requirements are specific and traceable to the conversation
- [ ] At least two options are listed (if only one was considered, note why)
- [ ] Each option has honest pros and cons, not just marketing points
- [ ] The Decision section explains *why*, not just *what*
- [ ] Trade-offs and downsides are explicitly acknowledged
- [ ] The title clearly states the decision (not just the topic)
- [ ] The index file (`docs/decisions/README.md`) is updated
