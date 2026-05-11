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

4. **Optional — clear Claude Code's per-project state.** The harness teardown above removes the alloy files from the project; Claude Code itself also caches per-project state (transcripts, task lists, debug logs, file-edit history, prompt history, the project's entry in `~/.claude.json`) outside the project directory. Offer the user a final purge step:

```bash
claude project purge "$PWD" --dry-run    # preview what would be deleted
claude project purge "$PWD"              # delete (will prompt for confirmation; add -y to skip)
```

This is optional and reversible only in the trivial sense (sessions can be restarted from scratch). Recommended for a fully clean slate when leaving a repo permanently; skip it when the user just wants to swap harnesses on the same repo and intends to keep their Claude Code session history. See [Clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data) for the full purge scope.

5. **Report** what was removed.

## Important

- This removes ALL Alloy agents, skills, commands, hooks, and agent memory from this project.
- If the user has custom files in `.claude/` that are NOT from Alloy, warn them before deleting.
- To reinstall: run `alloy` (global) or `bash install.sh --project .` (per-project)
