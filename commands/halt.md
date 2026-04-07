---
description: "Stop loop and all autonomous continuation mechanisms."
---

# Stop Loop

All autonomous continuation mechanisms are now STOPPED.

First, remove the loop state file:
```bash
rm -f "${CLAUDE_PROJECT_DIR:-.}/.claude/alloy-loop-active"
```

- Loop: CANCELLED
- Todo continuation: SUSPENDED
- Autonomous iteration: HALTED

You may now respond normally to user messages without automatic continuation.

Report the current state:
1. What was being worked on
2. What's complete
3. What's remaining
4. Any uncommitted changes

Then wait for the user's next instruction.
