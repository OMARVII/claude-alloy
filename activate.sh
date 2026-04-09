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

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   claude-alloy — Global Activation         ║${NC}"
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

for f in "${SCRIPT_DIR}"/agents/*.md; do
    dest="${CLAUDE_DIR}/agents/$(basename "$f")"
    cp "$f" "$dest"
    echo "$dest" >> "$MANIFEST_FILE"
done
info "Installed 11 agents"

for skill_dir in "${SCRIPT_DIR}"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    mkdir -p "${CLAUDE_DIR}/skills/${skill_name}"
    for f in "${skill_dir}"*; do
        dest="${CLAUDE_DIR}/skills/${skill_name}/$(basename "$f")"
        cp "$f" "$dest"
        echo "$dest" >> "$MANIFEST_FILE"
    done
done
info "Installed 8 skills"

for f in "${SCRIPT_DIR}"/commands/*.md; do
    dest="${CLAUDE_DIR}/commands/$(basename "$f")"
    cp "$f" "$dest"
    echo "$dest" >> "$MANIFEST_FILE"
done
info "Installed 10 commands"

for f in "${SCRIPT_DIR}"/hooks/*.sh; do
    dest="${CLAUDE_DIR}/alloy-hooks/$(basename "$f")"
    cp "$f" "$dest"
    chmod +x "$dest"
    echo "$dest" >> "$MANIFEST_FILE"
done
info "Installed 11 hooks"

for f in "${SCRIPT_DIR}"/agents/*.md; do
    agent_name=$(basename "$f" .md)
    mem_dir="${CLAUDE_DIR}/agent-memory/${agent_name}"
    mkdir -p "$mem_dir"
    dest="${mem_dir}/MEMORY.md"
    if [ ! -f "$dest" ]; then
        echo "# ${agent_name} Memory" > "$dest"
    fi
    echo "$dest" >> "$MANIFEST_FILE"
done
info "Generated 11 agent memory files"

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
    "BASH_MAX_TIMEOUT_MS": "420000"
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
          {"type":"command","command":($hd + "/todo-enforcer.sh"),"timeout":5,"statusMessage":"Checking todos..."},
          {"type":"command","command":($hd + "/loop-stop.sh"),"timeout":5,"statusMessage":"Checking loop status..."},
          {"type":"command","command":($hd + "/session-notify.sh"),"timeout":5,"async":true,"statusMessage":"Session complete!"}
        ]
      }
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
      .hooks.Stop = [{"hooks": (($alloy.hooks.Stop[0].hooks) + ([($orig.hooks.Stop // [{}])[0].hooks // []] | flatten | map(select(.command // "" | test("alloy-hooks") | not))))}]
    ' "$BACKUP_FILE" <(echo "$ALLOY_SETTINGS") > "$SETTINGS_FILE"
    info "Merged settings with existing configuration"
else
    echo "$ALLOY_SETTINGS" > "$SETTINGS_FILE"
    info "Created settings.json"
fi

if command -v claude &>/dev/null; then
    if claude mcp add context7 --transport http -s user -- "https://mcp.context7.com/mcp" 2>/dev/null; then
        info "Added context7 MCP server"
    fi
    if claude mcp add grep_app --transport http -s user -- "https://mcp.grep.app/search" 2>/dev/null; then
        info "Added grep_app MCP server"
    fi
    # Auto-configure Exa websearch only if the user already has an API key
    if [ -n "${EXA_API_KEY:-}" ]; then
        # shellcheck disable=SC2016
        if claude mcp add websearch --transport http -s user -- "https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY}" 2>/dev/null; then
            info "Added websearch MCP server (Exa)"
        fi
    fi
fi

echo ""
success "claude-alloy is now active globally!"
echo ""
info "Start ${BOLD}claude${NC} in any directory — no /alloy-init needed."
info "Run ${BOLD}unalloy${NC} to deactivate and restore original settings."
info "Type ${BOLD}/ignite${NC} inside Claude for maximum effort mode."
echo ""
