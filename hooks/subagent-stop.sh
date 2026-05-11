#!/usr/bin/env bash
# Subagent Stop Hook — Verifies agent deliverables and logs completion
# Runs as SubagentStop hook
# Exit 0 = always allow (warns via systemMessage if deliverable check fails)

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

# shellcheck source=hooks/_state-dir.sh
. "$(dirname "$0")/_state-dir.sh"
STATE_DIR="${HOME}/.claude/.alloy-state"
alloy_ensure_state_dir "$STATE_DIR" || exit 0

LOG_FILE="${STATE_DIR}/agent-log.jsonl"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# SubagentStop schema (https://code.claude.com/docs/en/hooks): input carries
# agent_id + agent_type at the top level. Read agent_type to clear the
# matching tungsten-active marker so pre-compact.sh stops blocking
# compaction once tungsten finishes. session_id is sanitized to the
# [A-Za-z0-9_-] allowlist before any filesystem use (CWE-22 guard).
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
AGENT_TYPE=$(echo "$INPUT" | jq -r '
    .agent_type
    // .subagent_type
    // .tool_input.subagent_type
    // .tool_use.input.subagent_type
    // empty
' 2>/dev/null || echo "")
AGENT_TYPE_LOWER=$(echo "${AGENT_TYPE:-}" | tr '[:upper:]' '[:lower:]')
if [ "$AGENT_TYPE_LOWER" = "tungsten" ] && [ -n "$SESSION_ID" ]; then
    rm -f "${STATE_DIR}/tungsten-active-${SESSION_ID}" 2>/dev/null || true
fi

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
