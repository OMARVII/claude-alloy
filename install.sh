#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
BACKUP_DIR="${CLAUDE_DIR}/.alloy-backup-$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[ALLOY]${NC} $1"; }
success() { echo -e "${GREEN}[ALLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[ALLOY]${NC} $1"; }
error() { echo -e "${RED}[ALLOY]${NC} $1"; }

AGENTS="steel tungsten quartz mercury graphene carbon prism gauge spectrum sentinel titanium iridium cobalt flint"
SKILLS="git-master frontend-ui-ux dev-browser code-review review-work ai-slop-remover tdd-workflow verification-loop"
COMMANDS="ignite ig loop init-deep refactor start-work handoff halt alloy unalloy status wiki-update notify-setup learn"
HOOKS="comment-checker.sh agent-reminder.sh skill-reminder.sh todo-enforcer.sh loop-stop.sh write-guard.sh session-notify.sh branch-guard.sh auto-install.sh typecheck.sh lint.sh pre-compact.sh subagent-start.sh subagent-stop.sh rate-limit-resume.sh session-start.sh session-end.sh ignite-stop-gate.sh ignite-detector.sh"

if [ "${1:-}" = "--uninstall" ]; then
    info "Uninstalling claude-alloy..."
    for agent in $AGENTS; do rm -f "${CLAUDE_DIR:?}/agents/${agent}.md"; done
    for skill in $SKILLS; do rm -rf "${CLAUDE_DIR:?}/skills/${skill}"; done
    # Clean up skills removed in previous versions (e.g. wiki, learn removed in v1.3.0)
    for stale_skill in wiki learn; do rm -rf "${CLAUDE_DIR:?}/skills/${stale_skill}"; done
    for cmd in $COMMANDS; do rm -f "${CLAUDE_DIR:?}/commands/${cmd}.md"; done
    rm -rf "${CLAUDE_DIR:?}/alloy-hooks"
    rm -rf "${CLAUDE_DIR:?}/agent-memory"
    rm -f "${CLAUDE_DIR:?}/CLAUDE.md"
    rm -f "${CLAUDE_DIR:?}/alloy-loop-active"
    rm -f "${CLAUDE_DIR:?}/.alloy-manifest"
    rm -rf "${CLAUDE_DIR:?}/.alloy-state"
    # Restore original settings.json from backup (matches deactivate.sh behavior)
    BACKUP_FILE="${CLAUDE_DIR}/settings.json.alloy-backup"
    SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
    if [ -f "$BACKUP_FILE" ]; then
        mv "$BACKUP_FILE" "$SETTINGS_FILE"
        info "Restored original settings.json from backup."
    elif [ -f "$SETTINGS_FILE" ]; then
        rm -f "$SETTINGS_FILE"
        info "Removed Alloy settings.json (no original to restore)."
    fi
    rm -f "${CLAUDE_DIR:?}/.alloy-version"
    # Remove alloy-managed MCP servers
    if command -v claude &>/dev/null; then
        for srv in context7 grep_app websearch playwright; do
            claude mcp remove "$srv" -s user &>/dev/null || true
        done
        info "Removed MCP servers (context7, grep_app, websearch, playwright)"
    fi
    success "claude-alloy uninstalled."
    exit 0
fi

