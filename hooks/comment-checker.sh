#!/usr/bin/env bash
# Comment Checker Hook — Detects AI slop comments in edited files
# Runs as PostToolUse hook on Write|Edit events
# Exit 0 = pass, Exit 2 = block with error message

set -u

INPUT=$(cat)

# Require jq for JSON parsing
if ! command -v jq &>/dev/null; then
    echo '{"hookSpecificOutput":{"message":"[ALLOY] jq is required. Install: brew install jq (macOS) or apt install jq (Linux)"}}'
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Reject path traversal
case "$FILE_PATH" in
    *../*|*/..*|*..)
        echo "Path traversal detected in '$FILE_PATH'. Skipping." >&2
        exit 2
        ;;
esac

# Get file extension
EXT="${FILE_PATH##*.}"

# Only check code files
case "$EXT" in
    ts|tsx|js|jsx|py|go|rs|java|c|cpp|h|hpp|rb|swift|kt|scala|cs)
        ;;
    *)
        exit 0
        ;;
esac

# AI slop comment patterns to detect
SLOP_PATTERNS=(
    "# This function"
    "// This function"
    "# This method"
    "// This method"
    "# This class"
    "// This class"
    "# Initialize the"
    "// Initialize the"
    "# Import necessary"
    "// Import necessary"
    "# Define the"
    "// Define the"
    "# Create a new"
    "// Create a new"
    "# Set up the"
    "// Set up the"
    "# TODO: Implement"
    "// TODO: Implement"
    "# Add error handling"
    "// Add error handling"
    "# Helper function"
    "// Helper function"
    "# Utility function"
    "// Utility function"
)

FOUND_SLOP=0
SLOP_LINES=""

for pattern in "${SLOP_PATTERNS[@]}"; do
    # Anchor to line start (after optional whitespace) to reduce false positives
    MATCHES=$(grep -nF "${pattern}" "$FILE_PATH" 2>/dev/null || true)
    if [ -n "$MATCHES" ]; then
        FOUND_SLOP=1
        SLOP_LINES="$SLOP_LINES\n$MATCHES"
    fi
done

if [ "$FOUND_SLOP" -eq 1 ]; then
    # Output warning as JSON (non-blocking — exit 0 with message)
    jq -n --arg msg "AI slop comments detected in $FILE_PATH. Remove obvious/redundant comments that just restate the code. Code should be self-documenting." \
        '{"hookSpecificOutput":{"message":$msg}}'
    exit 0
fi

exit 0
