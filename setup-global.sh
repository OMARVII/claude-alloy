#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[ALLOY]${NC} $1"; }
success() { echo -e "${GREEN}[ALLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[ALLOY]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
DIST_DIR="${CLAUDE_DIR}/alloy-dist"

if [ "${1:-}" = "--uninstall" ]; then
    info "Removing /alloy-init global command..."
    rm -f "${CLAUDE_DIR:?}/commands/alloy-init.md"
    rm -f "${CLAUDE_DIR:?}/alloy-install.sh"
    rm -rf "${DIST_DIR:?}"
    success "Done. /alloy-init removed."
    exit 0
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   claude-alloy — Global /alloy-init Setup  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

mkdir -p "${CLAUDE_DIR}/commands"

# Stale check — warn if alloy-dist is outdated
if [ -d "$DIST_DIR" ] && [ -f "$DIST_DIR/VERSION" ]; then
    DIST_VER=$(cat "$DIST_DIR/VERSION" 2>/dev/null || echo "unknown")
    REPO_VER=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")
    if [ "$DIST_VER" != "$REPO_VER" ]; then
        warn "alloy-dist is stale (dist: ${DIST_VER}, repo: ${REPO_VER}) — refreshing..."
    fi
fi

# Copy the full install payload so /alloy-init survives if the user moves the cloned repo.
rm -rf "${DIST_DIR:?}"
mkdir -p "$DIST_DIR"
cp "${SCRIPT_DIR}/install.sh" "$DIST_DIR/install.sh"
cp "${SCRIPT_DIR}/CLAUDE.md" "$DIST_DIR/CLAUDE.md"
cp -R "${SCRIPT_DIR}/agents" "$DIST_DIR/agents"
cp -R "${SCRIPT_DIR}/skills" "$DIST_DIR/skills"
cp -R "${SCRIPT_DIR}/commands" "$DIST_DIR/commands"
cp -R "${SCRIPT_DIR}/hooks" "$DIST_DIR/hooks"
cp -R "${SCRIPT_DIR}/wiki" "$DIST_DIR/wiki"
cp "${SCRIPT_DIR}/VERSION" "$DIST_DIR/VERSION"
chmod +x "$DIST_DIR/install.sh"
info "Copied installer payload to ${DIST_DIR}"

cat > "${CLAUDE_DIR}/commands/alloy-init.md" << INITMAX_EOF
---
description: "Install claude-alloy harness into the current project. Adds 14 agents, 8 skills, 14 commands, 19 hooks, and agent memory."
---

# /alloy-init — Install claude-alloy Into This Project

Run the claude-alloy installer for the current working directory.

\`\`\`bash
bash ${DIST_DIR}/install.sh --project .
\`\`\`

After installation, you'll have:
- **14 agents** — steel (opus), tungsten (opus), quartz (opus), mercury (haiku), graphene (sonnet), carbon (sonnet), prism (sonnet), gauge (sonnet), spectrum (sonnet), sentinel (opus), titanium (sonnet), iridium (sonnet), cobalt (sonnet), flint (sonnet)
- **8 skills** — git-master, frontend-ui-ux, dev-browser, code-review, review-work, ai-slop-remover, tdd-workflow, verification-loop
- **14 commands** — /ignite, /ig, /loop, /init-deep, /refactor, /start-work, /handoff, /halt, /alloy, /unalloy, /status, /wiki-update, /notify-setup, /learn
- **19 hooks** — intent detection, branch protection, write guard, comment checker, typecheck, auto-install, agent & skill reminders, todo enforcer, loop, session notify, pre-compact, subagent-start, subagent-stop, rate-limit-resume, session-start, session-end, ignite-stop-gate, ignite-detector
- **14 agent memory files** — persistent cross-session learning per agent
- **Environment tuning** — 7min bash timeout

**After install, type \`/ignite\` to activate maximum effort mode.**

**To uninstall from this project later:**
\`\`\`bash
rm -rf .claude
\`\`\`
INITMAX_EOF

success "Created /alloy-init global command"
echo ""
info "How it works:"
echo "  1. Open any project:  cd ~/my-project"
echo "  2. Start Claude Code:  claude"
echo "  3. Type:  /alloy-init"
echo "  4. Claude runs the installer for that project"
echo "  5. Type:  /ignite"
echo "  6. All 14 agents + 19 hooks active"
echo ""
info "Installer payload: ${DIST_DIR}"
info "Global command: ${CLAUDE_DIR}/commands/alloy-init.md"
echo ""
info "To remove: bash ${SCRIPT_DIR}/setup-global.sh --uninstall"
