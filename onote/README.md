# Onote Skill Structure

This directory contains the `onote` skill for summarizing Claude sessions into Obsidian-ready markdown notes.

## Files

### Core Skill Definition
- **`SKILL.md`** — Main skill definition with usage instructions, output template, and guidelines. This is the canonical reference.

### Reference Materials (loaded as needed)
- **`references/example-onote.md`** — Real example of a generated note (6DOF hardware session). Shows what the output looks like and how to structure learnings with artifacts.
- **`references/generation-logic.md`** — Step-by-step guide for Claude on how to analyze a session and generate a note. Not for you to read; this is Claude's working notes.
- **`references/troubleshooting.md`** — FAQ, common scenarios, gotchas, and how to customize onote behavior.

## Quick Start

1. **Invoke the skill:**
   ```
   /onote
   ```

2. **Optionally, scope it:**
   ```
   /onote focus on the Rust patterns
   /onote create two separate notes for hardware and software
   ```

3. **I'll generate a `.md` file** saved to `/mnt/user-data/outputs/`

4. **Download and import into Obsidian** — Edit as needed

## Key Concepts

### Significance Criteria
A learning matters if it's:
- New concept / pattern learned
- Changed your approach / methodology
- Solved a blocker
- Reusable tool / command
- Mental model shift

### Output Structure
Every generated note includes:
- **YAML frontmatter** (tags, date, related, status, confidence)
- **Context & Problem Statement** (why were you learning this?)
- **Key Learnings** (3–5 significant findings with artifacts)
- **Decisions Made** (trade-offs, what you chose and rejected)
- **Questions Remaining** (open questions, follow-ups)
- **Next Steps / Actions** (concrete to-dos)

### Confidence Levels
- **[Confirmed]** — Tested or from official docs
- **[Provisional]** — Tested once; seems right; mark for follow-up
- **[Hypothesis]** — Theory; needs real-world validation

## Customization

Use `/onote` modifiers to tune the output:

```
/onote focus on {topic}                    # Narrow scope
/onote separate {topic1} and {topic2}      # Create linked notes instead of one
/onote max {N} learnings                   # Strict learning count
/onote emphasize {aspect}                  # Prioritize certain details
/onote minimal; just the core              # Condensed version
```

## Workflow Integration

Onote fits into a learning loop:

1. **Have a learning session** with Claude (ask questions, explore trade-offs, solve problems)
2. **Generate a note** with `/onote` while context is fresh
3. **Download & import** into Obsidian
4. **Review & refine** (edit tags, reorganize if needed)
5. **Link related notes** using Obsidian's linking
6. **Revisit later** — bump `status: raw` → `refined` if still accurate

## For More Information

- **SKILL.md** — Complete documentation, output template, best practices
- **example-onote.md** — Concrete example showing quality output
- **troubleshooting.md** — FAQ, edge cases, customization recipes

## Future Enhancements

- Direct Obsidian vault integration (auto-insert without manual download)
- Automatic inter-note linking
- Bulk note operations (merge, split, retag)
- Confidence evolution tracking over time

---

**Status:** Beta (ready for use; expect iteration as you provide feedback)
**Last Updated:** 2025-06-05
