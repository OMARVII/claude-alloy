#!/usr/bin/env bash
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"

VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=true ;;
    esac
done

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    if [ "$VERBOSE" = true ]; then
        echo -e "  ${GREEN}[PASS]${NC} $1"
    fi
}

warn_check() {
    WARN_COUNT=$((WARN_COUNT + 1))
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

fail_check() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "  ${RED}[FAIL]${NC} $1"
}

# Canonical lists
AGENTS="steel tungsten quartz mercury graphene carbon prism gauge spectrum sentinel titanium iridium cobalt flint"
SKILLS="git-master frontend-ui-ux dev-browser code-review review-work ai-slop-remover tdd-workflow verification-loop"
COMMANDS="ignite ig loop init-deep refactor start-work handoff halt alloy unalloy status wiki-update notify-setup learn"
HOOKS="comment-checker.sh agent-reminder.sh skill-reminder.sh todo-enforcer.sh loop-stop.sh write-guard.sh session-notify.sh branch-guard.sh auto-install.sh typecheck.sh lint.sh pre-compact.sh subagent-start.sh subagent-stop.sh rate-limit-resume.sh session-start.sh session-end.sh ignite-stop-gate.sh ignite-detector.sh"

echo ""
echo -e "${BLUE}alloy doctor${NC} — checking installation health"
echo ""

# 1. check_jq
if command -v jq &>/dev/null; then
    pass "jq found: $(command -v jq)"
else
    fail_check "jq not found — required for hooks (brew install jq / apt install jq)"
fi

# 2. check_git
if command -v git &>/dev/null; then
    pass "git found: $(command -v git)"
else
    fail_check "git not found — required for self-update"
fi

# 3. check_claude_cli
if command -v claude &>/dev/null; then
    pass "claude CLI found: $(command -v claude)"
else
    warn_check "claude CLI not found — MCP checks skipped"
fi

# 4. check_agents
AGENT_MISSING=0
for agent in $AGENTS; do
    if [ ! -f "${CLAUDE_DIR}/agents/${agent}.md" ] && [ ! -L "${CLAUDE_DIR}/agents/${agent}.md" ]; then
        fail_check "Missing agent: ${agent}.md"
        AGENT_MISSING=$((AGENT_MISSING + 1))
    fi
done
if [ "$AGENT_MISSING" -eq 0 ]; then
    pass "All 14 agents present"
fi

# 5. check_skills
SKILL_MISSING=0
for skill in $SKILLS; do
    if [ ! -f "${CLAUDE_DIR}/skills/${skill}/SKILL.md" ] && [ ! -L "${CLAUDE_DIR}/skills/${skill}/SKILL.md" ]; then
        fail_check "Missing skill: ${skill}/SKILL.md"
        SKILL_MISSING=$((SKILL_MISSING + 1))
    fi
done
if [ "$SKILL_MISSING" -eq 0 ]; then
    pass "All 8 skills present"
fi

# 6. check_commands
CMD_MISSING=0
for cmd in $COMMANDS; do
    if [ ! -f "${CLAUDE_DIR}/commands/${cmd}.md" ] && [ ! -L "${CLAUDE_DIR}/commands/${cmd}.md" ]; then
        fail_check "Missing command: ${cmd}.md"
        CMD_MISSING=$((CMD_MISSING + 1))
    fi
done
if [ "$CMD_MISSING" -eq 0 ]; then
    pass "All 14 commands present"
fi

# 7. check_hooks
HOOK_MISSING=0
for hook in $HOOKS; do
    if [ ! -f "${CLAUDE_DIR}/alloy-hooks/${hook}" ] && [ ! -L "${CLAUDE_DIR}/alloy-hooks/${hook}" ]; then
        fail_check "Missing hook: ${hook}"
        HOOK_MISSING=$((HOOK_MISSING + 1))
    fi
done
if [ "$HOOK_MISSING" -eq 0 ]; then
    pass "All 19 hooks present"
fi

# 8. check_symlinks — find broken symlinks
BROKEN_LINKS=0
for dir in agents skills commands alloy-hooks; do
    target_dir="${CLAUDE_DIR}/${dir}"
    if [ -d "$target_dir" ]; then
        while IFS= read -r link; do
            fail_check "Broken symlink: ${link}"
            BROKEN_LINKS=$((BROKEN_LINKS + 1))
        done < <(find "$target_dir" -type l ! -exec test -e {} \; -print 2>/dev/null)
    fi
done
if [ "$BROKEN_LINKS" -eq 0 ]; then
    pass "No broken symlinks"
fi

# 9. check_settings
if [ -f "${CLAUDE_DIR}/settings.json" ]; then
    if jq . "${CLAUDE_DIR}/settings.json" &>/dev/null; then
        pass "settings.json exists and is valid JSON"
    else
        fail_check "settings.json exists but is not valid JSON"
    fi
else
    fail_check "settings.json not found"
fi

# 10. check_manifest
if [ -f "${CLAUDE_DIR}/.alloy-manifest" ]; then
    if [ -s "${CLAUDE_DIR}/.alloy-manifest" ]; then
        pass ".alloy-manifest exists ($(wc -l < "${CLAUDE_DIR}/.alloy-manifest" | tr -d ' ') files tracked)"
    else
        fail_check ".alloy-manifest exists but is empty"
    fi
else
    fail_check ".alloy-manifest not found — run alloy to generate"
fi

# 11. check_version
if [ -f "${CLAUDE_DIR}/.alloy-meta" ]; then
    INSTALLED_VER=$(jq -r '.version // "unknown"' "${CLAUDE_DIR}/.alloy-meta" 2>/dev/null || echo "unknown")
    REPO_VER=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")
    if [ "$INSTALLED_VER" = "$REPO_VER" ]; then
        pass "Version match: ${REPO_VER}"
    else
        warn_check "Version mismatch — installed: ${INSTALLED_VER}, repo: ${REPO_VER} (run alloy to update)"
    fi
else
    warn_check ".alloy-meta not found — version tracking unavailable (run alloy to generate)"
fi

# 12. check_mcp
if command -v claude &>/dev/null; then
    MCP_LIST=$(claude mcp list -s user 2>/dev/null || echo "")
    MCP_MISSING=0
    for server in context7 grep_app websearch; do
        if ! echo "$MCP_LIST" | grep -q "$server"; then
            warn_check "MCP server not configured: ${server}"
            MCP_MISSING=$((MCP_MISSING + 1))
        fi
    done
    if [ "$MCP_MISSING" -eq 0 ]; then
        pass "MCP servers configured (context7, grep_app, websearch)"
    fi
fi

# Summary
echo ""
TOTAL=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
echo -e "alloy doctor: ${GREEN}${PASS_COUNT} passed${NC}, ${YELLOW}${WARN_COUNT} warnings${NC}, ${RED}${FAIL_COUNT} failures${NC} (${TOTAL} checks)"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
