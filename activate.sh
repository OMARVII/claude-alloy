#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[ALLOY]${NC} $1"; }
success() { echo -e "${GREEN}[ALLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[ALLOY]${NC} $1"; }
error() { echo -e "${RED}[ALLOY]${NC} $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
BACKUP_FILE="${CLAUDE_DIR}/settings.json.alloy-backup"
HOOK_DIR="${CLAUDE_DIR}/alloy-hooks"

if ! command -v jq &>/dev/null; then
    error "jq is required. Install: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

# Self-update check (isolated — failures never block activation)
bash "$SCRIPT_DIR/self-update.sh" "$@" 2>/dev/null || true

VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "dev")

VLINE=$(printf "%-44s" "  claude-alloy v${VERSION}")

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}${VLINE}${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Agent Harness — Activate                  ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

mkdir -p "${CLAUDE_DIR}/agents" "${CLAUDE_DIR}/skills" "${CLAUDE_DIR}/commands" "${CLAUDE_DIR}/alloy-hooks" "${CLAUDE_DIR}/agent-memory"

if [ ! -f "$BACKUP_FILE" ]; then
    if [ -f "$SETTINGS_FILE" ]; then
        cp "$SETTINGS_FILE" "$BACKUP_FILE"
        info "Backed up existing settings.json"
    fi
else
    info "Updating existing Alloy installation (original backup preserved)"
fi

MANIFEST_FILE="${CLAUDE_DIR}/.alloy-manifest"
: > "$MANIFEST_FILE"

AGENT_COUNT=0
for f in "${SCRIPT_DIR}"/agents/*.md; do
    dest="${CLAUDE_DIR}/agents/$(basename "$f")"
    cp "$f" "$dest"
    echo "$dest" >> "$MANIFEST_FILE"
    AGENT_COUNT=$((AGENT_COUNT + 1))
done
info "Installed ${AGENT_COUNT} agents"

SKILL_COUNT=0
for skill_dir in "${SCRIPT_DIR}"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    mkdir -p "${CLAUDE_DIR}/skills/${skill_name}"
    for f in "${skill_dir}"*; do
        dest="${CLAUDE_DIR}/skills/${skill_name}/$(basename "$f")"
        cp "$f" "$dest"
        echo "$dest" >> "$MANIFEST_FILE"
    done
    SKILL_COUNT=$((SKILL_COUNT + 1))
done
info "Installed ${SKILL_COUNT} skills"
# Clean up skills removed in previous versions (e.g. wiki, learn removed in v1.3.0)
for stale_skill in wiki learn; do rm -rf "${CLAUDE_DIR}/skills/${stale_skill}" 2>/dev/null; done

CMD_COUNT=0
for f in "${SCRIPT_DIR}"/commands/*.md; do
    dest="${CLAUDE_DIR}/commands/$(basename "$f")"
    cp "$f" "$dest"
    echo "$dest" >> "$MANIFEST_FILE"
    CMD_COUNT=$((CMD_COUNT + 1))
done
info "Installed ${CMD_COUNT} commands"

HOOK_COUNT=0
for f in "${SCRIPT_DIR}"/hooks/*.sh; do
    dest="${CLAUDE_DIR}/alloy-hooks/$(basename "$f")"
    cp "$f" "$dest"
    chmod +x "$dest"
    echo "$dest" >> "$MANIFEST_FILE"
    HOOK_COUNT=$((HOOK_COUNT + 1))
done
info "Installed ${HOOK_COUNT} hooks"

MEM_COUNT=0
for f in "${SCRIPT_DIR}"/agents/*.md; do
    agent_name=$(basename "$f" .md)
    mem_dir="${CLAUDE_DIR}/agent-memory/${agent_name}"
    mkdir -p "$mem_dir"
    dest="${mem_dir}/MEMORY.md"
    if [ ! -f "$dest" ]; then
        echo "# ${agent_name} Memory" > "$dest"
    fi
    echo "$dest" >> "$MANIFEST_FILE"
    MEM_COUNT=$((MEM_COUNT + 1))
done
info "Generated ${MEM_COUNT} agent memory files"

dest="${CLAUDE_DIR}/CLAUDE.md"
cp "${SCRIPT_DIR}/CLAUDE.md" "$dest"
echo "$dest" >> "$MANIFEST_FILE"
info "Installed CLAUDE.md"

echo "$MANIFEST_FILE" >> "$MANIFEST_FILE"
info "Wrote manifest ($(wc -l < "$MANIFEST_FILE" | tr -d ' ') files tracked)"

ALLOY_SETTINGS=$(jq -n --arg hd "$HOOK_DIR" '{
  "agent": "steel",
  "env": {
    "BASH_DEFAULT_TIMEOUT_MS": "420000",
    "BASH_MAX_TIMEOUT_MS": "420000",
    "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS": "1"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [{"type":"command","command":($hd + "/write-guard.sh"),"timeout":5,"statusMessage":"Checking file safety..."}]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [{"type":"command","command":($hd + "/branch-guard.sh"),"timeout":5,"statusMessage":"Checking branch protection..."}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {"type":"command","command":($hd + "/comment-checker.sh"),"timeout":10,"statusMessage":"Checking code quality..."},
          {"type":"command","command":($hd + "/typecheck.sh"),"timeout":60,"statusMessage":"Running type check..."},
          {"type":"command","command":($hd + "/lint.sh"),"timeout":30,"statusMessage":"Running linter..."},
          {"type":"command","command":($hd + "/auto-install.sh"),"timeout":60,"statusMessage":"Checking dependencies..."}
        ]
      },
      {
        "matcher": "Grep|Glob|WebFetch|WebSearch|mcp__.*",
        "hooks": [{"type":"command","command":($hd + "/agent-reminder.sh"),"timeout":5,"statusMessage":"Checking delegation patterns..."}]
      },
      {
        "matcher": "Edit|Write|Bash|Read|Grep|Glob",
        "hooks": [{"type":"command","command":($hd + "/skill-reminder.sh"),"timeout":5,"statusMessage":"Checking skill usage..."}]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type":"command","command":($hd + "/ignite-stop-gate.sh"),"timeout":5,"statusMessage":"Checking IGNITE compliance..."},
          {"type":"command","command":($hd + "/todo-enforcer.sh"),"timeout":5,"statusMessage":"Checking todos..."},
          {"type":"command","command":($hd + "/loop-stop.sh"),"timeout":5,"statusMessage":"Checking loop status..."},
          {"type":"command","command":($hd + "/session-notify.sh"),"timeout":5,"async":true,"statusMessage":"Session complete!"}
        ]
      }
    ],
    "PreCompact": [
      {"hooks": [{"type":"command","command":($hd + "/pre-compact.sh"),"timeout":10,"statusMessage":"Saving context before compaction..."}]}
    ],
    "SubagentStart": [
      {"hooks": [{"type":"command","command":($hd + "/subagent-start.sh"),"timeout":5,"statusMessage":"Tracking agent activity..."}]}
    ],
    "SubagentStop": [
      {"hooks": [{"type":"command","command":($hd + "/subagent-stop.sh"),"timeout":5,"statusMessage":"Verifying agent deliverables..."}]}
    ],
    "StopFailure": [
      {"hooks": [{"type":"command","command":($hd + "/rate-limit-resume.sh"),"timeout":5,"statusMessage":"Checking rate limit status..."}]}
    ],
    "SessionStart": [
      {"hooks": [{"type":"command","command":($hd + "/session-start.sh"),"timeout":5,"statusMessage":"Loading project wiki..."}]}
    ],
    "SessionEnd": [
      {"hooks": [{"type":"command","command":($hd + "/session-end.sh"),"timeout":5,"async":true,"statusMessage":"Checking session productivity..."}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type":"command","command":($hd + "/ignite-detector.sh"),"timeout":5,"statusMessage":"Checking ignite mode..."}]}
    ]
  }
}')

if [ -f "$BACKUP_FILE" ]; then
    jq -s '
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
    ' "$BACKUP_FILE" <(echo "$ALLOY_SETTINGS") > "${SETTINGS_FILE}.tmp" || {
        error "Settings merge failed. Restoring backup."
        rm -f "${SETTINGS_FILE}.tmp"
        cp "$BACKUP_FILE" "$SETTINGS_FILE"
        exit 1
    }
    mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    info "Merged settings with existing configuration"
else
    echo "$ALLOY_SETTINGS" > "$SETTINGS_FILE"
    info "Created settings.json"
fi

info "Configuring MCP servers..."
if command -v claude &>/dev/null; then
    # Ensures an MCP server is configured with the expected URL.
    # Only touches the config when the server is missing or the URL changed.
    ensure_mcp() {
        local name="$1" url="$2"
        # claude mcp list outputs JSON; check if this server already has the right URL
        if claude mcp list -s user 2>/dev/null | grep -q "\"${url}\""; then
            return 0
        fi
        claude mcp remove "$name" -s user &>/dev/null || true
        claude mcp add "$name" --transport http -s user -- "$url" &>/dev/null || { warn "Failed to add $name MCP"; return 1; }
    }

    # Websearch: always-on keyless; EXA_API_KEY upgrades to higher rate limits
    WEBSEARCH_URL="https://mcp.exa.ai/mcp"
    if [ -n "${EXA_API_KEY:-}" ]; then
        WEBSEARCH_URL="https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY}"
    fi
    ensure_mcp context7 "https://mcp.context7.com/mcp"
    ensure_mcp grep_app "https://mcp.grep.app"
    ensure_mcp websearch "$WEBSEARCH_URL"
    success "MCP servers ready (context7, grep_app, websearch)"
    if [ -n "${EXA_API_KEY:-}" ]; then
        success "Websearch upgraded with EXA API key (higher rate limits)"
    fi
    # Opt-in: Playwright MCP for browser automation (uses system Chrome, zero download)
    if [ "${ALLOY_BROWSER:-}" = "1" ]; then
        if ! claude mcp list -s user 2>/dev/null | grep -q "playwright"; then
            claude mcp remove playwright -s user &>/dev/null || true
            if claude mcp add playwright -s user -- npx @playwright/mcp@0.0.70 --browser=chrome &>/dev/null; then
                success "Added Playwright MCP server (browser automation)"
            else
                warn "Failed to add Playwright MCP"
            fi
        fi
    fi
else
    warn "Claude CLI not found. Add MCP servers manually."
fi

# Track installed version
if [ -d "$SCRIPT_DIR/.git" ]; then
    git -C "$SCRIPT_DIR" describe --tags --always 2>/dev/null > "${CLAUDE_DIR}/.alloy-version" || true
fi

echo ""
success "claude-alloy is now active globally!"
echo ""
info "Start ${BOLD}claude${NC} in any directory — no /alloy-init needed."
info "Run ${BOLD}unalloy${NC} to deactivate and restore original settings."
info "Type ${BOLD}/ignite${NC} inside Claude for maximum effort mode."
echo ""
