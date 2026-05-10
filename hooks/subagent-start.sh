#!/usr/bin/env bash
# Subagent Start Hook — Logs agent spawn events and tracks per-session state.
# Runs as SubagentStart hook (per code.claude.com/docs/en/hooks).
#
# Schema (current Claude Code):
#   session_id, transcript_path, cwd, hook_event_name, agent_type
#
# Older/alternate payloads sometimes wrap the agent identifier differently
# (`subagent_type`, or `tool_input.subagent_type` for Agent-tool dispatches).
# We read `.agent_type` first, then fall back to those forms so the counter
# never silently fails when Anthropic ships a schema variant.
#
# Exit 0 = always allow (SubagentStart has no decision control upstream).

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

# shellcheck source=./_state-dir.sh
. "$(dirname "$0")/_state-dir.sh"
STATE_DIR="${HOME}/.claude/.alloy-state"
alloy_ensure_state_dir "$STATE_DIR" || exit 0
# Stale-file cleanup is centralized in hooks/session-end.sh.

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Extract session_id and agent_type from input. Try the documented field
# first, then known fallbacks (subagent_type at top level, then nested under
# tool_input/tool_use for Agent-tool-style payloads).
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
AGENT_TYPE=$(echo "$INPUT" | jq -r '
    .agent_type
    // .subagent_type
    // .tool_input.subagent_type
    // .tool_use.input.subagent_type
    // empty
' 2>/dev/null || echo "")

# Optional debug trace — gated to keep production output silent. Surfaces
# the raw input + extracted fields so users can confirm the hook fired
# against the right schema. Tail with:
#   tail -f ~/.claude/.alloy-state/subagent-debug.log
if [ "${ALLOY_DEBUG:-0}" = "1" ]; then
    {
        printf '[%s] SubagentStart fired session=%s agent=%s\n' \
            "$TIMESTAMP" "${SESSION_ID:-<empty>}" "${AGENT_TYPE:-<empty>}"
        printf '  raw input: %s\n' "$INPUT"
    } >> "${STATE_DIR}/subagent-debug.log" 2>/dev/null || true
    printf '[alloy] SubagentStart session=%s agent=%s\n' \
        "${SESSION_ID:-?}" "${AGENT_TYPE:-?}" >&2
fi

# Append to global agent log (existing behavior)
LOG_FILE="${STATE_DIR}/agent-log.jsonl"
jq -nc --arg ts "$TIMESTAMP" --arg ev "start" --argjson input "$INPUT" \
    '{timestamp: $ts, event: $ev, agent: $input}' >> "$LOG_FILE" 2>/dev/null || \
jq -nc --arg ts "$TIMESTAMP" --arg ev "start" \
    '{timestamp: $ts, event: $ev, agent: {}}' >> "$LOG_FILE" 2>/dev/null

# Per-session agent counter and ledger are now owned by hooks/agent-count.sh
# (PostToolUse on Agent|Task in the parent session). This hook used to also
# write to those files, but that caused double-counting when SubagentStart
# DID fire in the parent session — both hooks would increment the same
# parent-session counter for one logical agent dispatch. The IGNITE stop-gate
# now reads from agent-count.sh's writes only. This hook retains its global
# agent-log.jsonl append (above) for debugging/audit, but no longer touches
# the load-bearing counter/ledger files.

exit 0
