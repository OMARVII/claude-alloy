#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[ALLOY]${NC} $1"; }
success() { echo -e "${GREEN}[ALLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[ALLOY]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--uninstall" ]; then
    info "Removing alloy/unalloy aliases..."
    for profile in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
        if [ -f "$profile" ] && grep -q '>>> claude-alloy aliases >>>' "$profile" 2>/dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' '/>>> claude-alloy aliases >>>/,/<<< claude-alloy aliases <<</d' "$profile"
            else
                sed -i '/>>> claude-alloy aliases >>>/,/<<< claude-alloy aliases <<</d' "$profile"
            fi
            info "Removed from $(basename "$profile")"
        fi
    done
    success "Done. Aliases removed."
    exit 0
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   claude-alloy — Alias Setup               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

ALIAS_BLOCK="
# >>> claude-alloy aliases >>>
alias alloy='bash \"${SCRIPT_DIR}/activate.sh\"'
alias unalloy='bash \"${SCRIPT_DIR}/deactivate.sh\"'
# <<< claude-alloy aliases <<<"

INSTALLED=0

for profile in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
    if [ -f "$profile" ]; then
        if grep -q '>>> claude-alloy aliases >>>' "$profile" 2>/dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' '/>>> claude-alloy aliases >>>/,/<<< claude-alloy aliases <<</d' "$profile"
            else
                sed -i '/>>> claude-alloy aliases >>>/,/<<< claude-alloy aliases <<</d' "$profile"
            fi
        fi
        echo "$ALIAS_BLOCK" >> "$profile"
        info "Added to $(basename "$profile")"
        INSTALLED=$((INSTALLED + 1))
    fi
done

if [ "$INSTALLED" -eq 0 ]; then
    warn "No shell profiles found. Create ~/.zshrc or ~/.bashrc first."
    echo ""
    info "Or add manually to your shell profile:"
    echo "  alias alloy='bash \"${SCRIPT_DIR}/activate.sh\"'"
    echo "  alias unalloy='bash \"${SCRIPT_DIR}/deactivate.sh\"'"
    exit 1
fi

echo ""
success "Aliases installed!"
echo ""
info "Restart your terminal, or run now:"
echo ""
echo "  source ~/.zshrc"
echo ""
info "Then:"
echo ""
echo "  ${BOLD}alloy${NC}     Activate claude-alloy globally"
echo "  ${BOLD}unalloy${NC}   Deactivate and restore vanilla Claude"
echo ""
info "To uninstall aliases: bash ${SCRIPT_DIR}/setup-aliases.sh --uninstall"
echo ""
