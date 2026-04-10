#!/usr/bin/env bash
# Rate Limit Auto-Resume — Keeps session alive on rate limit
# Runs as StopFailure hook
# Resumes up to 3 times, then stops to avoid token waste

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // ""' 2>/dev/null) || STOP_REASON=""

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"
COUNTER_FILE="${STATE_DIR}/rate-limit-count"

# Only handle rate_limit — all other stop reasons pass through
if [ "$STOP_REASON" != "rate_limit" ]; then
    # Normal exit clears the counter (resets between rate limit bursts)
    rm -f "$COUNTER_FILE"
    exit 0
fi

# Read current counter
COUNT=0
if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null) || COUNT=0
    # Guard against non-numeric values
    case "$COUNT" in
        ''|*[!0-9]*) COUNT=0 ;;
    esac
fi

COUNT=$((COUNT + 1))

if [ "$COUNT" -ge 3 ]; then
    # Hit limit — stop and reset
    rm -f "$COUNTER_FILE"
    jq -n '{continue: false, stopReason: "Rate limit hit 3 consecutive times. Stopping to avoid token waste."}'
else
    # Resume — increment counter
    echo "$COUNT" > "$COUNTER_FILE"
    jq -n --arg msg "Rate limited. Auto-resuming (attempt ${COUNT}/3)..." \
        '{continue: true, systemMessage: $msg}'
fi
