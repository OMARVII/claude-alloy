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
# Stale-file cleanup is centralized in hooks/session-end.sh (runs once per session).

# One-shot per session: once the reminder has fired, never fire again.
# Mirrors the pattern in hooks/skill-reminder.sh. The previous behavior
# fired on every 2 search calls and reset the counter to 0, so the same
# [Agent Usage Reminder] block was injected into context every two grep/glob
# calls — wasting tokens on every research-heavy session.
REMINDER_FILE="${STATE_DIR}/agent-reminded-${SESSION_ID}"
if [ -f "$REMINDER_FILE" ]; then
    exit 0
fi

STATE_FILE="${STATE_DIR}/agent-reminder-${SESSION_ID}"

TOOL_LOWER=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')

AGENT_TOOLS="agent task"
SEARCH_TOOLS="grep glob webfetch websearch mcp__context7 mcp__grep_app"

for at in $AGENT_TOOLS; do
    if [ "$TOOL_LOWER" = "$at" ] || echo "$TOOL_LOWER" | grep -qi "^agent"; then
        echo "1" > "$STATE_FILE"
        exit 0
    fi
done

IS_SEARCH=false

# Native Claude Code search tools (canonical names).
for st in $SEARCH_TOOLS; do
    if echo "$TOOL_LOWER" | grep -qi "$st"; then
        IS_SEARCH=true
        break
    fi
done

# Bash-as-search fallback. When the host environment doesn't expose the
# native Grep tool (older Claude Code projects, restricted tool registries),
# users fall back to bash invocations of grep/rg/ag/find/fd/ack as their
# search primitive. Treat those exactly like a Grep call so the reminder
# fires consistently regardless of the project's tool surface.
#
# Only inspects the FIRST token of the bash command — `git grep` and
# `find . -name foo` count, but `echo "regex"` doesn't (false positive on
# 'rg' in echoed strings is what we're avoiding).
if [ "$IS_SEARCH" = false ] && [ "$TOOL_LOWER" = "bash" ]; then
    BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
    # Strip leading whitespace + take first whitespace-delimited token.
    FIRST_TOKEN=$(printf '%s' "$BASH_CMD" | sed -E 's/^[[:space:]]+//' | awk '{print $1}')
    case "$FIRST_TOKEN" in
        grep|rg|ag|ack|find|fd)
            IS_SEARCH=true
            ;;
        git)
            # `git grep ...` and `git log -S/-G ...` are searches. Inspect
            # second token to disambiguate from `git status` / `git commit`.
            SECOND_TOKEN=$(printf '%s' "$BASH_CMD" | sed -E 's/^[[:space:]]+//' | awk '{print $2}')
            case "$SECOND_TOKEN" in
                grep|log) IS_SEARCH=true ;;
            esac
            ;;
    esac
fi

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
# Guard against corrupted counter content (set -u + non-numeric = silent fail).
case "$COUNT" in
    ''|*[!0-9]*) COUNT=0 ;;
esac
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Threshold lowered from 2 to 1: the reminder is one-shot per session anyway,
# so making the user wait for a second search before any signal appears
# defeated the purpose. Fires on first search → marker prevents re-fire.
if [ "$COUNT" -ge 1 ]; then
    # Mark reminded so the early-exit guard above prevents re-firing this session.
    echo "1" > "$REMINDER_FILE"
    if [ "${ALLOY_DEBUG:-0}" = "1" ]; then
        printf '[alloy] agent-reminder fired session=%s tool=%s\n' \
            "$SESSION_ID" "$TOOL_NAME" >&2
    fi
    jq -n --arg msg '[Agent Usage Reminder] You'\''re calling search/fetch tools directly without leveraging specialized agents. RECOMMENDED: Use @"mercury (agent)" for codebase searches and @"graphene (agent)" for external docs/examples. They run in background and search more thoroughly than individual tool calls.' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
fi

exit 0
