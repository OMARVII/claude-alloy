#!/usr/bin/env bash
# Context Pressure Monitor — Estimates context usage and warns at high thresholds
# Runs as PostToolUse hook
# Exit 0 = always non-blocking (advisory only)

set -u

# v1.6.11 hardening: skip on low-effort turns. Context-pressure is advisory
# (warns at ~70%/85% tool-call estimates) and adds a syscall on every
# PostToolUse — wasted on haiku micro-tasks. Drain stdin before exit so
# Claude Code's pipe-write doesn't block waiting for a reader.
if [ "${CLAUDE_EFFORT:-medium}" = "low" ]; then cat > /dev/null; exit 0; fi

# shellcheck disable=SC2034
INPUT=$(cat)

command -v jq &>/dev/null || exit 0

# shellcheck source=hooks/_state-dir.sh
. "$(dirname "$0")/_state-dir.sh"
STATE_DIR="${HOME}/.claude/.alloy-state"
alloy_ensure_state_dir "$STATE_DIR" || exit 0

# BUG-2 fix: derive SESSION_ID from stdin .session_id so the counter file
# path matches what hooks/statusline.sh reads. The previous env-var source
# ($CLAUDE_SESSION_ID) diverged from stdin in some builds, causing the
# statusline to look at a counter this hook never wrote.
# Reuse the $INPUT captured above — no extra stdin read.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
# Sanitize session_id against path traversal (CWE-22): reject anything that
# isn't a plain identifier before using it in a filesystem path.
[[ "$SESSION_ID" =~ ^[A-Za-z0-9_-]+$ ]] || SESSION_ID="unknown"
COUNTER_FILE="${STATE_DIR}/tool-count-${SESSION_ID}"

# Increment tool call counter
COUNT=0
if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null) || COUNT=0
fi
COUNT=$((COUNT + 1))
# Atomic write: avoid half-written counter if the hook is killed mid-write.
echo "$COUNT" > "${COUNTER_FILE}.tmp" && mv "${COUNTER_FILE}.tmp" "$COUNTER_FILE"

# Stale tool-count files are reaped by hooks/session-end.sh (centralized
# janitor, per the v1.6.1 commitment). Do not scan the state dir from this
# hot-path hook.

# Thresholds based on empirical context window behavior:
# ~100 tool calls ≈ 70% context (precision starts dropping)
# ~140 tool calls ≈ 85% context (hallucinations increase)
# These are conservative estimates; actual usage depends on output size

# Claude Code requires `hookEventName` inside `hookSpecificOutput` for the
# additionalContext channel. Without it, the hook fails JSON validation
# silently in the harness and the warning is dropped.
if [ "$COUNT" -ge 140 ]; then
    jq -n --arg msg "[CONTEXT PRESSURE: CRITICAL] ~${COUNT} tool calls this session. Context window likely >85% full. Performance is degrading. Strongly recommend: /clear and restart, or compact now. Do NOT start new complex tasks." \
        '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $msg}}'
elif [ "$COUNT" -ge 100 ]; then
    jq -n --arg msg "[CONTEXT PRESSURE: HIGH] ~${COUNT} tool calls this session. Context window estimated >70% full. Consider wrapping up current task and using /clear before starting new work." \
        '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $msg}}'
fi

exit 0
