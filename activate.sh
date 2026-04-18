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

# --- Platform detection ---

detect_install_mode() {
    # WSL detection
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
        echo "copy"
        return
    fi
    if [ -f /proc/version ] && grep -qi "microsoft" /proc/version 2>/dev/null; then
        echo "copy"
        return
    fi
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            echo "copy"
            return
            ;;
    esac

    # Probe test: verify symlinks actually work (NTFS drvfs creates text files)
    local probe_dir="${CLAUDE_DIR}"
    mkdir -p "$probe_dir"
    local probe_src="${probe_dir}/.alloy-probe-src"
    local probe_lnk="${probe_dir}/.alloy-probe-lnk"
    echo "probe" > "$probe_src" 2>/dev/null || { echo "copy"; return; }
    ln -sf "$probe_src" "$probe_lnk" 2>/dev/null || { rm -f "$probe_src"; echo "copy"; return; }
    if [ -L "$probe_lnk" ]; then
        rm -f "$probe_src" "$probe_lnk"
        echo "symlink"
    else
        rm -f "$probe_src" "$probe_lnk"
        echo "copy"
    fi
}

install_file() {
    local src="$1" dest="$2" manifest_tmp="$3"
    if [ "$INSTALL_MODE" = "symlink" ]; then
        if [ -f "$dest" ] && [ ! -L "$dest" ]; then
            # Regular file exists — check if it differs from source
            if ! diff -q "$src" "$dest" &>/dev/null; then
                cp "$dest" "${dest}.user-backup"
                warn "Backed up customized file: $(basename "$dest") → $(basename "$dest").user-backup"
            fi
            ln -s "$src" "${dest}.alloy-tmp" && mv "${dest}.alloy-tmp" "$dest"
        elif [ -L "$dest" ]; then
            local current_target
            current_target=$(readlink "$dest" 2>/dev/null || echo "")
            if [ "$current_target" = "$src" ]; then
                : # Already correct symlink — skip
            else
                ln -s "$src" "${dest}.alloy-tmp" && mv "${dest}.alloy-tmp" "$dest"
            fi
        else
            ln -s "$src" "${dest}.alloy-tmp" && mv "${dest}.alloy-tmp" "$dest"
        fi
    else
        cp "$src" "$dest"
    fi
    echo "$dest" >> "$manifest_tmp"
}

# --- Flag handling (short-circuit before self-update) ---

for arg in "$@"; do
    case "$arg" in
        --version)
            VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "dev")
            INSTALLED_VER=""
            if [ -f "${CLAUDE_DIR}/.alloy-version" ]; then
                INSTALLED_VER=$(cat "${CLAUDE_DIR}/.alloy-version" 2>/dev/null || echo "")
            fi
            if [ -n "$INSTALLED_VER" ] && [ "$INSTALLED_VER" != "$VERSION" ] && [ "$INSTALLED_VER" != "v${VERSION}" ]; then
                echo "claude-alloy repo: ${VERSION} | installed: ${INSTALLED_VER}"
            else
                echo "claude-alloy ${VERSION}"
            fi
            exit 0
            ;;
        --check)
            exec bash "${SCRIPT_DIR}/doctor.sh" "$@"
            ;;
    esac
done

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

INSTALL_MODE=$(detect_install_mode)

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
MANIFEST_TMP="${MANIFEST_FILE}.tmp"
: > "$MANIFEST_TMP"

