#!/usr/bin/env bash
# Todo Continuation Enforcer — Blocks exit if todos remain incomplete
# Runs as Stop hook
# Exit 0 = allow stop, Exit 2 = block stop

set -u

# Read hook input from stdin
INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

# Prevent infinite re-blocking loop
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Extract transcript path
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Find the LAST TodoWrite call in the transcript.
# TodoWrite replaces the full list each time, so the last call IS the current state.
# We must check ONLY the last call — not historical entries where items were "pending".
# Scan only the tail of the transcript for speed — the last TodoWrite is always recent.
LAST_TODO_LINE=$(tail -500 "$TRANSCRIPT_PATH" 2>/dev/null | grep -n -i 'todowrite\|TodoWrite\|todo_write' | tail -1 | cut -d: -f1)

if [ -z "$LAST_TODO_LINE" ]; then
    # No todos were ever created — nothing to enforce
    exit 0
fi

# LAST_TODO_LINE is relative to the tail-500 window. Translate to absolute line number
# so the sed window below reads from the correct location in the full transcript.
TRANSCRIPT_LINES=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d ' ')
if [ "${TRANSCRIPT_LINES:-0}" -gt 500 ]; then
    LAST_TODO_LINE=$((TRANSCRIPT_LINES - 500 + LAST_TODO_LINE))
fi

# Extract a window around the last TodoWrite (its JSON payload follows within ~50 lines)
TODO_PAYLOAD=$(sed -n "${LAST_TODO_LINE},$((LAST_TODO_LINE + 50))p" "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

# Count incomplete items in this FINAL todo state only
# Use POSIX-compliant [[:space:]] instead of \s for portability
PENDING=$(echo "$TODO_PAYLOAD" | grep -cE '"status"[[:space:]]*:[[:space:]]*"pending"' 2>/dev/null) || PENDING=0
IN_PROGRESS=$(echo "$TODO_PAYLOAD" | grep -cE '"status"[[:space:]]*:[[:space:]]*"in_progress"' 2>/dev/null) || IN_PROGRESS=0
INCOMPLETE=$((PENDING + IN_PROGRESS))

if [ "$INCOMPLETE" -gt 0 ]; then
    STATE_DIR="${HOME}/.claude/.alloy-state"
    mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
    # Stale-file cleanup is centralized in hooks/session-end.sh.
    BLOCK_KEY=$(echo "$TRANSCRIPT_PATH" | cksum | cut -d' ' -f1)
    BLOCK_FILE="${STATE_DIR}/todo-blocked-${BLOCK_KEY}"

    if [ -f "$BLOCK_FILE" ]; then
        rm -f "$BLOCK_FILE"
        # Second attempt — allow stop but warn
        jq -nc --arg msg "Stopping with incomplete todos. Use /handoff to save progress." \
            '{systemMessage: $msg}'
        exit 0
    fi

    echo "1" > "$BLOCK_FILE"
    # First attempt — block stop
    jq -nc --argjson n "$INCOMPLETE" \
        '{decision: "block", reason: ("You have " + ($n | tostring) + " incomplete todos (pending/in_progress). Complete or cancel them before stopping.")}'
    exit 2
fi

BLOCK_KEY=$(echo "$TRANSCRIPT_PATH" | cksum | cut -d' ' -f1)
rm -f "${HOME}/.claude/.alloy-state/todo-blocked-${BLOCK_KEY}" 2>/dev/null || true

exit 0
