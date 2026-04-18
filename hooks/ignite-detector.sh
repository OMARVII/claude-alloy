#!/usr/bin/env bash
# IGNITE Detector — Detects "ig"/"ignite" in user prompt and sets flag
# Runs as UserPromptSubmit hook
# Exit 0 = always allow

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
# Stale-file cleanup is centralized in hooks/session-end.sh.

# Extract session_id
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')

# Extract user prompt text (try common field names)
PROMPT_TEXT=$(echo "$INPUT" | jq -r '.prompt // .user_message // .message // empty' 2>/dev/null || echo "")

# Fallback: check transcript for last user message
if [ -z "$PROMPT_TEXT" ]; then
    TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
    if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
        PROMPT_TEXT=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null || echo "")
    fi
fi

if [ -z "$PROMPT_TEXT" ]; then
    exit 0
fi

# Scan for word-bounded "ig" or "ignite" (case-insensitive)
IGNITE_DETECTED=false
if echo "$PROMPT_TEXT" | grep -qiE '\big\b|\bignite\b'; then
    IGNITE_DETECTED=true
fi

if [ "$IGNITE_DETECTED" = "false" ]; then
    exit 0
fi

# Set IGNITE flag with timestamp
IGNITE_FLAG="${STATE_DIR}/ignite-active-${SESSION_ID}"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$IGNITE_FLAG"

# Output context injection for the LLM
jq -nc --arg ctx '[IGNITE PROTOCOL] Maximum-effort mode detected. Requirements: (1) 6+ background agents including graphene, (2) tungsten for all implementation, (3) sentinel/iridium/flint after code changes, (4) detailed todos via TaskWrite, (5) manual QA before completion.' \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'

exit 0
