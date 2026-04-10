---
description: "Extract reusable patterns from the current session into skill files. User-reviewed, not automatic."
---

# Learn — Pattern Extraction

Review this session and extract any reusable patterns, debugging approaches, or workflow improvements into a new skill file.

## Steps

1. Review what happened this session:
   - `git log --oneline -10 2>/dev/null`
   - `git diff --stat HEAD~5..HEAD 2>/dev/null`
   - Check recent tool usage patterns
2. Identify reusable patterns:
   - Debugging approaches that worked
   - Code generation patterns that produced good results
   - Workflow sequences worth repeating
   - Non-obvious solutions to common problems
3. If patterns found, generate a skill file:
   - Write to `.claude/skills/learned/[pattern-name]/SKILL.md`
   - Use standard skill format (frontmatter + instructions)
   - Name should be descriptive: `debug-react-hydration`, `optimize-sql-queries`, etc.
4. Report what was extracted and where the file was saved
5. Remind user to review the generated skill before relying on it

## Rules
- Only extract genuinely reusable patterns, not one-off fixes
- If nothing worth extracting, say so honestly
- Generated skills go in `.claude/skills/learned/` (separate from core skills)
- The user decides whether to keep the generated skill
- Never modify existing core skills in `.claude/skills/`

## Output
- Summary of patterns found (or "No reusable patterns identified")
- File path of generated skill (if any)
- One-line description of what the skill does
