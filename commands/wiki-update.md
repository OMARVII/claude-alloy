---
description: "Update the project wiki with learnings from the current session. Summarizes architecture, conventions, and decisions."
---

# Wiki Update

Update `.claude/wiki/` files based on what you learned in this session.

## Steps

1. Read all files in `.claude/wiki/`
2. Review recent changes: `git diff --stat HEAD~5..HEAD 2>/dev/null` and `git log --oneline -10 2>/dev/null`
3. Scan key project files: package.json, tsconfig.json, main entry points
4. Update each wiki file:

### architecture.md
- Key modules and their responsibilities
- Data flow patterns
- External service integrations
- Tech stack summary

### conventions.md
- Naming conventions (variables, functions, files)
- File organization patterns
- Error handling patterns
- Import/export conventions

### decisions.md
- Add any new technical decisions from this session
- Format: | Date | Decision | Rationale |

## Rules
- Keep each wiki file under 100 lines
- Write for a developer joining the project tomorrow
- Facts only, no opinions
- Update existing content, don't just append
- If nothing meaningful to add, say so and don't edit
