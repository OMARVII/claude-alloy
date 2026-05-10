#!/usr/bin/env bash
# Agent Count Tracker — increments per-session agent-spawn counter on every
# `Agent`/`Task` tool call in the PARENT session.
#
# Why this hook exists in addition to subagent-start.sh:
#   subagent-start.sh fires on Claude Code's SubagentStart event, which is
#   keyed to the SUBAGENT's session lifecycle and does not fire reliably in
#   every parent session (observed empirically: zero SubagentStart events
#   for some long-running parent sessions despite many agent dispatches).
#   PostToolUse on the Agent tool, by contrast, fires reliably for every
#   tool call in the parent session — so counting here gives the IGNITE
#   stop-gate a stable, parent-session-keyed agent count.
#
# Runs as PostToolUse with matcher "Agent|Task". Exit 0 always — advisory.

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')

# Only count Agent/Task dispatches; the matcher should already restrict this
# but defense-in-depth in case the hook is invoked for a wider matcher.
TOOL_LOWER=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')
case "$TOOL_LOWER" in
    agent|task) ;;
    *) exit 0 ;;
esac

# Extract the subagent_type the parent asked for. Multiple fallbacks because
# the field path varies across Claude Code versions and tool variants. The
# tool_use.input nesting handles Agent-tool dispatches that wrap the input
# under a tool_use envelope (matches the pattern subagent-start.sh handles).
AGENT_TYPE=$(echo "$INPUT" | jq -r '
    .tool_input.subagent_type
    // .tool_input.agent_type
    // .tool_input.type
    // .tool_use.input.subagent_type
    // .subagent_type
    // empty
' 2>/dev/null || echo "")

# shellcheck source=./_state-dir.sh
. "$(dirname "$0")/_state-dir.sh"
STATE_DIR="${HOME}/.claude/.alloy-state"
alloy_ensure_state_dir "$STATE_DIR" || exit 0

# Append-only ledger is the canonical source of truth for both the count
# AND the per-agent record. POSIX guarantees that single-buffer writes
# below PIPE_BUF (≥512 bytes; effectively always for one agent name + \n)
# are atomic, so concurrent appends interleave at line boundaries without
# corrupting each other or losing increments. Deriving count via wc -l
# on read avoids the read-modify-write race on a separate counter file.
#
# Defaults to "unknown" so the ledger always has a row per spawn — keeps
# grep-based audits and the IGNITE stop-gate's count honest even when
# the upstream schema doesn't surface the agent name.
AGENTS_FILE="${STATE_DIR}/agents-spawned-${SESSION_ID}"
if [ -n "$AGENT_TYPE" ]; then
    echo "$AGENT_TYPE" >> "$AGENTS_FILE"
else
    echo "unknown" >> "$AGENTS_FILE"
fi

# Mirror the count to agent-count-${SESSION_ID} so the IGNITE stop-gate's
# existing read path keeps working without changes. Re-derived from the
# ledger via wc -l (single-shot read of an append-only file is atomic
# enough for this purpose; no read-modify-write).
COUNT_FILE="${STATE_DIR}/agent-count-${SESSION_ID}"
COUNT=$(wc -l < "$AGENTS_FILE" 2>/dev/null | tr -d ' ')
case "$COUNT" in
    ''|*[!0-9]*) COUNT=0 ;;
esac
echo "$COUNT" > "$COUNT_FILE"

if [ "${ALLOY_DEBUG:-0}" = "1" ]; then
    printf '[alloy] agent-count fired session=%s tool=%s type=%s count=%s\n' \
        "$SESSION_ID" "$TOOL_NAME" "${AGENT_TYPE:-unknown}" "$COUNT" >&2
fi

exit 0
