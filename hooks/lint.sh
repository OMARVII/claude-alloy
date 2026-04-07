#!/usr/bin/env bash
set -u

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

# Only lint file types that linters typically handle
case "$FILE_PATH" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.html|*.vue|*.svelte)
        ;;
    *)
        exit 0
        ;;
esac

# Walk up to find the project root
PROJ_DIR="$FILE_PATH"
while [ "$PROJ_DIR" != "/" ]; do
    PROJ_DIR=$(dirname "$PROJ_DIR")
    [ -f "$PROJ_DIR/package.json" ] && break
done

if [ ! -f "$PROJ_DIR/package.json" ]; then
    exit 0
fi

ERRORS=""

# Detect and run Biome
if [ -f "$PROJ_DIR/biome.json" ] || [ -f "$PROJ_DIR/biome.jsonc" ]; then
    OUTPUT=$(cd "$PROJ_DIR" && npx @biomejs/biome check "$FILE_PATH" 2>&1) || true
    ERRORS=$(echo "$OUTPUT" | grep -E "^.+:[0-9]+:[0-9]+" | head -10)

# Detect and run ESLint
elif [ -f "$PROJ_DIR/.eslintrc" ] || [ -f "$PROJ_DIR/.eslintrc.js" ] || [ -f "$PROJ_DIR/.eslintrc.cjs" ] || [ -f "$PROJ_DIR/.eslintrc.json" ] || [ -f "$PROJ_DIR/.eslintrc.yml" ] || [ -f "$PROJ_DIR/eslint.config.js" ] || [ -f "$PROJ_DIR/eslint.config.mjs" ] || [ -f "$PROJ_DIR/eslint.config.cjs" ]; then
    OUTPUT=$(cd "$PROJ_DIR" && npx eslint --no-warn-ignored "$FILE_PATH" 2>&1) || true
    ERRORS=$(echo "$OUTPUT" | grep -E "^.+:[0-9]+:[0-9]+" | head -10)

# Detect and run Prettier (check mode only)
elif [ -f "$PROJ_DIR/.prettierrc" ] || [ -f "$PROJ_DIR/.prettierrc.js" ] || [ -f "$PROJ_DIR/.prettierrc.json" ] || [ -f "$PROJ_DIR/.prettierrc.yml" ] || [ -f "$PROJ_DIR/.prettierrc.cjs" ] || [ -f "$PROJ_DIR/prettier.config.js" ] || [ -f "$PROJ_DIR/prettier.config.cjs" ]; then
    OUTPUT=$(cd "$PROJ_DIR" && npx prettier --check "$FILE_PATH" 2>&1) || true
    if echo "$OUTPUT" | grep -q "Code style issues"; then
        ERRORS="Formatting issues detected in $FILE_PATH"
    fi
fi

if [ -n "$ERRORS" ]; then
    jq -n --arg msg "[Lint] Issues found: $ERRORS" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
fi

exit 0
