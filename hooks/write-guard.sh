#!/usr/bin/env bash
set -u

INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Reject path traversal (fail closed — block the write)
case "$FILE_PATH" in
    *../*|*/..*|*..)
        echo "Path traversal detected in '$FILE_PATH'. Blocked." >&2
        exit 2
        ;;
esac

# Allow writes to files matching known-safe patterns (generated, lock files, configs)
case "$FILE_PATH" in
    *.lock|*.lock.json|*-lock.yaml|*/dist/*|*/build/*|*/.next/*|*/node_modules/*|*.generated.*|*.gen.*)
        exit 0
        ;;
esac

if [ -f "$FILE_PATH" ]; then
    FILE_SIZE=$(wc -c < "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 0 ]; then
        echo "File '$FILE_PATH' already exists (${FILE_SIZE} bytes). Use the Edit tool instead of Write to modify existing files. Write overwrites the entire file and risks data loss. Only use Write for NEW files or generated files." >&2
        exit 2
    fi
fi

exit 0
