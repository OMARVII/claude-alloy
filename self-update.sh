#!/usr/bin/env bash
# claude-alloy self-update checker
# Called from activate.sh in a subshell — failures here never block activation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
NO_UPDATE_FILE="${CLAUDE_DIR}/.alloy-no-update"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[ALLOY]${NC} $1"; }
success() { echo -e "${GREEN}[ALLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[ALLOY]${NC} $1"; }

# --- Opt-out checks ---

# Persistent file-based opt-out
[ -f "$NO_UPDATE_FILE" ] && exit 0

# Env var opt-out
[ "${ALLOY_AUTO_UPDATE:-}" = "0" ] && exit 0

# CLI flag opt-out (--skip-update passed from activate.sh)
for arg in "$@"; do
    [ "$arg" = "--skip-update" ] && exit 0
done

# --- Git repo checks ---

# Not a git repo (tarball install) — skip silently
[ -d "$SCRIPT_DIR/.git" ] || exit 0

cd "$SCRIPT_DIR" || exit 0

# Not on main branch — skip silently
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
[ "$BRANCH" = "main" ] || exit 0

# Remote URL safety check — only fetch from known origin
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
# Exact match (not substring) — prevents e.g. github.com/OMARVII/claude-alloy-evil from passing
NORMALIZED_REMOTE="$(echo "$REMOTE_URL" | sed -E 's#^(https://)?(git@)?github\.com[:/]##; s#\.git$##')"
if [ "$NORMALIZED_REMOTE" != "OMARVII/claude-alloy" ]; then
    exit 0
fi

# --- Fetch with timeout ---

GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=3 \
    git fetch --quiet origin main 2>/dev/null || exit 0

# --- Compare versions ---

LOCAL_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
REMOTE_SHA=$(git rev-parse origin/main 2>/dev/null || echo "")

# Already up to date
[ "$LOCAL_SHA" = "$REMOTE_SHA" ] && exit 0

# Count commits behind
BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
[ "$BEHIND" = "0" ] && exit 0

LOCAL_VER=$(git describe --tags --always 2>/dev/null || echo "unknown")
REMOTE_VER=$(git describe --tags --always origin/main 2>/dev/null || echo "unknown")

# --- Check if user wants to apply ---

FORCE_UPDATE=false
for arg in "$@"; do
    [ "$arg" = "--update" ] && FORCE_UPDATE=true
done

if [ "$FORCE_UPDATE" = true ] || [ "${ALLOY_AUTO_UPDATE:-}" = "1" ]; then
    info "Pulling latest from origin/main..."
    if git pull --ff-only origin main 2>/dev/null; then
        # Read install mode from metadata
        META_FILE="${CLAUDE_DIR}/.alloy-meta"
        CURRENT_MODE="copy"
        if [ -f "$META_FILE" ] && command -v jq &>/dev/null; then
            CURRENT_MODE=$(jq -r '.install_mode // "copy"' "$META_FILE" 2>/dev/null || echo "copy")
        fi
        if [ "$CURRENT_MODE" = "symlink" ]; then
            success "Updated ${LOCAL_VER} → ${REMOTE_VER} (${BEHIND} new commits). Changes are live immediately."
        else
            success "Updated ${LOCAL_VER} → ${REMOTE_VER} (${BEHIND} new commits). Run 'alloy' to apply the update."
        fi
    else
        warn "Update available (${LOCAL_VER} → ${REMOTE_VER}) but your local repo has diverged."
        warn "Fix: cd ${SCRIPT_DIR} && git pull --rebase origin main"
    fi
else
    echo ""
    info "Update available: ${LOCAL_VER} → ${REMOTE_VER} (${BEHIND} commits behind)"
    info "Run ${GREEN}alloy --update${NC} to apply."
    echo ""
fi
