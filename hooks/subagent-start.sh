#!/usr/bin/env bash
# Subagent Start Hook — Logs agent spawn events for tracking
# Runs as SubagentStart hook
# Exit 0 = always allow

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

LOG_FILE="${STATE_DIR}/agent-log.jsonl"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

jq -nc --arg ts "$TIMESTAMP" --arg ev "start" --argjson input "$INPUT" \
    '{timestamp: $ts, event: $ev, agent: $input}' >> "$LOG_FILE" 2>/dev/null || \
jq -nc --arg ts "$TIMESTAMP" --arg ev "start" \
    '{timestamp: $ts, event: $ev, agent: {}}' >> "$LOG_FILE" 2>/dev/null

exit 0
