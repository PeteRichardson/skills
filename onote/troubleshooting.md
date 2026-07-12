# Onote Quick Reference & Troubleshooting

## Quick Checklist Before Invoking `/onote`

- [ ] The session has a clear focus (if it covers 3+ unrelated topics, split it)
- [ ] I've asked 5+ substantive questions (not just a quick lookup)
- [ ] The conversation has context and I'm ready to capture learnings now (fresh memory)
- [ ] I want to preserve this for future reference (worth a permanent note)

---

## Common Scenarios & How to Handle Them

### Scenario 1: The session is a quick lookup (e.g., "What's the syntax for X?")

**Don't use `/onote`** — Onote is for learning sessions with depth. A 2-minute syntax check doesn't warrant a note.

**Do use `/onote` if:** You spent 30+ minutes exploring variations, edge cases, or trade-offs around that syntax.

---

### Scenario 2: Multiple unrelated topics came up (Rust + networking + hardware)

**Use split notes:**

```
/onote create three separate notes:
  1. Rust async patterns
  2. UniFi VLAN troubleshooting
  3. USB serial power injection
Then link them via related: field.```

Or ask me to generate a primary note on the most important topic and sidebar notes on the others.

---

### Scenario 3: The session went in circles (asked the same question 3 different ways)

**I'll collapse the redundant bits.** The note will only include the final, clearest answer — not all three variations.

**Gotcha:** If you changed your mind mid-session (e.g., started with approach A, switched to B), I'll capture that as a **Decision Made** with reasoning.

---

### Scenario 4: Some things are confirmed but others are just theories

**Use confidence levels:**
- `[Confirmed]` — Tested, or from official docs
- `[Provisional]` — Seems right; tested once
- `[Hypothesis]` — Theory; needs real-world validation

Don't hide hypotheses; just flag them honestly. Future-you will know not to rely blindly on them.

---

### Scenario 5: I want to emphasize or exclude certain parts

**Use `/onote` modifiers:**


```
/onote focus on the Rust patterns, skip the networking stuff
/onote emphasize the gotchas, minimize the background context
/onote only create 2 learnings on the core insight```

I'll respect these scoping hints.

---

### Scenario 6: The note is too long / too short

**Too long (7+ learnings)?**
- I should split it or collapse closely-related learnings into one with subheadings
- Ask me to regenerate with a strict limit (e.g., `/onote max 4 learnings`)

**Too short (1 learning)?**
- Was the session really that shallow? Onote works best with 3–5 learnings
- Or maybe you're being too strict on significance criteria; ask me to relax them

---

### Scenario 7: I want to add or remove a learning after the note is generated

**Easy:** Download the note, edit it in your text editor, and re-upload to Obsidian. Or ask me to regenerate with changes.

**I won't re-generate continuously** — use the exported .md as the source of truth and edit it directly.

---

## Onote Output: File Naming Convention

Generated files follow this pattern:


```
{Topic-in-kebab-case}-{YYYY-MM-DD}.md```

Examples:
- `rust-async-patterns-2025-06-05.md`
- `spacemouse-hardware-usb-serial-2025-06-05.md`
- `macos-dotfile-sourcing-order-2025-06-05.md`

If you re-run `/onote` on the same topic on the same day, I'll append a suffix:

```
rust-async-patterns-2025-06-05-v2.md```

---

## What Happens Next: Workflow

1. **I generate the .md file** → saved directly to `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/technical/`
2. **Review & refine** — Edit tags, move to folders, refactor if needed
3. **Link related notes** — Use Obsidian's linking UI to cross-reference
4. **Revisit later** — Bump `status: raw` → `status: refined` if it holds up

Notes are written straight into your vault — no manual download or copy step needed. You still have full control to edit, move, or delete them afterward.

---

## Obsidian Integration: Making the Most of Frontmatter

After you import a note, you can leverage the YAML metadata:

### Filter by tag
In Obsidian, search with `tag:#rust` to find all Rust-related notes.

### Search by date
Use `created:2025-06` to find all notes created in June 2025.

### Filter by status
Search `status:raw` to find notes you haven't fully refined yet.

### Navigate via related links
The `related:` field creates backlinks; Obsidian shows them in the graph view.

### Bulk operations
Use Obsidian's `dataview` plugin (if installed) to query:

```
table tags, date, status
where contains(tags, "rust") AND confidence = "high"```

---

## Troubleshooting: "The Generated Note Doesn't Feel Right"

### Problem: Too conceptual, not enough code

**Cause:** The session focused on understanding over implementation.

**Fix:** Ask me to regenerate with emphasis on examples/artifacts:

```
/onote add more code examples and command snippets```

### Problem: Too focused on one topic; missed the bigger picture

**Cause:** I applied the "significance" filter too strictly.

**Fix:** Ask me to expand or relax the criteria:

```
/onote include all the tangential learnings too; this is a brainstorm note```

### Problem: Decisions table is empty or unclear

**Cause:** The session didn't have explicit trade-offs.

**Fix:** Provide context; I'll infer decisions from your questions:

```
/onote I was choosing between libraries X and Y; capture that trade-off```

### Problem: Questions Remaining section is missing or vague

**Cause:** The session was conclusive; there aren't real open questions.

**Fix:** That's fine. I'll note `## Questions Remaining: None — session was conclusive` or list true unknowns only.

### Problem: The note feels incomplete; I know I learned more

**Cause:** Some learnings didn't make the "significant" cut, or I'm being conservative on confidence.

**Fix:** Ask me to lower the bar or expand scope:

```
/onote include all my learnings, even small ones; mark them with lower confidence```

---

## When to Revisit & Update a Note

- **New information arrives** (e.g., you test a [Hypothesis] and it becomes [Confirmed]) → Edit the note, bump confidence
- **Months pass** → Revisit the note, check if it's still accurate, update status to `refined` or `archived`
- **You solve the question** that was in "Questions Remaining" → Remove it or move to a separate follow-up note
- **A better approach emerges** → Create a new note or link a "Part 2" note to show the evolution

**Don't worry about keeping notes "perfect"** — They're learning artifacts, not polished docs. Update as your understanding evolves.

---

## Future Enhancements (Planned, Not Yet Implemented)

- 🔮 Automatic linking between related notes
- 🔮 Bulk note operations (merge, split, re-tag) via Obsidian plugin
- 🔮 Confidence evolution tracking (see how certainty changed over time)
- 🔮 Note template generation (create your own custom onote format)

As the skill matures, these conveniences will arrive.

---

## Quick Command Reference


```bash
# Onote writes directly to the vault, so no manual copy step is needed. Obsidian
# (via iCloud Drive sync) picks up the new file automatically.

# To delete an onote:
rm "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/technical/{Topic}-{YYYY-MM-DD}.md"
# Obsidian will remove it from the vault automatically
```

---

## Questions About Onote Itself?

- **How are learnings organized?** → By significance and topic relevance; related learnings may be grouped
- **Why limit to 3–5 learnings?** → Keeps notes scannable; longer notes should be split
- **Can I use tags not listed in the template?** → Yes! Edit the YAML frontmatter freely; Obsidian will recognize them
- **Can I use onote for non-technical sessions?** → Absolutely! Cooking tips, woodworking techniques, anything with learnings
- **Should every session become a note?** → No; only sessions where you've learned something worth remembering. Scratch conversations don't need notes.

