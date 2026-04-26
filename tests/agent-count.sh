#!/usr/bin/env bash
# Tests for hooks/agent-count.sh — parent-session-keyed agent counter.
#
# Regression target: pre-fix, the IGNITE stop-gate's "N/6 agents spawned"
# check relied on hooks/subagent-start.sh, which fires on Claude Code's
# SubagentStart event — empirically NOT fired in some long-running parent
# sessions. agent-count.sh runs as PostToolUse on Agent|Task tool calls
# instead, which fires reliably for every parent-session tool call.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/agent-count.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — agent-count exits early without it\n'
    exit 0
fi

# Sandbox HOME so STATE_DIR=${HOME}/.claude/.alloy-state lands in /tmp.
TMP_HOME=$(mktemp -d /tmp/alloy-agentcount-test.XXXXXX)
export HOME="$TMP_HOME"
STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

cleanup() {
    rm -rf "$TMP_HOME" 2>/dev/null
    return 0
}
trap cleanup EXIT

call_hook() {
    # $1 = tool_name, $2 = subagent_type, $3 = session_id
    _tool=$1
    _agent=$2
    _sid=$3
    jq -nc --arg t "$_tool" --arg a "$_agent" --arg s "$_sid" \
        '{tool_name: $t, tool_input: {subagent_type: $a}, session_id: $s}' \
        | bash "$HOOK" 2>/dev/null
}

# ---- Counter increments on first Agent dispatch -----------------------------
SID="agent-count-test-$$"
COUNT_FILE="${STATE_DIR}/agent-count-${SID}"
AGENTS_FILE="${STATE_DIR}/agents-spawned-${SID}"

call_hook "Agent" "mercury" "$SID" >/dev/null
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo "missing")
assert_eq "1" "$COUNT" "first Agent dispatch increments counter to 1"
[ -f "$AGENTS_FILE" ] && AGENTS_OK="yes" || AGENTS_OK="no"
assert_eq "yes" "$AGENTS_OK" "first Agent dispatch creates agents-spawned ledger"
LAST=$(tail -1 "$AGENTS_FILE" 2>/dev/null)
assert_eq "mercury" "$LAST" "ledger records the subagent_type"

# ---- Multiple dispatches accumulate -----------------------------------------
call_hook "Agent" "graphene" "$SID" >/dev/null
call_hook "Agent" "tungsten" "$SID" >/dev/null
call_hook "Task" "sentinel" "$SID" >/dev/null
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo "missing")
assert_eq "4" "$COUNT" "four dispatches accumulate to count=4"
LEDGER_LINES=$(wc -l < "$AGENTS_FILE" | tr -d ' ')
assert_eq "4" "$LEDGER_LINES" "ledger has 4 entries"
grep -q "^graphene$" "$AGENTS_FILE" && GRAPH_OK="yes" || GRAPH_OK="no"
assert_eq "yes" "$GRAPH_OK" "graphene appears in ledger"

# ---- Non-Agent/Task tools do NOT increment ----------------------------------
SID_BG="non-agent-test-$$"
BG_COUNT_FILE="${STATE_DIR}/agent-count-${SID_BG}"
call_hook "Bash" "" "$SID_BG" >/dev/null
[ -f "$BG_COUNT_FILE" ] && EXISTS="yes" || EXISTS="no"
assert_eq "no" "$EXISTS" "Bash tool does NOT increment counter (matcher safety)"

call_hook "Grep" "" "$SID_BG" >/dev/null
[ -f "$BG_COUNT_FILE" ] && EXISTS="yes" || EXISTS="no"
assert_eq "no" "$EXISTS" "Grep tool does NOT increment counter"

# ---- Empty subagent_type writes "unknown" -----------------------------------
SID_EMPTY="empty-type-test-$$"
EMPTY_AGENTS="${STATE_DIR}/agents-spawned-${SID_EMPTY}"
jq -nc --arg s "$SID_EMPTY" '{tool_name: "Agent", tool_input: {}, session_id: $s}' \
    | bash "$HOOK" 2>/dev/null
LAST=$(tail -1 "$EMPTY_AGENTS" 2>/dev/null)
assert_eq "unknown" "$LAST" "missing subagent_type → ledger writes 'unknown'"

# ---- Path traversal: malicious session_id is sanitized ----------------------
EVIL="../evil"
jq -nc --arg s "$EVIL" \
    '{tool_name: "Agent", tool_input: {subagent_type: "x"}, session_id: $s}' \
    | bash "$HOOK" 2>/dev/null

# After sanitization, file should land at agent-count-evil (not -../evil).
SAN_FILE="${STATE_DIR}/agent-count-evil"
[ -f "$SAN_FILE" ] && SAN_OK="yes" || SAN_OK="no"
assert_eq "yes" "$SAN_OK" "traversal: malicious '../evil' session_id sanitized to 'evil'"

ESCAPED=$(find "${HOME}/.claude" -maxdepth 3 -name '*evil*' -not -path "${STATE_DIR}/*" 2>/dev/null | wc -l | tr -d ' ')
assert_eq 0 "$ESCAPED" "traversal: no 'evil'-named files outside STATE_DIR"

# ---- Counter survives corrupted content -------------------------------------
SID_CORRUPT="corrupt-test-$$"
CORRUPT_FILE="${STATE_DIR}/agent-count-${SID_CORRUPT}"
echo "not a number" > "$CORRUPT_FILE"
call_hook "Agent" "x" "$SID_CORRUPT" >/dev/null
COUNT=$(cat "$CORRUPT_FILE" 2>/dev/null || echo "missing")
assert_eq "1" "$COUNT" "corrupted counter resets to 1 on increment (no abort)"

done_testing
