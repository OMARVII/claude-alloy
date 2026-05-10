#!/usr/bin/env bash
# Edit Ledger — records implementation edits for IGNITE review enforcement.
# Runs as PostToolUse on Edit|Write|MultiEdit|NotebookEdit.

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

# shellcheck source=hooks/_state-dir.sh
. "$(dirname "$0")/_state-dir.sh"
STATE_DIR="${HOME}/.claude/.alloy-state"
alloy_ensure_state_dir "$STATE_DIR" || exit 0

FIELDS=$(printf '%s' "$INPUT" | jq -r '
    [
        (.session_id // "default"),
        (.tool_name // .tool_use.name // ""),
        (
            .tool_input.file_path
            // .tool_input.path
            // .tool_use.input.file_path
            // .tool_use.input.path
            // ""
        )
    ] | join("\u001f")
' 2>/dev/null || printf 'default\037\037')

IFS=$'\037' read -r SESSION_ID TOOL_NAME FILE_PATH <<EOF
$FIELDS
EOF
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')

case "$TOOL_NAME" in
    Edit|Write|MultiEdit|NotebookEdit) ;;
    *) exit 0 ;;
esac

IS_STATE_BOOKKEEPING=false
case "$FILE_PATH" in
    "$STATE_DIR"/*)
        STATE_FILE=${FILE_PATH#"$STATE_DIR"/}
        case "$STATE_FILE" in
            */*|.*|*..*) ;;
            agent-count-*|agents-spawned-*|ignite-active-*|ignite-blocked-*)
                if [ ! -L "$FILE_PATH" ]; then
                    IS_STATE_BOOKKEEPING=true
                fi
                ;;
        esac
        ;;
esac

if [ "$IS_STATE_BOOKKEEPING" = "true" ]; then
    exit 0
fi

MARKER_FILE="${STATE_DIR}/code-edited-${SESSION_ID}"
printf '%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$TOOL_NAME" "$FILE_PATH" >> "$MARKER_FILE" 2>/dev/null || true
chmod 600 "$MARKER_FILE" 2>/dev/null || true

exit 0