if [ "${1:-}" = "--project" ]; then
    TARGET_DIR="${2:-.}"
    TARGET_DIR=$(cd "$TARGET_DIR" 2>/dev/null && pwd) || { error "Target directory does not exist: ${2:-.}"; exit 1; }
    if [ "$TARGET_DIR" = "/" ]; then
        error "Refusing to install to filesystem root."
        exit 1
    fi
    VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "dev")
    echo ""
    info "claude-alloy v${VERSION} — project install"
    info "Target: ${TARGET_DIR}/.claude/"
    echo ""
    CLAUDE_DIR="${TARGET_DIR}/.claude"
    HOOK_PREFIX="\$CLAUDE_PROJECT_DIR/.claude/alloy-hooks"
    mkdir -p "${CLAUDE_DIR}"/{agents,skills,commands,alloy-hooks}
    MANIFEST_FILE="${CLAUDE_DIR}/.alloy-manifest"
    : > "$MANIFEST_FILE"

    AGENT_OK=0; AGENT_FAIL=0; AGENT_ERRORS=""
    for agent in $AGENTS; do
        dest="${CLAUDE_DIR}/agents/${agent}.md"
        if cp "${SCRIPT_DIR}/agents/${agent}.md" "$dest" 2>/dev/null; then
            echo "$dest" >> "$MANIFEST_FILE"
            AGENT_OK=$((AGENT_OK + 1))
        else
            AGENT_FAIL=$((AGENT_FAIL + 1))
            AGENT_ERRORS="${AGENT_ERRORS}\n    ✗ ${agent}"
        fi
    done
    if [ "$AGENT_FAIL" -eq 0 ]; then
        success "Agents:   ${AGENT_OK} installed"
    else
        warn "Agents:   ${AGENT_OK} installed, ${AGENT_FAIL} failed"
        echo -e "${AGENT_ERRORS}"
    fi

    SKILL_OK=0; SKILL_FAIL=0; SKILL_ERRORS=""
    for skill in $SKILLS; do
        mkdir -p "${CLAUDE_DIR}/skills/${skill}"
        dest="${CLAUDE_DIR}/skills/${skill}/SKILL.md"
        if cp "${SCRIPT_DIR}/skills/${skill}/SKILL.md" "$dest" 2>/dev/null; then
            echo "$dest" >> "$MANIFEST_FILE"
            SKILL_OK=$((SKILL_OK + 1))
        else
            SKILL_FAIL=$((SKILL_FAIL + 1))
            SKILL_ERRORS="${SKILL_ERRORS}\n    ✗ ${skill}"
        fi
    done
    # Clean up skills removed in previous versions (e.g. wiki, learn removed in v1.3.0)
    for stale_skill in wiki learn; do rm -rf "${CLAUDE_DIR}/skills/${stale_skill}" 2>/dev/null; done
    if [ "$SKILL_FAIL" -eq 0 ]; then
        success "Skills:   ${SKILL_OK} installed"
    else
        warn "Skills:   ${SKILL_OK} installed, ${SKILL_FAIL} failed"
        echo -e "${SKILL_ERRORS}"
    fi

    CMD_OK=0; CMD_FAIL=0; CMD_ERRORS=""
    for cmd in $COMMANDS; do
        dest="${CLAUDE_DIR}/commands/${cmd}.md"
        if cp "${SCRIPT_DIR}/commands/${cmd}.md" "$dest" 2>/dev/null; then
            echo "$dest" >> "$MANIFEST_FILE"
            CMD_OK=$((CMD_OK + 1))
        else
            CMD_FAIL=$((CMD_FAIL + 1))
            CMD_ERRORS="${CMD_ERRORS}\n    ✗ ${cmd}"
        fi
    done
    if [ "$CMD_FAIL" -eq 0 ]; then
        success "Commands: ${CMD_OK} installed"
    else
        warn "Commands: ${CMD_OK} installed, ${CMD_FAIL} failed"
        echo -e "${CMD_ERRORS}"
    fi

    HOOK_OK=0; HOOK_FAIL=0; HOOK_ERRORS=""
    for hook in $HOOKS; do
        dest="${CLAUDE_DIR}/alloy-hooks/${hook}"
        if cp "${SCRIPT_DIR}/hooks/${hook}" "$dest" 2>/dev/null && chmod +x "$dest"; then
            echo "$dest" >> "$MANIFEST_FILE"
            HOOK_OK=$((HOOK_OK + 1))
        else
            HOOK_FAIL=$((HOOK_FAIL + 1))
            HOOK_ERRORS="${HOOK_ERRORS}\n    ✗ ${hook}"
        fi
    done
    if [ "$HOOK_FAIL" -eq 0 ]; then
        success "Hooks:    ${HOOK_OK} installed"
    else
        warn "Hooks:    ${HOOK_OK} installed, ${HOOK_FAIL} failed"
        echo -e "${HOOK_ERRORS}"
    fi

    dest="${TARGET_DIR}/CLAUDE.md"
    if cp "${SCRIPT_DIR}/CLAUDE.md" "$dest" 2>/dev/null; then
        echo "$dest" >> "$MANIFEST_FILE"
    fi

    MEM_OK=0
    for agent in $AGENTS; do
        mem_dir="${CLAUDE_DIR}/agent-memory/${agent}"
        mkdir -p "$mem_dir"
        dest="${mem_dir}/MEMORY.md"
        if [ ! -f "$dest" ]; then
            echo "# ${agent} Memory" > "$dest"
        fi
        echo "$dest" >> "$MANIFEST_FILE"
        MEM_OK=$((MEM_OK + 1))
    done
    success "Memory:   ${MEM_OK} initialized"

    # Copy wiki templates (only if not already present)
    WIKI_DIR="${CLAUDE_DIR}/wiki"
    mkdir -p "$WIKI_DIR"
    for wiki_file in "${SCRIPT_DIR}"/wiki/*.md; do
        [ -f "$wiki_file" ] || continue
        dest="${WIKI_DIR}/$(basename "$wiki_file")"
        if [ ! -f "$dest" ]; then
            cp "$wiki_file" "$dest"
            echo "$dest" >> "$MANIFEST_FILE"
        fi
    done

    echo "$MANIFEST_FILE" >> "$MANIFEST_FILE"

    SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
    BACKUP_FILE="${CLAUDE_DIR}/settings.json.alloy-backup"
    # Back up existing settings on first install (preserve original)
    if [ -f "$SETTINGS_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
        cp "$SETTINGS_FILE" "$BACKUP_FILE"
    fi
    ALLOY_TMP="${SETTINGS_FILE}.alloy-new"
    cat > "$ALLOY_TMP" << PROJ_EOF
{
  "agent": "steel",
  "env": {"BASH_DEFAULT_TIMEOUT_MS": "420000", "BASH_MAX_TIMEOUT_MS": "420000", "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS": "1"},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Write", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/write-guard.sh", "timeout": 5}]},
      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/branch-guard.sh", "timeout": 5}]}
    ],
    "PostToolUse": [
      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/comment-checker.sh", "timeout": 10}, {"type": "command", "command": "${HOOK_PREFIX}/typecheck.sh", "timeout": 60}, {"type": "command", "command": "${HOOK_PREFIX}/lint.sh", "timeout": 30}, {"type": "command", "command": "${HOOK_PREFIX}/auto-install.sh", "timeout": 60}]},
      {"matcher": "Grep|Glob|WebFetch|WebSearch|mcp__.*", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/agent-reminder.sh", "timeout": 5}]},
      {"matcher": "Edit|Write|Bash|Read|Grep|Glob", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/skill-reminder.sh", "timeout": 5}]}
    ],
    "Stop": [{"hooks": [
      {"type": "command", "command": "${HOOK_PREFIX}/ignite-stop-gate.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/todo-enforcer.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/loop-stop.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/session-notify.sh", "timeout": 5, "async": true}
    ]}],
    "PreCompact": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/pre-compact.sh", "timeout": 10}]}],
    "SubagentStart": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/subagent-start.sh", "timeout": 5}]}],
    "SubagentStop": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/subagent-stop.sh", "timeout": 5}]}],
    "StopFailure": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/rate-limit-resume.sh", "timeout": 5}]}],
    "SessionStart": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/session-start.sh", "timeout": 5}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/session-end.sh", "timeout": 5, "async": true}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/ignite-detector.sh", "timeout": 5}]}]
  }
}
PROJ_EOF
    # Merge with existing settings if backup exists (preserve user's non-alloy hooks)
    if [ -f "$BACKUP_FILE" ] && command -v jq &>/dev/null; then
        if jq -s '
          .[0] as $orig | .[1] as $alloy |
          ($orig * {agent: $alloy.agent}) |
          .env = (($orig.env // {}) * $alloy.env) |
          .hooks.PreToolUse = ($alloy.hooks.PreToolUse) + ([($orig.hooks.PreToolUse // [])[]] | map(select((.hooks // [{}])[0].command // "" | test("alloy-hooks") | not))) |
          .hooks.PostToolUse = ($alloy.hooks.PostToolUse) + ([($orig.hooks.PostToolUse // [])[]] | map(select((.hooks // [{}])[0].command // "" | test("alloy-hooks") | not))) |
          .hooks.Stop = [{"hooks": (($alloy.hooks.Stop[0].hooks) + ([($orig.hooks.Stop // [{}])[0].hooks // []] | flatten | map(select(.command // "" | test("alloy-hooks") | not))))}] |
          .hooks.PreCompact = $alloy.hooks.PreCompact |
          .hooks.SubagentStart = $alloy.hooks.SubagentStart |
          .hooks.SubagentStop = $alloy.hooks.SubagentStop |
          .hooks.StopFailure = $alloy.hooks.StopFailure |
          .hooks.SessionStart = $alloy.hooks.SessionStart |
          .hooks.SessionEnd = $alloy.hooks.SessionEnd |
          .hooks.UserPromptSubmit = $alloy.hooks.UserPromptSubmit
        ' "$BACKUP_FILE" "$ALLOY_TMP" > "${SETTINGS_FILE}.tmp"; then
            mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        else
            warn "Settings merge failed — using alloy defaults"
            rm -f "${SETTINGS_FILE}.tmp"
            mv "$ALLOY_TMP" "$SETTINGS_FILE"
        fi
    else
        mv "$ALLOY_TMP" "$SETTINGS_FILE"
    fi
    rm -f "$ALLOY_TMP" 2>/dev/null
    success "Settings: configured"
    success "Manifest: $(wc -l < "$MANIFEST_FILE" | tr -d ' ') files tracked"
    GITIGNORE="${TARGET_DIR}/.gitignore"
    if [ -f "$GITIGNORE" ]; then
        if ! grep -qxF '.claude/' "$GITIGNORE" 2>/dev/null; then
            echo '.claude/' >> "$GITIGNORE"
        fi
        if ! grep -qxF 'CLAUDE.md' "$GITIGNORE" 2>/dev/null; then
            echo 'CLAUDE.md' >> "$GITIGNORE"
        fi
    fi
    echo ""
    success "Project install complete! Run 'claude' to use."
    exit 0
fi

VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "dev")

VLINE=$(printf "%-44s" "  claude-alloy v${VERSION}")

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}${VLINE}${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Agent Harness — Install                   ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

mkdir -p "${CLAUDE_DIR}"/{agents,skills,commands,alloy-hooks}

NEEDS_BACKUP=false
for agent in $AGENTS; do [ -f "${CLAUDE_DIR}/agents/${agent}.md" ] && NEEDS_BACKUP=true; done
if [ "$NEEDS_BACKUP" = true ]; then
    info "Existing files found. Backing up to ${BACKUP_DIR}..."
    mkdir -p "$BACKUP_DIR"
    cp -r "${CLAUDE_DIR}/agents/" "${BACKUP_DIR}/agents/" 2>/dev/null || true
    cp -r "${CLAUDE_DIR}/skills/" "${BACKUP_DIR}/skills/" 2>/dev/null || true
    cp -r "${CLAUDE_DIR}/commands/" "${BACKUP_DIR}/commands/" 2>/dev/null || true
fi

AGENT_OK=0; AGENT_FAIL=0; AGENT_ERRORS=""
for agent in $AGENTS; do
    if [ -f "${SCRIPT_DIR}/agents/${agent}.md" ]; then
        cp "${SCRIPT_DIR}/agents/${agent}.md" "${CLAUDE_DIR}/agents/${agent}.md"
        AGENT_OK=$((AGENT_OK + 1))
    else
        AGENT_FAIL=$((AGENT_FAIL + 1))
        AGENT_ERRORS="${AGENT_ERRORS}\n    ✗ ${agent}"
    fi
done
if [ "$AGENT_FAIL" -eq 0 ]; then
    success "Agents:   ${AGENT_OK} installed"
else
    warn "Agents:   ${AGENT_OK} installed, ${AGENT_FAIL} failed"
    echo -e "${AGENT_ERRORS}"
fi

SKILL_OK=0; SKILL_FAIL=0; SKILL_ERRORS=""
for skill in $SKILLS; do
    if [ -f "${SCRIPT_DIR}/skills/${skill}/SKILL.md" ]; then
        mkdir -p "${CLAUDE_DIR}/skills/${skill}"
        cp "${SCRIPT_DIR}/skills/${skill}/SKILL.md" "${CLAUDE_DIR}/skills/${skill}/SKILL.md"
        SKILL_OK=$((SKILL_OK + 1))
    else
        SKILL_FAIL=$((SKILL_FAIL + 1))
        SKILL_ERRORS="${SKILL_ERRORS}\n    ✗ ${skill}"
    fi
done
if [ "$SKILL_FAIL" -eq 0 ]; then
    success "Skills:   ${SKILL_OK} installed"
else
    warn "Skills:   ${SKILL_OK} installed, ${SKILL_FAIL} failed"
    echo -e "${SKILL_ERRORS}"
fi

CMD_OK=0; CMD_FAIL=0; CMD_ERRORS=""
for cmd in $COMMANDS; do
    if [ -f "${SCRIPT_DIR}/commands/${cmd}.md" ]; then
        cp "${SCRIPT_DIR}/commands/${cmd}.md" "${CLAUDE_DIR}/commands/${cmd}.md"
        CMD_OK=$((CMD_OK + 1))
    else
        CMD_FAIL=$((CMD_FAIL + 1))
        CMD_ERRORS="${CMD_ERRORS}\n    ✗ ${cmd}"
    fi
done
if [ "$CMD_FAIL" -eq 0 ]; then
    success "Commands: ${CMD_OK} installed"
else
    warn "Commands: ${CMD_OK} installed, ${CMD_FAIL} failed"
    echo -e "${CMD_ERRORS}"
fi

HOOK_OK=0; HOOK_FAIL=0; HOOK_ERRORS=""
for hook in $HOOKS; do
    if [ -f "${SCRIPT_DIR}/hooks/${hook}" ]; then
        cp "${SCRIPT_DIR}/hooks/${hook}" "${CLAUDE_DIR}/alloy-hooks/${hook}"
        chmod +x "${CLAUDE_DIR}/alloy-hooks/${hook}"
        HOOK_OK=$((HOOK_OK + 1))
    else
        HOOK_FAIL=$((HOOK_FAIL + 1))
        HOOK_ERRORS="${HOOK_ERRORS}\n    ✗ ${hook}"
    fi
done
if [ "$HOOK_FAIL" -eq 0 ]; then
    success "Hooks:    ${HOOK_OK} installed"
else
    warn "Hooks:    ${HOOK_OK} installed, ${HOOK_FAIL} failed"
    echo -e "${HOOK_ERRORS}"
fi

MEM_OK=0
for agent in $AGENTS; do
    mem_dir="${CLAUDE_DIR}/agent-memory/${agent}"
    mkdir -p "$mem_dir"
    if [ ! -f "$mem_dir/MEMORY.md" ]; then
        echo "# ${agent} Memory" > "$mem_dir/MEMORY.md"
    fi
    MEM_OK=$((MEM_OK + 1))
done
success "Memory:   ${MEM_OK} initialized"

WIKI_DIR="${CLAUDE_DIR}/wiki"
mkdir -p "$WIKI_DIR"
WIKI_OK=0
for wiki_file in "${SCRIPT_DIR}"/wiki/*.md; do
    [ -f "$wiki_file" ] || continue
    dest="${WIKI_DIR}/$(basename "$wiki_file")"
    if [ ! -f "$dest" ]; then
        cp "$wiki_file" "$dest"
    fi
    WIKI_OK=$((WIKI_OK + 1))
done
success "Wiki:     ${WIKI_OK} templates"

SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOK_PREFIX="${HOME}/.claude/alloy-hooks"

cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "agent": "steel",
  "env": {"BASH_DEFAULT_TIMEOUT_MS": "420000", "BASH_MAX_TIMEOUT_MS": "420000", "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS": "1"},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Write", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/write-guard.sh", "timeout": 5}]},
      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/branch-guard.sh", "timeout": 5}]}
    ],
    "PostToolUse": [
      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/comment-checker.sh", "timeout": 10}, {"type": "command", "command": "${HOOK_PREFIX}/typecheck.sh", "timeout": 60}, {"type": "command", "command": "${HOOK_PREFIX}/lint.sh", "timeout": 30}, {"type": "command", "command": "${HOOK_PREFIX}/auto-install.sh", "timeout": 60}]},
      {"matcher": "Grep|Glob|WebFetch|WebSearch|mcp__.*", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/agent-reminder.sh", "timeout": 5}]},
      {"matcher": "Edit|Write|Bash|Read|Grep|Glob", "hooks": [{"type": "command", "command": "${HOOK_PREFIX}/skill-reminder.sh", "timeout": 5}]}
    ],
    "Stop": [{"hooks": [
      {"type": "command", "command": "${HOOK_PREFIX}/ignite-stop-gate.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/todo-enforcer.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/loop-stop.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/session-notify.sh", "timeout": 5, "async": true}
    ]}],
    "PreCompact": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/pre-compact.sh", "timeout": 10}]}],
    "SubagentStart": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/subagent-start.sh", "timeout": 5}]}],
    "SubagentStop": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/subagent-stop.sh", "timeout": 5}]}],
    "StopFailure": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/rate-limit-resume.sh", "timeout": 5}]}],
    "SessionStart": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/session-start.sh", "timeout": 5}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/session-end.sh", "timeout": 5, "async": true}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/ignite-detector.sh", "timeout": 5}]}]
  }
}
SETTINGS_EOF
success "Settings: configured (hooks + env)"

MCP_OK=0; MCP_NAMES=""
if command -v claude &>/dev/null; then
    ensure_mcp() {
        local name="$1" url="$2"
        if claude mcp list -s user 2>/dev/null | grep -q "\"${url}\""; then
            return 0
        fi
        claude mcp remove "$name" -s user &>/dev/null || true
        claude mcp add "$name" --transport http --scope user "$url" &>/dev/null || { warn "Failed to add $name MCP"; return 1; }
    }

    WEBSEARCH_URL="https://mcp.exa.ai/mcp"
    if [ -n "${EXA_API_KEY:-}" ]; then
        WEBSEARCH_URL="https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY}"
    fi
    ensure_mcp context7 "https://mcp.context7.com/mcp" && MCP_OK=$((MCP_OK + 1)) && MCP_NAMES="context7"
    ensure_mcp grep_app "https://mcp.grep.app" && MCP_OK=$((MCP_OK + 1)) && MCP_NAMES="${MCP_NAMES}, grep_app"
    ensure_mcp websearch "$WEBSEARCH_URL" && MCP_OK=$((MCP_OK + 1)) && MCP_NAMES="${MCP_NAMES}, websearch"
    if [ "${ALLOY_BROWSER:-}" = "1" ]; then
        if ! claude mcp list -s user 2>/dev/null | grep -q "playwright"; then
            claude mcp remove playwright -s user &>/dev/null || true
            if claude mcp add --scope user playwright -- npx @playwright/mcp@0.0.70 --browser=chrome &>/dev/null; then
                MCP_OK=$((MCP_OK + 1)); MCP_NAMES="${MCP_NAMES}, playwright"
            else
                warn "Failed to add Playwright MCP"
            fi
        else
            MCP_OK=$((MCP_OK + 1)); MCP_NAMES="${MCP_NAMES}, playwright"
        fi
    fi
    success "MCP:      ${MCP_OK} servers ready (${MCP_NAMES})"
else
    warn "MCP:      Claude CLI not found — add servers manually"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Installation Complete!            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
info "Start: claude"
info "Max effort: /ignite"
info "Uninstall: bash ${SCRIPT_DIR}/install.sh --uninstall"
