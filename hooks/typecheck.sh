#!/usr/bin/env bash
set -u

# Opt-in only: runs project-local npx binaries — see SECURITY.md
[ "${ALLOY_AUTO_LINT:-}" = "1" ] || exit 0

INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Reject path traversal — skip analysis (PostToolUse cannot block)
case "$FILE_PATH" in
    *../*|*/..*|*..)
        exit 0
        ;;
esac

case "$FILE_PATH" in
    *.ts|*.tsx)
        ;;
    *)
        exit 0
        ;;
esac

PROJ_DIR="$FILE_PATH"
while [ "$PROJ_DIR" != "/" ]; do
    PROJ_DIR=$(dirname "$PROJ_DIR")
    [ -f "$PROJ_DIR/tsconfig.json" ] && break
done

if [ ! -f "$PROJ_DIR/tsconfig.json" ]; then
    exit 0
fi

OUTPUT=$(cd "$PROJ_DIR" && npx --no-install tsc --noEmit --incremental 2>&1) || true
ERRORS=$(echo "$OUTPUT" | grep "error TS" | head -10)

if [ -n "$ERRORS" ]; then
    # Use jq for safe JSON construction (handles special chars in error messages)
    jq -n --arg msg "[TypeCheck] Errors found: $ERRORS" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
fi

exit 0
