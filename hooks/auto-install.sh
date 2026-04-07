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

case "$FILE_PATH" in
    */package.json)
        if command -v npm &>/dev/null && [ -f "$FILE_PATH" ]; then
            DIR=$(dirname "$FILE_PATH")
            if (cd "$DIR" && npm install --no-audit --no-fund --ignore-scripts >/dev/null 2>&1); then
                jq -n --arg msg "Dependencies installed from ${FILE_PATH} (lifecycle scripts skipped for safety — run 'npm rebuild' if needed)." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            else
                jq -n --arg msg "[ALLOY] npm install failed for ${FILE_PATH}. Check package.json." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            fi
        fi
        ;;
    */requirements.txt)
        if command -v pip &>/dev/null && [ -f "$FILE_PATH" ]; then
            DIR=$(dirname "$FILE_PATH")
            # Only auto-install if inside a virtual environment
            if [ -z "${VIRTUAL_ENV:-}" ] && [ ! -d "$DIR/.venv" ] && [ ! -d "$DIR/venv" ]; then
                jq -n --arg msg "Skipping pip install — no virtual environment detected. Activate a venv first or create one with: python -m venv .venv" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            elif (cd "$DIR" && pip install -q -r "$(basename "$FILE_PATH")" >/dev/null 2>&1); then
                jq -n --arg msg "Python dependencies installed from ${FILE_PATH}." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            else
                jq -n --arg msg "[ALLOY] pip install failed for ${FILE_PATH}." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            fi
        fi
        ;;
    */pyproject.toml)
        if command -v pip &>/dev/null && [ -f "$FILE_PATH" ]; then
            DIR=$(dirname "$FILE_PATH")
            # Only auto-install if inside a virtual environment
            if [ -z "${VIRTUAL_ENV:-}" ] && [ ! -d "$DIR/.venv" ] && [ ! -d "$DIR/venv" ]; then
                jq -n --arg msg "Skipping pip install — no virtual environment detected. Activate a venv first or create one with: python -m venv .venv" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            elif (cd "$DIR" && pip install -q -e . >/dev/null 2>&1); then
                jq -n --arg msg "Python package installed from ${FILE_PATH}." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            else
                jq -n --arg msg "[ALLOY] pip install failed for ${FILE_PATH}." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            fi
        fi
        ;;
esac

exit 0
