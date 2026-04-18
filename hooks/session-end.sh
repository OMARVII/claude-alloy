#!/usr/bin/env bash
# Session End Hook — Nudges wiki update if session was productive
# Runs as SessionEnd hook (async)
# Exit 0 = always allow

set -u

# Consume hook input from stdin (required by hook protocol)
cat > /dev/null

# Centralized stale-file cleanup (moved out of hot-path hooks in v1.6.1).
# State dir convention: ~/.claude/.alloy-state
STATE_DIR="${HOME}/.claude/.alloy-state"
[ -d "$STATE_DIR" ] && find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null || true

command -v jq &>/dev/null || exit 0

# Count files changed in this session
FILES_CHANGED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
FILES_STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
TOTAL_CHANGED=$((FILES_CHANGED + FILES_STAGED))

# If fewer than 5 files changed, exit silently
if [ "$TOTAL_CHANGED" -lt 5 ]; then
    exit 0
fi

# Check for patterns worth learning (3+ edits to same file type)
LEARN_NUDGE=""
TOP_EXT=$(git diff --name-only 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')
if [ "${TOP_EXT:-0}" -ge 3 ] 2>/dev/null; then
    LEARN_NUDGE=" Consider running /learn to extract reusable patterns."
fi

jq -n --arg msg "This session touched ${TOTAL_CHANGED} files. Consider running /wiki-update to update project docs.${LEARN_NUDGE}" \
    '{"systemMessage": $msg}'
