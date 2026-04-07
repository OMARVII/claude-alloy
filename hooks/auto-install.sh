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
    */package.json)
        if command -v npm &>/dev/null && [ -f "$FILE_PATH" ]; then
            DIR=$(dirname "$FILE_PATH")
            if (cd "$DIR" && npm install --no-audit --no-fund --ignore-scripts >/dev/null 2>&1); then
                jq -n --arg msg "Dependencies installed from ${FILE_PATH} (lifecycle scripts skipped for safety — run 'npm rebuild' if needed)." '{"hookSpecificOutput":{"message":$msg}}'
            else
                jq -n --arg msg "[ALLOY] npm install failed for ${FILE_PATH}. Check package.json." '{"hookSpecificOutput":{"message":$msg}}'
            fi
        fi
        ;;
    */requirements.txt)
        if command -v pip &>/dev/null && [ -f "$FILE_PATH" ]; then
            DIR=$(dirname "$FILE_PATH")
            if (cd "$DIR" && pip install -q -r "$(basename "$FILE_PATH")" >/dev/null 2>&1); then
                jq -n --arg msg "Python dependencies installed from ${FILE_PATH}." '{"hookSpecificOutput":{"message":$msg}}'
            else
                jq -n --arg msg "[ALLOY] pip install failed for ${FILE_PATH}." '{"hookSpecificOutput":{"message":$msg}}'
            fi
        fi
        ;;
    */pyproject.toml)
        if command -v pip &>/dev/null && [ -f "$FILE_PATH" ]; then
            DIR=$(dirname "$FILE_PATH")
            if (cd "$DIR" && pip install -q -e . >/dev/null 2>&1); then
                jq -n --arg msg "Python package installed from ${FILE_PATH}." '{"hookSpecificOutput":{"message":$msg}}'
            else
                jq -n --arg msg "[ALLOY] pip install failed for ${FILE_PATH}." '{"hookSpecificOutput":{"message":$msg}}'
            fi
        fi
        ;;
esac

exit 0
