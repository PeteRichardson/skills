# 🎉 `/review` Skill — Ready to Use

You now have a **complete, ready-to-use code review skill** for your `.claude/skills/` directory.

## 📦 What to copy

```
review/
└── SKILL.md
```

**That's all you need.** Copy this folder to `~/.claude/skills/review/` and you're done.

## 🚀 To use it

```
/review src/
```

Claude reads the `SKILL.md` file and executes the skill. You get a comprehensive code review with issues ranked by importance, saved to `docs/reviews/src_YYYY-MM-DD.md`.

## 📚 Supporting documentation

If you want to understand the skill better, read these (in order):

1. **HOW_TO_USE.md** — Quick explanation of what you have
2. **BRAINSTORM_SUMMARY.md** — Philosophy & design decisions
3. **QUICK_REFERENCE.md** — Commands & examples
4. **README.md** — Complete user guide
5. **review_skill_spec.md** — Detailed specification

All other files are optional reference material.

## ✨ Key features

- **Comprehensive analysis**: HIGH (security, memory), IDIOM (language best practices), MEDIUM (inefficiencies), LOW (style)
- **Importance-based ranking**: Not all IDIOM > all MEDIUM; ranked by composite score
- **Session-independent**: Reports saved as markdown, referenceable by issue name
- **Iterative workflow**: "I fixed X, what's next?" continues through issues
- **Learning-focused**: IDIOM scoring teaches why patterns matter
- **Safe defaults**: File threshold, auto-language detection, clear instructions

## 🎯 Commands

```
/review src/                          # Full review
/review src/ --focus idiom            # Language learning
/review src/ --focus high             # Security review
I fixed [issue], what's next?         # Continue
Show me [issue] again                 # Look up specific issue
/review src/ --refresh                # New report when stale
```

## 📋 What's happening under the hood

When you run `/review src/`:

1. Claude reads your `SKILL.md` file
2. Understands the instructions (discover files, analyze code, rank issues, etc.)
3. Asks you for confirmation if scope is large (>30 files)
4. Reads all code files in the scope
5. Calls the Claude API with a detailed system prompt
6. Parses the response (HIGH, IDIOM, MEDIUM, LOW issues with scores)
7. Ranks them (all HIGH + top IDIOM+MEDIUM by importance)
8. Generates markdown report
9. Saves to `docs/reviews/` (not committed)
10. Displays the report

All of this is defined in `SKILL.md`. Claude executes these steps when it sees the `/review` command.

## ✅ You don't need to

- Write any code
- Set up Node.js or TypeScript
- Configure anything
- Run any build steps

Just copy the `review/` folder and use `/review`.

## 🔑 The design is locked in

All of these decisions are made and documented:

- Command name: `/review`
- Report location: `docs/reviews/[SCOPE]_[DATE].md` (ephemeral)
- Ranking: All HIGH + top (10 - num_HIGH) IDIOM+MEDIUM by importance + LOW if room
- IDIOM scoring: Three dimensions (interview + simplification + impact)
- File threshold: >30 requires confirmation
- Language detection: Auto-detect from extensions
- Issue names: Memorable (e.g., "Memory leak in Allocator")

## 📂 File contents

```
review/SKILL.md              ← The actual skill (all Claude needs)
review/review_skill_spec.md  ← Complete specification
```

## 🎓 If you want to customize it

The `SKILL.md` file is a markdown instruction set — you can edit it directly:

- Change file threshold: Edit the line mentioning 30 files
- Adjust scoring rules: Edit the IDIOM scoring section
- Modify commands: Edit the command examples
- Change report location: Edit the `docs/reviews/` mention

Everything is human-readable and editable.

## ✨ Next steps

1. Copy `review/` to `~/.claude/skills/review/`
2. Type `/review src/` in Claude
3. Start reviewing code!

That's it. You're ready to go. 🚀

---

**Total package:**
- ✅ One ready-to-use skill
- ✅ Complete documentation
- ✅ Design specification
- ✅ Reference implementation (optional)

**Estimated time to start using:** 2 minutes (copy folder + try it)

Enjoy! 🎉
