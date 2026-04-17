---
description: "Scan project health and Claude Code readiness. Reports maturity level and suggests improvements."
---

# Assess — Project Health Scanner

Scan the current project and report its Claude Code readiness level.

## Pre-scan (run these first)

```!
echo "=== CLAUDE.md ==="
if [ -f "CLAUDE.md" ]; then echo "EXISTS ($(wc -l < CLAUDE.md) lines)"; else echo "MISSING"; fi
echo ""

echo "=== MCP Servers ==="
claude mcp list 2>/dev/null || echo "Unable to check MCPs"
echo ""

echo "=== Skills ==="
ls .claude/skills/ 2>/dev/null || echo "No skills directory"
echo ""

echo "=== Commands ==="
ls .claude/commands/ 2>/dev/null || echo "No commands directory"
echo ""

echo "=== Hooks ==="
if [ -f ".claude/settings.json" ]; then
    cat .claude/settings.json | python3 -c "import sys,json; d=json.load(sys.stdin); hooks=d.get('hooks',{}); print(f'{sum(len(v) for v in hooks.values())} hooks across {len(hooks)} events')" 2>/dev/null || echo "settings.json exists but no hooks"
else
    echo "No project settings.json"
fi
echo ""

echo "=== Tests ==="
for pattern in "*.test.*" "*.spec.*" "*_test.*" "test_*"; do
    count=$(find . -name "$pattern" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then echo "$pattern: $count files"; fi
done
echo ""

echo "=== Lint/Type Config ==="
for cfg in .eslintrc* eslint.config* biome.json tsconfig.json pyproject.toml .flake8 .pylintrc Cargo.toml go.mod; do
    for f in $cfg; do
        [ -f "$f" ] && echo "  ✅ $f"
    done
done
echo ""

echo "=== Git Status ==="
git status --short 2>/dev/null | wc -l | tr -d ' '
echo "uncommitted files"
echo "Branch: $(git branch --show-current 2>/dev/null || echo 'N/A')"
echo ""

echo "=== Agent Memory ==="
if [ -d ".claude/agent-memory" ]; then
    find .claude/agent-memory -name "*.md" -size +50c 2>/dev/null | wc -l | tr -d ' '
    echo "active memory files"
else
    echo "No agent memory"
fi
```

## Scoring Guide

Based on the pre-scan results, score the project on a 0-10 maturity scale:

| Level | Name | Requires |
|-------|------|----------|
| 0 | Terminal Tourist | Nothing configured |
| 1 | Context Aware | CLAUDE.md exists with >10 meaningful lines |
| 2 | Connected | At least 1 MCP server configured |
| 3 | Skilled | 3+ custom skills or commands |
| 4 | Knowledge System | Agent memory with real content, OR wiki populated |
| 5 | Multi-Phase | Approval gates, sub-agents, or multi-step workflows |
| 6 | Programmatic | Headless mode usage, pipeline scripts, or CI integration |
| 7 | Browser Enabled | Browser automation configured (Playwright MCP) |
| 8 | Parallel Agents | 5+ specialized agents with distinct roles |
| 9 | Automated | Scheduled/cron agents running autonomously |
| 10 | Swarm Architect | Agent orchestrator managing other agents |

## Output Format

Present results as:

```
╔══════════════════════════════════════╗
║  PROJECT HEALTH ASSESSMENT           ║
╠══════════════════════════════════════╣
║  Maturity Level: [N]/10 — [Name]    ║
╠══════════════════════════════════════╣
║  ✅ CLAUDE.md        [status]        ║
║  ✅ MCP Servers      [count]         ║
║  ✅ Skills           [count]         ║
║  ✅ Commands         [count]         ║
║  ✅ Hooks            [count]         ║
║  ✅ Tests            [status]        ║
║  ✅ Lint/Types       [status]        ║
║  ✅ Git Hygiene      [status]        ║
║  ✅ Agent Memory     [status]        ║
╠══════════════════════════════════════╣
║  NEXT STEPS                          ║
║  1. [Most impactful improvement]     ║
║  2. [Second improvement]             ║
║  3. [Third improvement]              ║
╚══════════════════════════════════════╝
```

Use ✅ for present/healthy, ⚠️ for partial, ❌ for missing. Be specific in next steps — name the exact file to create or command to run.
