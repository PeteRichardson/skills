---
name: update-docs
description: Check whether documentation needs updating given recent changes, and update it if so. Use when the user types /update-docs, says "update the docs", "is the design doc current", or has just made structural changes and wants to keep documentation in sync. Invokes /gen-design-doc if an update is warranted.
---

# Update Docs

Assess whether the design doc and ADR index are current given recent
changes. Update what needs updating; confirm what doesn't. Don't update
docs that don't need it.

---

## Step 1: Understand what changed

```bash
git diff --staged --name-only
git diff --name-only
git diff --staged
git diff
```

Use staged files if staged; otherwise all changed files. Read enough
of the diff to understand the *nature* of the change — structural vs.
behavioral vs. cosmetic.

---

## Step 2: Check design doc currency

```bash
head -10 docs/design.md 2>/dev/null       # Last updated date
git log --oneline -1 -- docs/design.md    # Last commit touching it
git log --oneline -5 -- docs/design.md    # Recent history
```

Assess whether the design doc is likely stale given the change:

| Change type | Update warranted? |
|-------------|------------------|
| New module, crate, or package | Yes |
| New public API surface | Yes |
| Changed data model or core types | Yes |
| New external dependency with architectural significance | Yes |
| Internal refactor, no interface change | Usually not |
| Bug fix | No |
| Test additions only | No |
| Config, build, or tooling only | No |
| Documentation only | No |

When in doubt, briefly describe the change and ask:
> "This change [adds/modifies X]. Does the design doc need updating?"

---

## Step 3: Update design doc if needed

If an update is warranted, run `/gen-design-doc`. That skill handles
the full update cycle — reading the current doc, identifying stale
sections, and rewriting them.

If no update is needed, say so briefly:
> ✅ Design doc looks current — this change doesn't affect the architecture.

---

## Step 4: Check ADR index

```bash
ls docs/decisions/ 2>/dev/null
cat docs/decisions/README.md 2>/dev/null
git log --oneline -3 -- docs/decisions/
```

Note the most recent ADR and its date. Don't prompt for a new ADR here —
that's `/capture-decision`'s job. Just report status:

> ADRs: last recorded [date] — [slug]. N decisions total.

---

## Step 5: Report

Close with a compact status:

```
Design doc:  ✅ current  (no structural changes)
             ✅ updated  (ran /gen-design-doc)
             ⚠️  may need update — [reason]
ADR index:   ✅ N decisions, last updated [date]
```

---

## What not to do

- Don't update the design doc for non-structural changes — churn is worse
  than staleness for minor changes
- Don't write ADRs — that's `/capture-decision`
- Don't modify source code
- Don't update docs that are already current