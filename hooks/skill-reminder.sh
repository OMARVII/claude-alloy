#!/usr/bin/env bash
set -u

INPUT=$(cat)

# Require jq for JSON parsing
if ! command -v jq &>/dev/null; then
    echo '{"hookSpecificOutput":{"message":"[ALLOY] jq is required. Install: brew install jq (macOS) or apt install jq (Linux)"}}'
    exit 0
fi

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

TOOL_LOWER=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')

DELEGATION_TOOLS="agent task skill"
WORK_TOOLS="edit write bash read grep glob"

IS_DELEGATION=false
for dt in $DELEGATION_TOOLS; do
    if echo "$TOOL_LOWER" | grep -qi "$dt"; then
        IS_DELEGATION=true
        break
    fi
done

if [ "$IS_DELEGATION" = true ]; then
    echo "1" > "${STATE_DIR}/delegated-${SESSION_ID}"
    exit 0
fi

IS_WORK=false
for wt in $WORK_TOOLS; do
    if echo "$TOOL_LOWER" | grep -qi "^${wt}$"; then
        IS_WORK=true
        break
    fi
done

if [ "$IS_WORK" = false ]; then
    exit 0
fi

DELEGATED="0"
if [ -f "${STATE_DIR}/delegated-${SESSION_ID}" ]; then
    DELEGATED=$(cat "${STATE_DIR}/delegated-${SESSION_ID}" 2>/dev/null || echo "0")
fi

if [ "$DELEGATED" = "1" ]; then
    exit 0
fi

REMINDER_FILE="${STATE_DIR}/skill-reminded-${SESSION_ID}"
if [ -f "$REMINDER_FILE" ]; then
    exit 0
fi

COUNTER_FILE="${STATE_DIR}/work-count-${SESSION_ID}"
COUNT=0
if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

if [ "$COUNT" -ge 8 ]; then
    echo "1" > "$REMINDER_FILE"
    jq -n --arg msg "[Skill Reminder] You've made ${COUNT} direct tool calls without delegating. Available skills: /git-master (commits, rebase, history), /frontend-ui-ux (UI design), /dev-browser (browser automation), /code-review (confidence-scored review). For complex work, delegate to @\"tungsten (agent)\" instead of doing it yourself." \
        '{"hookSpecificOutput":{"message":$msg}}'
fi

exit 0
