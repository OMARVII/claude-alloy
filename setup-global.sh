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

if [ "${1:-}" = "--uninstall" ]; then
    info "Removing /alloy-init global command..."
    rm -f "${CLAUDE_DIR}/commands/alloy-init.md"
    success "Done. /alloy-init removed."
    exit 0
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   claude-alloy — Global /alloy-init Setup  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

mkdir -p "${CLAUDE_DIR}/commands"

# Copy install.sh to ~/.claude/ so /alloy-init survives if the user moves the cloned repo
cp "${SCRIPT_DIR}/install.sh" "${CLAUDE_DIR}/alloy-install.sh"
chmod +x "${CLAUDE_DIR}/alloy-install.sh"
info "Copied installer to ${CLAUDE_DIR}/alloy-install.sh"

cat > "${CLAUDE_DIR}/commands/alloy-init.md" << INITMAX_EOF
---
description: "Install claude-alloy harness into the current project. Adds 14 agents, 10 skills, 14 commands, 17 hooks, and agent memory."
---

# /alloy-init — Install claude-alloy Into This Project

Run the claude-alloy installer for the current working directory.

\`\`\`bash
bash ${CLAUDE_DIR}/alloy-install.sh --project .
\`\`\`

After installation, you'll have:
- **14 agents** — steel (opus), tungsten (opus), quartz (opus), mercury (haiku), graphene (sonnet), carbon (sonnet), prism (sonnet), gauge (sonnet), spectrum (sonnet), sentinel (opus), titanium (sonnet), iridium (sonnet), cobalt (sonnet), flint (sonnet)
- **10 skills** — git-master, frontend-ui-ux, dev-browser, code-review, review-work, ai-slop-remover, tdd-workflow, verification-loop, wiki, learn
- **14 commands** — /ignite, /ig, /loop, /init-deep, /refactor, /start-work, /handoff, /halt, /alloy, /unalloy, /status, /wiki-update, /notify-setup, /learn
- **17 hooks** — intent detection, branch protection, write guard, comment checker, typecheck, auto-install, agent & skill reminders, todo enforcer, loop, session notify, pre-compact, subagent-start, subagent-stop, rate-limit-resume, session-start, session-end
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
echo "  6. All 14 agents + 17 hooks active"
echo ""
info "Installer copy: ${CLAUDE_DIR}/alloy-install.sh"
info "Global command: ${CLAUDE_DIR}/commands/alloy-init.md"
echo ""
warn "To remove: bash ${SCRIPT_DIR}/setup-global.sh --uninstall"
