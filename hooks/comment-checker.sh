#!/usr/bin/env bash
# Comment Checker Hook — Detects AI slop comments in edited files
# Runs as PostToolUse hook on Write|Edit events
# Exit 0 = pass, Exit 2 = block with error message
#
# Default behavior on slop detection: emit a warning via
# `hookSpecificOutput.additionalContext` (non-blocking, exit 0). Claude
# sees the warning in the next turn and can choose to clean up.
#
# Opt-in recoverable blocking (env var ALLOY_BLOCK_AI_SLOP=1, default unset):
# emit `{"decision":"block", "hookSpecificOutput.continueOnBlock":true,
# additionalContext}`. Per https://code.claude.com/docs/en/hooks (v2.1.139),
# `continueOnBlock:true` on a PostToolUse block decision feeds the rejection
# reason back to Claude as context — Claude sees the block AND the specific
# slop comments and rewrites in the SAME turn instead of in a follow-up. The
# write is not reverted; the rewrite simply gets immediate priority.
#
# Default is opt-OUT because forcible blocking can derail unrelated work
# (e.g. fixing an urgent bug in a file that happens to contain pre-existing
# slop comments). Teams that want stricter discipline set the env var in
# their .claude/settings.json env block.

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
    MSG="AI slop comments detected in $FILE_PATH. Remove obvious/redundant comments that just restate the code. Code should be self-documenting."
    if [ "${ALLOY_BLOCK_AI_SLOP:-0}" = "1" ]; then
        # Recoverable block: Claude sees the rejection AND the additionalContext
        # in the same turn (continueOnBlock:true). Strict mode — opt-in only.
        jq -n --arg msg "$MSG" \
            '{"decision":"block","reason":$msg,"hookSpecificOutput":{"hookEventName":"PostToolUse","continueOnBlock":true,"additionalContext":$msg}}'
    else
        # Default: warn-only via additionalContext, exit 0.
        jq -n --arg msg "$MSG" \
            '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
    fi
    exit 0
fi

exit 0
