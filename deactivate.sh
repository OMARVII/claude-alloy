#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[ALLOY]${NC} $1"; }
success() { echo -e "${GREEN}[ALLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[ALLOY]${NC} $1"; }

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
BACKUP_FILE="${CLAUDE_DIR}/settings.json.alloy-backup"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   claude-alloy — Global Deactivation       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

MANIFEST_FILE="${CLAUDE_DIR}/.alloy-manifest"

force_uninstall() {
    local FOUND_SOMETHING=false
    for dir in agents skills commands alloy-hooks agent-memory; do
        if [ -d "${CLAUDE_DIR}/${dir}" ]; then
            rm -rf "${CLAUDE_DIR:?}/${dir}"
            FOUND_SOMETHING=true
        fi
    done
    if [ -f "${CLAUDE_DIR}/CLAUDE.md" ]; then
        rm -f "${CLAUDE_DIR}/CLAUDE.md"
        FOUND_SOMETHING=true
    fi
    if [ "$FOUND_SOMETHING" = true ]; then
        info "Force-removed agents, skills, commands, hooks, memory"
    else
        warn "No Alloy files found — nothing to remove"
    fi
}

if [ ! -f "$MANIFEST_FILE" ]; then
    if [ "${1:-}" = "--force" ]; then
        warn "No manifest found. Running legacy force uninstall..."
        force_uninstall
    else
        warn "No manifest found at ${MANIFEST_FILE}"
        warn "This means activate.sh was run before manifest support was added."
        warn "Re-run with --force to use legacy behavior (removes entire directories):"
        echo ""
        echo "  bash $(basename "$0") --force"
        echo ""
        warn "Or re-activate first (to generate a manifest), then deactivate."
        exit 1
    fi
else
    REMOVED=0
    SKIPPED=0
    while IFS= read -r filepath; do
        [ -z "$filepath" ] && continue
        # Validate path is within CLAUDE_DIR to prevent out-of-scope deletion
        case "$filepath" in
            "${CLAUDE_DIR}/"*|"${CLAUDE_DIR}") ;;
            *) warn "Skipping out-of-scope path: $filepath"; continue ;;
        esac
        if [ -f "$filepath" ] || [ -L "$filepath" ]; then
            rm -f "$filepath"
            REMOVED=$((REMOVED + 1))
        else
            SKIPPED=$((SKIPPED + 1))
        fi
    done < "$MANIFEST_FILE"
    info "Removed ${REMOVED} files (${SKIPPED} already absent)"

    # Clean up empty directories left behind
    for dir in agents skills commands alloy-hooks agent-memory; do
        if [ -d "${CLAUDE_DIR}/${dir}" ]; then
            find "${CLAUDE_DIR}/${dir}" -type d -empty -delete 2>/dev/null || true
        fi
    done
    info "Cleaned up empty directories"
fi

# Clean up metadata files
rm -f "${CLAUDE_DIR}/.alloy-meta"
rm -f "${CLAUDE_DIR}/.alloy-manifest"

if [ -f "$BACKUP_FILE" ]; then
    mv "$BACKUP_FILE" "$SETTINGS_FILE"
    info "Restored original settings.json"
elif [ -f "$SETTINGS_FILE" ]; then
    rm -f "$SETTINGS_FILE"
    info "Removed Alloy settings.json (no original to restore)"
fi

echo ""
success "claude-alloy deactivated. Back to vanilla Claude."
echo ""
info "Run ${BLUE}alloy${NC} to reactivate anytime."
echo ""
