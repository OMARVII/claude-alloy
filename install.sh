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
HOOKS="comment-checker.sh agent-reminder.sh skill-reminder.sh todo-enforcer.sh loop-stop.sh write-guard.sh session-notify.sh branch-guard.sh auto-install.sh typecheck.sh lint.sh pre-compact.sh subagent-start.sh subagent-stop.sh rate-limit-resume.sh session-start.sh session-end.sh"

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
            claude mcp remove "$srv" -s user 2>/dev/null || true
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
    info "Installing to project: ${TARGET_DIR}/.claude/"
    CLAUDE_DIR="${TARGET_DIR}/.claude"
    HOOK_PREFIX="\$CLAUDE_PROJECT_DIR/.claude/alloy-hooks"
    mkdir -p "${CLAUDE_DIR}"/{agents,skills,commands,alloy-hooks}
    MANIFEST_FILE="${CLAUDE_DIR}/.alloy-manifest"
    : > "$MANIFEST_FILE"
    for agent in $AGENTS; do
        dest="${CLAUDE_DIR}/agents/${agent}.md"
        if cp "${SCRIPT_DIR}/agents/${agent}.md" "$dest" 2>/dev/null; then
            echo "$dest" >> "$MANIFEST_FILE"
            success "  agent: ${agent}"
        else
            error "  missing: ${agent}"
        fi
    done
    for skill in $SKILLS; do
        mkdir -p "${CLAUDE_DIR}/skills/${skill}"
        dest="${CLAUDE_DIR}/skills/${skill}/SKILL.md"
        if cp "${SCRIPT_DIR}/skills/${skill}/SKILL.md" "$dest" 2>/dev/null; then
            echo "$dest" >> "$MANIFEST_FILE"
            success "  skill: ${skill}"
        else
            error "  missing: ${skill}"
        fi
    done
    # Clean up skills removed in previous versions (e.g. wiki, learn removed in v1.3.0)
    for stale_skill in wiki learn; do rm -rf "${CLAUDE_DIR}/skills/${stale_skill}" 2>/dev/null; done
    for cmd in $COMMANDS; do
        dest="${CLAUDE_DIR}/commands/${cmd}.md"
        if cp "${SCRIPT_DIR}/commands/${cmd}.md" "$dest" 2>/dev/null; then
            echo "$dest" >> "$MANIFEST_FILE"
            success "  cmd: ${cmd}"
        else
            error "  missing: ${cmd}"
        fi
    done
    for hook in $HOOKS; do
        dest="${CLAUDE_DIR}/alloy-hooks/${hook}"
        if cp "${SCRIPT_DIR}/hooks/${hook}" "$dest" 2>/dev/null && chmod +x "$dest"; then
            echo "$dest" >> "$MANIFEST_FILE"
            success "  hook: ${hook}"
        else
            error "  missing: ${hook}"
        fi
    done
    dest="${TARGET_DIR}/CLAUDE.md"
    if cp "${SCRIPT_DIR}/CLAUDE.md" "$dest" 2>/dev/null; then
        echo "$dest" >> "$MANIFEST_FILE"
    fi
    for agent in $AGENTS; do
        mem_dir="${CLAUDE_DIR}/agent-memory/${agent}"
        mkdir -p "$mem_dir"
        dest="${mem_dir}/MEMORY.md"
        if [ ! -f "$dest" ]; then
            echo "# ${agent} Memory" > "$dest"
        fi
        echo "$dest" >> "$MANIFEST_FILE"
    done
    success "  agent-memory: generated"
    # Copy wiki templates (only if not already present)
    WIKI_DIR="${CLAUDE_DIR}/wiki"
    mkdir -p "$WIKI_DIR"
    for wiki_file in "${SCRIPT_DIR}"/wiki/*.md; do
        [ -f "$wiki_file" ] || continue
        dest="${WIKI_DIR}/$(basename "$wiki_file")"
        if [ ! -f "$dest" ]; then
            cp "$wiki_file" "$dest"
            echo "$dest" >> "$MANIFEST_FILE"
            success "  wiki: $(basename "$wiki_file")"
        fi
    done
    echo "$MANIFEST_FILE" >> "$MANIFEST_FILE"
    info "Wrote manifest ($(wc -l < "$MANIFEST_FILE" | tr -d ' ') files tracked)"
    SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
    BACKUP_FILE="${CLAUDE_DIR}/settings.json.alloy-backup"
    # Back up existing settings on first install (preserve original)
    if [ -f "$SETTINGS_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
        cp "$SETTINGS_FILE" "$BACKUP_FILE"
        info "Backed up existing project settings.json"
    fi
    ALLOY_TMP="${SETTINGS_FILE}.alloy-new"
    cat > "$ALLOY_TMP" << PROJ_EOF
{
  "agent": "steel",
  "env": {"BASH_DEFAULT_TIMEOUT_MS": "420000", "BASH_MAX_TIMEOUT_MS": "420000"},
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
      {"type": "command", "command": "${HOOK_PREFIX}/todo-enforcer.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/loop-stop.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/session-notify.sh", "timeout": 5, "async": true}
    ]}],
    "PreCompact": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/pre-compact.sh", "timeout": 10}]}],
    "SubagentStart": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/subagent-start.sh", "timeout": 5}]}],
    "SubagentStop": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/subagent-stop.sh", "timeout": 5}]}],
    "StopFailure": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/rate-limit-resume.sh", "timeout": 5}]}],
    "SessionStart": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/session-start.sh", "timeout": 5}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/session-end.sh", "timeout": 5, "async": true}]}]
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
          .hooks.SessionEnd = $alloy.hooks.SessionEnd
        ' "$BACKUP_FILE" "$ALLOY_TMP" > "${SETTINGS_FILE}.tmp"; then
            mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
            info "Merged settings with existing project configuration"
        else
            warn "Settings merge failed. Using alloy defaults."
            rm -f "${SETTINGS_FILE}.tmp"
            mv "$ALLOY_TMP" "$SETTINGS_FILE"
        fi
    else
        mv "$ALLOY_TMP" "$SETTINGS_FILE"
        info "Created project settings.json"
    fi
    rm -f "$ALLOY_TMP" 2>/dev/null
    GITIGNORE="${TARGET_DIR}/.gitignore"
    if [ -f "$GITIGNORE" ]; then
        ADDED=""
        if ! grep -qxF '.claude/' "$GITIGNORE" 2>/dev/null; then
            echo '.claude/' >> "$GITIGNORE"
            ADDED="${ADDED} .claude/"
        fi
        if ! grep -qxF 'CLAUDE.md' "$GITIGNORE" 2>/dev/null; then
            echo 'CLAUDE.md' >> "$GITIGNORE"
            ADDED="${ADDED} CLAUDE.md"
        fi
        if [ -n "$ADDED" ]; then
            success "  .gitignore: added${ADDED}"
        else
            warn "  .gitignore: already has .claude/ and CLAUDE.md"
        fi
    fi
    success "Project install complete! Run 'claude' in ${TARGET_DIR} to use."
    exit 0
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        claude-alloy — Agent Harness        ║${NC}"
echo -e "${BLUE}║     Multi-Agent Orchestration for CC       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

info "Creating directories..."
mkdir -p "${CLAUDE_DIR}"/{agents,skills,commands,alloy-hooks}

NEEDS_BACKUP=false
for agent in $AGENTS; do [ -f "${CLAUDE_DIR}/agents/${agent}.md" ] && NEEDS_BACKUP=true; done
if [ "$NEEDS_BACKUP" = true ]; then
    warn "Existing files found. Backing up to ${BACKUP_DIR}..."
    mkdir -p "$BACKUP_DIR"
    cp -r "${CLAUDE_DIR}/agents/" "${BACKUP_DIR}/agents/" 2>/dev/null || true
    cp -r "${CLAUDE_DIR}/skills/" "${BACKUP_DIR}/skills/" 2>/dev/null || true
    cp -r "${CLAUDE_DIR}/commands/" "${BACKUP_DIR}/commands/" 2>/dev/null || true
fi

info "Installing 14 agents..."
for agent in $AGENTS; do
    if [ -f "${SCRIPT_DIR}/agents/${agent}.md" ]; then
        cp "${SCRIPT_DIR}/agents/${agent}.md" "${CLAUDE_DIR}/agents/${agent}.md"
        success "  ✓ ${agent}"
    else
        error "  ✗ ${agent} (file not found)"
    fi
done

info "Installing 8 skills..."
for skill in $SKILLS; do
    if [ -f "${SCRIPT_DIR}/skills/${skill}/SKILL.md" ]; then
        mkdir -p "${CLAUDE_DIR}/skills/${skill}"
        cp "${SCRIPT_DIR}/skills/${skill}/SKILL.md" "${CLAUDE_DIR}/skills/${skill}/SKILL.md"
        success "  ✓ ${skill}"
    else
        error "  ✗ ${skill} (file not found)"
    fi
done

info "Installing 14 commands..."
for cmd in $COMMANDS; do
    if [ -f "${SCRIPT_DIR}/commands/${cmd}.md" ]; then
        cp "${SCRIPT_DIR}/commands/${cmd}.md" "${CLAUDE_DIR}/commands/${cmd}.md"
        success "  ✓ ${cmd}"
    else
        error "  ✗ ${cmd} (file not found)"
    fi
done

info "Installing 17 hook scripts..."
for hook in $HOOKS; do
    if [ -f "${SCRIPT_DIR}/hooks/${hook}" ]; then
        cp "${SCRIPT_DIR}/hooks/${hook}" "${CLAUDE_DIR}/alloy-hooks/${hook}"
        chmod +x "${CLAUDE_DIR}/alloy-hooks/${hook}"
        success "  ✓ ${hook}"
    else
        error "  ✗ ${hook} (file not found)"
    fi
done

info "Generating agent memory files..."
for agent in $AGENTS; do
    mem_dir="${CLAUDE_DIR}/agent-memory/${agent}"
    mkdir -p "$mem_dir"
    if [ ! -f "$mem_dir/MEMORY.md" ]; then
        echo "# ${agent} Memory" > "$mem_dir/MEMORY.md"
    fi
    success "  ✓ ${agent}"
done

info "Copying wiki templates..."
WIKI_DIR="${CLAUDE_DIR}/wiki"
mkdir -p "$WIKI_DIR"
for wiki_file in "${SCRIPT_DIR}"/wiki/*.md; do
    [ -f "$wiki_file" ] || continue
    dest="${WIKI_DIR}/$(basename "$wiki_file")"
    if [ ! -f "$dest" ]; then
        cp "$wiki_file" "$dest"
        success "  ✓ $(basename "$wiki_file")"
    else
        warn "  ✓ $(basename "$wiki_file") (already exists, skipped)"
    fi
done

info "Configuring hooks in settings.json..."
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOK_PREFIX="${HOME}/.claude/alloy-hooks"

if [ -f "$SETTINGS_FILE" ] && grep -q "alloy-hooks" "$SETTINGS_FILE" 2>/dev/null; then
    warn "Hooks already configured in settings.json. Overwriting..."
fi

cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "agent": "steel",
  "env": {"BASH_DEFAULT_TIMEOUT_MS": "420000", "BASH_MAX_TIMEOUT_MS": "420000"},
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
      {"type": "command", "command": "${HOOK_PREFIX}/todo-enforcer.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/loop-stop.sh", "timeout": 5},
      {"type": "command", "command": "${HOOK_PREFIX}/session-notify.sh", "timeout": 5, "async": true}
    ]}],
    "PreCompact": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/pre-compact.sh", "timeout": 10}]}],
    "SubagentStart": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/subagent-start.sh", "timeout": 5}]}],
    "SubagentStop": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/subagent-stop.sh", "timeout": 5}]}],
    "StopFailure": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/rate-limit-resume.sh", "timeout": 5}]}],
    "SessionStart": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/session-start.sh", "timeout": 5}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "${HOOK_PREFIX}/session-end.sh", "timeout": 5, "async": true}]}]
  }
}
SETTINGS_EOF
success "Created settings.json with all hooks"

info "Configuring MCP servers..."
if command -v claude &>/dev/null; then
    # Websearch: always-on keyless; EXA_API_KEY upgrades to higher rate limits
    WEBSEARCH_URL="https://mcp.exa.ai/mcp"
    if [ -n "${EXA_API_KEY:-}" ]; then
        WEBSEARCH_URL="https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY}"
    fi
    # Atomic remove+add per server (handles transport-type changes across versions)
    claude mcp remove context7 -s user 2>/dev/null || true
    claude mcp add --transport http --scope user context7 "https://mcp.context7.com/mcp" 2>/dev/null || warn "Failed to add context7 MCP"
    claude mcp remove grep_app -s user 2>/dev/null || true
    claude mcp add --transport http --scope user grep_app "https://mcp.grep.app" 2>/dev/null || warn "Failed to add grep_app MCP"
    claude mcp remove websearch -s user 2>/dev/null || true
    claude mcp add --transport http --scope user websearch "$WEBSEARCH_URL" 2>/dev/null || warn "Failed to add websearch MCP"
    success "Configured MCP servers (context7, grep_app, websearch)"
    if [ -n "${EXA_API_KEY:-}" ]; then
        success "Websearch upgraded with EXA API key (higher rate limits)"
    fi
    # Opt-in: Playwright MCP for browser automation (uses system Chrome, zero download)
    if [ "${ALLOY_BROWSER:-}" = "1" ]; then
        claude mcp remove playwright -s user 2>/dev/null || true
        if claude mcp add --scope user playwright -- npx @playwright/mcp@0.0.70 --browser=chrome 2>/dev/null; then
            success "Added Playwright MCP server (browser automation)"
        else
            warn "Failed to add Playwright MCP"
        fi
    fi
else
    warn "Claude CLI not found. Add MCP servers manually."
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Installation Complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
success "Installed:"
echo "  14 agents — steel, tungsten, quartz, mercury, graphene, carbon, prism, gauge, spectrum, sentinel, titanium, iridium, cobalt, flint"
echo "  8 skills — git-master, frontend-ui-ux, dev-browser, code-review, review-work, ai-slop-remover, tdd-workflow, verification-loop"
echo "  14 commands — ignite, ig, loop, init-deep, refactor, start-work, handoff, halt, alloy, unalloy, status, wiki-update, notify-setup, learn"
echo "  17 hooks  — comment-checker, agent-reminder, skill-reminder, todo-enforcer, loop-stop, write-guard, session-notify, branch-guard, auto-install, typecheck, lint, pre-compact, subagent-start, subagent-stop, rate-limit-resume, session-start, session-end"
echo "  14 memory — persistent agent memory files (generated per agent)"
echo "  3 MCPs    — context7, grep_app, websearch (+ Playwright if ALLOY_BROWSER=1)"
echo ""
info "Usage modes:"
echo "  bash install.sh              — Global install (all projects)"
echo "  bash install.sh --project .  — Project install (current dir only)"
echo "  bash install.sh --uninstall  — Remove everything"
echo ""
info "Quick Start:"
echo "  1. Start Claude Code: claude"
echo "  2. Type: /ignite"
echo "  3. All 14 agents + 17 hooks active."
echo ""
warn "To uninstall: bash ${SCRIPT_DIR}/install.sh --uninstall"
