---
description: "Create a detailed context summary for continuing work in a new session."
---

# Handoff — Session Continuation Summary

Create a comprehensive context summary that allows a new session to seamlessly continue this work.

## Include in the summary:

### 1. Current State
- What was being worked on
- What's complete and what's remaining
- Current branch and recent commits
- Any uncommitted changes

### 2. Architecture Context
- Key files and their roles
- Important patterns and conventions discovered
- Dependencies and relationships

### 3. Outstanding Items
- Remaining todos with status
- Known issues or blockers
- Decisions that need to be made

### 4. How to Continue
- Exact next steps (numbered, specific)
- Files to read first
- Tests to run
- Commands to execute

### 5. Gotchas
- Things that didn't work (so the next session doesn't repeat mistakes)
- Non-obvious constraints or requirements
- Important context that might be lost

## Output:
Write the summary to `HANDOFF.md` in the project root. Format it so Claude Code can read it at the start of the next session.

## Counterpart:
Use `/start-work` in the next session to resume from this handoff.
