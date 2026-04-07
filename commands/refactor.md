---
description: "Intelligent refactoring with diagnostics verification. Ensures no regressions."
argument-hint: "[what to refactor]"
---

# Refactor — Safe Code Transformation

Refactor the following: $ARGUMENTS

## Process:

1. **Analyze**: Understand what exists and why. Read the code. Check git history for context.
2. **Plan**: List every file and function that will change. Identify dependencies.
3. **Baseline**: Run diagnostics and tests BEFORE any changes. Record the baseline.
4. **Execute**: Make changes incrementally. Verify after EACH change.
5. **Verify**: Run diagnostics and tests AFTER all changes. Compare to baseline.

## Safety Rules:
- Use LSP rename for symbol renames (catches all references)
- Use AST-grep for structural pattern changes
- Run diagnostics after EVERY file edit
- Run tests after completing each logical unit
- If tests break: STOP, understand why, fix or revert
- NEVER change behavior while refactoring (unless explicitly asked)
- Commit each logical unit separately (use /git-master)

## Verification Checklist:
- [ ] All diagnostics pass (no new errors)
- [ ] All tests pass (no regressions)
- [ ] No behavioral changes (unless intended)
- [ ] Code is cleaner/simpler than before
- [ ] No new type suppressions introduced
