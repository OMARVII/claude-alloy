#!/usr/bin/env bash
# Comment Checker Hook — Detects AI slop comments in edited files
# Runs as PostToolUse hook on Write|Edit events
# Exit 0 = pass, Exit 2 = block with error message

set -u

INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Reject path traversal — skip analysis (PostToolUse cannot block)
case "$FILE_PATH" in
    *../*|*/..*|*..)
        exit 0
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

# AI slop comment patterns to detect (newline-separated for POSIX compatibility)
SLOP_PATTERNS="# This function
// This function
# This method
// This method
# This class
// This class
# Initialize the
// Initialize the
# Import necessary
// Import necessary
# Define the
// Define the
# Create a new
// Create a new
# Set up the
// Set up the
# TODO: Implement
// TODO: Implement
# Add error handling
// Add error handling
# Helper function
// Helper function
# Utility function
// Utility function"

HAS_SLOP=false
while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    if grep -qF "$pattern" "$FILE_PATH" 2>/dev/null; then
        HAS_SLOP=true
        break
    fi
done <<EOF
$SLOP_PATTERNS
EOF

if [ "$HAS_SLOP" = true ]; then
    # Output warning as JSON (non-blocking — exit 0 with message)
    jq -n --arg msg "AI slop comments detected in $FILE_PATH. Remove obvious/redundant comments that just restate the code. Code should be self-documenting." \
        '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
    exit 0
fi

exit 0