AGENT_COUNT=0
for f in "${SCRIPT_DIR}"/agents/*.md; do
    dest="${CLAUDE_DIR}/agents/$(basename "$f")"
    install_file "$f" "$dest" "$MANIFEST_TMP"
    AGENT_COUNT=$((AGENT_COUNT + 1))
done
info "Installed ${AGENT_COUNT} agents (${INSTALL_MODE} mode)"

SKILL_COUNT=0
for skill_dir in "${SCRIPT_DIR}"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    mkdir -p "${CLAUDE_DIR}/skills/${skill_name}"
    for f in "${skill_dir}"*; do
        dest="${CLAUDE_DIR}/skills/${skill_name}/$(basename "$f")"
        install_file "$f" "$dest" "$MANIFEST_TMP"
    done
    SKILL_COUNT=$((SKILL_COUNT + 1))
done
info "Installed ${SKILL_COUNT} skills"
# Clean up skills removed in previous versions (e.g. wiki, learn removed in v1.3.0)
for stale_skill in wiki learn; do rm -rf "${CLAUDE_DIR}/skills/${stale_skill}" 2>/dev/null; done

CMD_COUNT=0
for f in "${SCRIPT_DIR}"/commands/*.md; do
    dest="${CLAUDE_DIR}/commands/$(basename "$f")"
    install_file "$f" "$dest" "$MANIFEST_TMP"
    CMD_COUNT=$((CMD_COUNT + 1))
done
info "Installed ${CMD_COUNT} commands"

HOOK_COUNT=0
chmod +x "${SCRIPT_DIR}"/hooks/*.sh 2>/dev/null || true
for f in "${SCRIPT_DIR}"/hooks/*.sh; do
    dest="${CLAUDE_DIR}/alloy-hooks/$(basename "$f")"
    install_file "$f" "$dest" "$MANIFEST_TMP"
    # Ensure dest is executable (for copy mode; symlinks inherit source perms)
    if [ ! -L "$dest" ]; then
        chmod +x "$dest"
    fi
    HOOK_COUNT=$((HOOK_COUNT + 1))
done
# Ship VERSION alongside hooks so statusline.sh can self-locate it (v1.6.2+)
install_file "${SCRIPT_DIR}/VERSION" "${CLAUDE_DIR}/alloy-hooks/VERSION" "$MANIFEST_TMP"
info "Installed ${HOOK_COUNT} hooks"

# Agent memory: always copy, never symlink
MEM_COUNT=0
for f in "${SCRIPT_DIR}"/agents/*.md; do
    agent_name=$(basename "$f" .md)
    mem_dir="${CLAUDE_DIR}/agent-memory/${agent_name}"
    mkdir -p "$mem_dir"
    dest="${mem_dir}/MEMORY.md"
    if [ ! -f "$dest" ]; then
        echo "# ${agent_name} Memory" > "$dest"
    fi
    echo "$dest" >> "$MANIFEST_TMP"
    MEM_COUNT=$((MEM_COUNT + 1))
done
info "Generated ${MEM_COUNT} agent memory files"

# CLAUDE.md: always copy (may be customized per-project)
dest="${CLAUDE_DIR}/CLAUDE.md"
cp "${SCRIPT_DIR}/CLAUDE.md" "$dest"
echo "$dest" >> "$MANIFEST_TMP"
info "Installed CLAUDE.md"

echo "$MANIFEST_FILE" >> "$MANIFEST_TMP"
mv "$MANIFEST_TMP" "$MANIFEST_FILE"
info "Wrote manifest ($(wc -l < "$MANIFEST_FILE" | tr -d ' ') files tracked)"

# Write install metadata
VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "dev")
META_TMP="${CLAUDE_DIR}/.alloy-meta.tmp"
jq -n --arg mode "$INSTALL_MODE" --arg ver "$VERSION" \
    '{"install_mode": $mode, "version": $ver}' > "$META_TMP"
mv "$META_TMP" "${CLAUDE_DIR}/.alloy-meta"

ALLOY_SETTINGS=$(jq -n --arg hd "$HOOK_DIR" '{
  "agent": "steel",
  "env": {
    "BASH_DEFAULT_TIMEOUT_MS": "420000",
    "BASH_MAX_TIMEOUT_MS": "420000",
    "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS": "1"
  },
  "statusLine": {
    "type": "command",
    "command": ($hd + "/statusline.sh")
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
      },
      {
        "matcher": ".*",
        "hooks": [{"type":"command","command":($hd + "/context-pressure.sh"),"timeout":3,"async":true}]
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
      .hooks.UserPromptSubmit = $alloy.hooks.UserPromptSubmit |
      .statusLine = ($orig.statusLine // $alloy.statusLine)
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
cat "${SCRIPT_DIR}/VERSION" > "${CLAUDE_DIR}/.alloy-version" 2>/dev/null || true

echo ""
success "claude-alloy is now active globally!"
echo ""
info "Start ${BOLD}claude${NC} in any directory — no /alloy-init needed."
info "Run ${BOLD}unalloy${NC} to deactivate and restore original settings."
info "Type ${BOLD}/ignite${NC} inside Claude for maximum effort mode."
echo ""
