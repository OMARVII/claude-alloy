#!/usr/bin/env bash
# Subagent Stop Hook — Verifies agent deliverables and logs completion
# Runs as SubagentStop hook
# Exit 0 = always allow (warns via systemMessage if deliverable check fails)

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

LOG_FILE="${STATE_DIR}/agent-log.jsonl"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null) || LAST_MSG=""
MSG_LEN=${#LAST_MSG}

WARN=false

if [ "$MSG_LEN" -le 200 ]; then
    WARN=true
fi

if [ "$WARN" = false ] && echo "$LAST_MSG" | grep -qiE "I couldn't|I was unable|Error:|I don't have"; then
    WARN=true
fi

jq -nc --arg ts "$TIMESTAMP" --arg ev "stop" --argjson input "$INPUT" \
    '{timestamp: $ts, event: $ev, agent: $input}' >> "$LOG_FILE" 2>/dev/null || \
jq -nc --arg ts "$TIMESTAMP" --arg ev "stop" \
    '{timestamp: $ts, event: $ev, agent: {}}' >> "$LOG_FILE" 2>/dev/null

if [ "$WARN" = true ]; then
    jq -nc '{systemMessage: "Warning: agent may not have completed its task. Check results."}'
fi

exit 0
