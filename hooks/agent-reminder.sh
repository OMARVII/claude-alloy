#!/usr/bin/env bash
set -u

INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')

if [ -z "$TOOL_NAME" ]; then
    exit 0
fi

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"

# Clean up stale state files (older than 7 days)
find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null || true

STATE_FILE="${STATE_DIR}/agent-reminder-${SESSION_ID}"

TOOL_LOWER=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')

AGENT_TOOLS="agent task"
SEARCH_TOOLS="grep glob webfetch websearch mcp_websearch mcp_context7 mcp_grep_app"

for at in $AGENT_TOOLS; do
    if [ "$TOOL_LOWER" = "$at" ] || echo "$TOOL_LOWER" | grep -qi "^agent"; then
        echo "1" > "$STATE_FILE"
        exit 0
    fi
done

IS_SEARCH=false
for st in $SEARCH_TOOLS; do
    if echo "$TOOL_LOWER" | grep -qi "$st"; then
        IS_SEARCH=true
        break
    fi
done

if [ "$IS_SEARCH" = false ]; then
    exit 0
fi

AGENT_USED="0"
if [ -f "$STATE_FILE" ]; then
    AGENT_USED=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
fi

if [ "$AGENT_USED" = "1" ]; then
    exit 0
fi

COUNTER_FILE="${STATE_DIR}/search-count-${SESSION_ID}"
COUNT=0
if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

if [ "$COUNT" -ge 2 ]; then
    jq -n --arg msg '[Agent Usage Reminder] You'\''re calling search/fetch tools directly without leveraging specialized agents. RECOMMENDED: Use @"mercury (agent)" for codebase searches and @"graphene (agent)" for external docs/examples. They run in background and search more thoroughly than individual tool calls.' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
    echo "0" > "$COUNTER_FILE"
fi

exit 0
