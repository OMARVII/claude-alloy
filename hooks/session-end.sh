#!/usr/bin/env bash
# Session End Hook — Nudges wiki update if session was productive
# Runs as SessionEnd hook (async)
# Exit 0 = always allow

set -u

# Consume hook input from stdin (required by hook protocol)
INPUT=$(cat 2>/dev/null || true)

# Centralized stale-file cleanup (moved out of hot-path hooks in v1.6.1).
# State dir convention: ~/.claude/.alloy-state
STATE_DIR="${HOME}/.claude/.alloy-state"
if [ -d "$STATE_DIR" ]; then
    find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null
    # Tool-count counters rotate fast; prune aggressively so stale sessions
    # don't accumulate. context-pressure.sh used to do this inline — moved
    # here to finish the v1.6.1 centralization.
    find "$STATE_DIR" -name 'tool-count-*' -mtime +1 -delete 2>/dev/null
    # Pre-compact backup dirs (v1.6.7) — directory-level prune since the file
    # janitor above empties dirs but doesn't remove them. -depth so children
    # are reached first; -mindepth 1 so we never touch STATE_DIR itself.
    find "$STATE_DIR" -mindepth 1 -depth -type d -name 'compact-backup-*' -mtime +7 -exec rm -rf {} + 2>/dev/null

    # Per-session marker cleanup. The Stop-gate reads code-edited-${SESSION_ID}
    # as a positive signal that implementation edits occurred; if that marker
    # is not removed at session end, the NEXT session that reuses the same id
    # (or any future read against the same marker) would mistakenly conclude
    # edits already happened. Bind the cleanup to the session that's ending.
    if command -v jq >/dev/null 2>&1; then
        SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
        SESSION_ID=$(printf '%s' "${SESSION_ID:-}" | tr -cd 'a-zA-Z0-9_-')
        if [ -n "$SESSION_ID" ]; then
            rm -f "${STATE_DIR}/code-edited-${SESSION_ID}" 2>/dev/null || true
        fi
    fi
fi

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
