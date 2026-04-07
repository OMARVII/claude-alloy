---
description: "Remove claude-alloy harness from the current project. Deletes .claude/ directory, CLAUDE.md, and cleans .gitignore entries."
---

# /unalloy — Remove claude-alloy From This Project

Uninstall the claude-alloy harness from the current working directory.

## Steps

1. **Confirm** with the user before proceeding (this is destructive and irreversible).

2. **Remove** the harness:

```bash
rm -rf .claude/agents .claude/skills .claude/commands .claude/alloy-hooks .claude/agent-memory .claude/settings.json
rm -f CLAUDE.md
```

3. **Clean .gitignore** — remove the `.claude/` and `CLAUDE.md` entries if present:

```bash
if [ -f .gitignore ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' '/^\.claude\/$/d' .gitignore
    sed -i '' '/^CLAUDE\.md$/d' .gitignore
  else
    sed -i '/^\.claude\/$/d' .gitignore
    sed -i '/^CLAUDE\.md$/d' .gitignore
  fi
fi
```

4. **Report** what was removed.

## Important

- This removes ALL Alloy agents, skills, commands, hooks, and agent memory from this project.
- If the user has custom files in `.claude/` that are NOT from Alloy, warn them before deleting.
- To reinstall: run `alloy` (global) or `bash install.sh --project .` (per-project)
