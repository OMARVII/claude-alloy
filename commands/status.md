---
description: "Report current session status: loop state, branch, uncommitted changes, todos, and recent memory."
---

# Status Report

Gather and display the following information:

## 1. Loop State

Check if a `/loop` is currently active:
- Look for an `alloy-loop-active` file in the project root or `.claude/` directory
- Report: **Loop active** or **No loop active**

## 2. Git State

Run `git status` and `git branch --show-current` to report:
- Current branch name
- Number of uncommitted changes (staged and unstaged)
- Number of untracked files

## 3. Pending Todos

Check if there are any active todo items in the current session:
- List incomplete todos with their status
- If none, report: **No pending todos**

## 4. Agent Memory Highlights

Scan `.claude/agent-memory/` for recent memory entries:
- List the 5 most recently modified memory files across all agents
- For each, show: agent name, memory title, one-line description
- If no memories exist, report: **No agent memories recorded**

## Output Format

Present as a compact status block:

```
STATUS
  Loop:     [active/inactive]
  Branch:   [name] ([N] uncommitted, [M] untracked)
  Todos:    [count pending] / [count total]
  Memory:   [count] recent entries across [N] agents
```

Follow the status block with details for any non-empty section.
