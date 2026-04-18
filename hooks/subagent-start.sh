#!/usr/bin/env bash
# Subagent Start Hook — Logs agent spawn events and tracks per-session state
# Runs as SubagentStart hook
# Exit 0 = always allow

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
# Stale-file cleanup is centralized in hooks/session-end.sh.

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Extract session_id and agent_type from input
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || echo "")

# Append to global agent log (existing behavior)
LOG_FILE="${STATE_DIR}/agent-log.jsonl"
jq -nc --arg ts "$TIMESTAMP" --arg ev "start" --argjson input "$INPUT" \
    '{timestamp: $ts, event: $ev, agent: $input}' >> "$LOG_FILE" 2>/dev/null || \
jq -nc --arg ts "$TIMESTAMP" --arg ev "start" \
    '{timestamp: $ts, event: $ev, agent: {}}' >> "$LOG_FILE" 2>/dev/null

# Track per-session agent count
COUNT_FILE="${STATE_DIR}/agent-count-${SESSION_ID}"
COUNT=0
if [ -f "$COUNT_FILE" ]; then
    COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo "0")
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

# Track per-session agent types (one per line)
if [ -n "$AGENT_TYPE" ]; then
    AGENTS_FILE="${STATE_DIR}/agents-spawned-${SESSION_ID}"
    echo "$AGENT_TYPE" >> "$AGENTS_FILE"
fi

exit 0
