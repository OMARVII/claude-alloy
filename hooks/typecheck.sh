#!/usr/bin/env bash
set -u

INPUT=$(cat)

# Require jq for JSON parsing
if ! command -v jq &>/dev/null; then
    echo '{"hookSpecificOutput":{"message":"[ALLOY] jq is required. Install: brew install jq (macOS) or apt install jq (Linux)"}}'
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Reject path traversal
case "$FILE_PATH" in
    *../*|*/..*|*..)
        echo "Path traversal detected in '$FILE_PATH'. Skipping." >&2
        exit 2
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

OUTPUT=$(cd "$PROJ_DIR" && npx tsc --noEmit 2>&1) || true
ERRORS=$(echo "$OUTPUT" | grep "error TS" | head -10)

if [ -n "$ERRORS" ]; then
    # Use jq for safe JSON construction (handles special chars in error messages)
    jq -n --arg msg "[TypeCheck] Errors found: $ERRORS" '{"hookSpecificOutput":{"message":$msg}}'
fi

exit 0
