#!/usr/bin/env bash
set -u

# v1.6.11 P2: skip on low-effort turns. Skill nudges are unproductive when the
# agent is intentionally operating in a constrained, lightweight mode.
if [ "${CLAUDE_EFFORT:-medium}" = "low" ]; then
    cat > /dev/null
    exit 0
fi

INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
# SESSION_ID: match context-pressure.sh pattern — default "unknown", regex-sanitize against
# CWE-22 path traversal before using in a filesystem path.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
[[ "$SESSION_ID" =~ ^[A-Za-z0-9_-]+$ ]] || SESSION_ID="unknown"

if [ -z "$TOOL_NAME" ]; then
    exit 0
fi

# shellcheck source=./_state-dir.sh
. "$(dirname "$0")/_state-dir.sh"
STATE_DIR="${HOME}/.claude/.alloy-state"
alloy_ensure_state_dir "$STATE_DIR" || exit 0
# Stale-file cleanup is centralized in hooks/session-end.sh.
WORK_REMINDER_THRESHOLD=${ALLOY_SKILL_REMINDER_WORK_THRESHOLD:-12}
case "$WORK_REMINDER_THRESHOLD" in
    ''|*[!0-9]*) WORK_REMINDER_THRESHOLD=12 ;;
esac

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

if [ "$COUNT" -ge "$WORK_REMINDER_THRESHOLD" ]; then
    echo "1" > "$REMINDER_FILE"
    jq -n --arg msg "[Skill Reminder] Sustained direct work detected (${COUNT} tool calls). If the task has expanded, load the matching skill or delegate the specialist portion: /git-master (commits, rebase, history), /frontend-ui-ux (UI design), /dev-browser (browser automation), /code-review (confidence-scored review), or @\"tungsten (agent)\" for complex implementation. If the work is still local and clear, continue directly." \
        '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
fi

exit 0
