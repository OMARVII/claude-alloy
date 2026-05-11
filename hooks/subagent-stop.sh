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
#
# agent_id receives the same sanitization as defense-in-depth: it is not
# currently used in a filesystem path here, but pre-sanitizing it ensures
# any future per-agent file path (per-agent ledger, transcript pointer)
# inherits a safe shape without a separate audit pass.
#
# Single jq pass — earlier revisions forked jq three separate times to read
# session_id, agent_type, and last_assistant_message; on a hot path that
# fires for every SubagentStop, three forks adds ~6-15ms per stop event.
# Emit one line per field, newline-delimited (NOT tab-separated), because
# IFS=$'\t' read collapses empty fields and last_assistant_message is the
# most likely field to be empty.
JQ_OUT=$(echo "$INPUT" | jq -r '
    [
      (.session_id // "default"),
      (.agent_id // ""),
      (.agent_type // .subagent_type // .tool_input.subagent_type // .tool_use.input.subagent_type // ""),
      (.last_assistant_message // "" | gsub("\n"; "\\n"))
    ] | .[]
' 2>/dev/null) || JQ_OUT=""
SESSION_ID=$(printf '%s\n' "$JQ_OUT" | sed -n '1p')
AGENT_ID=$(printf '%s\n' "$JQ_OUT" | sed -n '2p')
AGENT_TYPE=$(printf '%s\n' "$JQ_OUT" | sed -n '3p')
LAST_MSG=$(printf '%s\n' "$JQ_OUT" | sed -n '4p')
# Empty fallbacks if the jq call failed entirely.
[ -n "$SESSION_ID" ] || SESSION_ID="default"
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
AGENT_ID=$(printf '%s' "$AGENT_ID" | tr -cd 'a-zA-Z0-9_-')

AGENT_TYPE_LOWER=$(echo "${AGENT_TYPE:-}" | tr '[:upper:]' '[:lower:]')
if [ "$AGENT_TYPE_LOWER" = "tungsten" ] && [ -n "$SESSION_ID" ]; then
    rm -f "${STATE_DIR}/tungsten-active-${SESSION_ID}" 2>/dev/null || true
fi

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
