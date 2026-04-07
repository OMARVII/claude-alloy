#!/usr/bin/env bash
# Loop Stop Hook — Blocks exit unless completion promise is found
# Runs as Stop hook
# Exit 0 = allow stop, Exit 2 = block and continue loop

set -u

INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

# Check if loop is active by looking for the state file
# Use project dir if available, fall back to HOME
LOOP_DIR="${CLAUDE_PROJECT_DIR:-${HOME}}/.claude"
LOOP_STATE="${LOOP_DIR}/alloy-loop-active"

if [ ! -f "$LOOP_STATE" ]; then
    # Loop not active, allow normal stop
    exit 0
fi

# Read the loop config
TASK_PROMPT=$(cat "$LOOP_STATE" 2>/dev/null || echo "")

if [ -z "$TASK_PROMPT" ]; then
    exit 0
fi

# Check if the transcript contains the completion promise
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Look for the completion promise in the last message
    if tail -5 "$TRANSCRIPT_PATH" 2>/dev/null | grep -q '<promise>DONE</promise>'; then
        # Task complete! Clean up state file
        rm -f "$LOOP_STATE"
        exit 0
    fi
fi

# Loop active but task not complete — block exit and continue
printf '%s\n' "Loop is active. Your task is not complete yet. Continue working on: ${TASK_PROMPT}" >&2
printf '\n' >&2
printf 'Review your progress. Check what'\''s done and what remains. Then keep going.\n' >&2
printf 'Only output <promise>DONE</promise> when the task is genuinely 100%% complete.\n' >&2
exit 2
