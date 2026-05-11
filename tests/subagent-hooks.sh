#!/usr/bin/env bash
# Tests for hooks/subagent-start.sh and hooks/subagent-stop.sh — both read
# the platform's SubagentStart/SubagentStop input schema (agent_id +
# agent_type) directly. These tests pin that contract so a schema-shape
# regression surfaces as a test failure rather than a silent miss in the
# IGNITE counter or the tungsten-active marker.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

START_HOOK="${REPO_ROOT}/hooks/subagent-start.sh"
STOP_HOOK="${REPO_ROOT}/hooks/subagent-stop.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — subagent hooks require jq for input parse\n'
    exit 0
fi

# Override HOME so the hooks write to a sandboxed STATE_DIR. The hooks read
# ${HOME}/.claude/.alloy-state; pointing HOME at a temp dir keeps the test
# from polluting (or depending on) the real state dir.
TMP_HOME=$(mktemp -d /tmp/alloy-subagent-hooks.XXXXXX)
export HOME="$TMP_HOME"
STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

cleanup() {
    rm -rf "$TMP_HOME" 2>/dev/null
    return 0
}
trap cleanup EXIT

# ---- SubagentStart: documented schema (agent_type at top level) ------------
SESSION_ID="sastart-doc"
INPUT=$(jq -nc \
    --arg sid "$SESSION_ID" \
    --arg atype "mercury" \
    '{session_id: $sid, agent_type: $atype, hook_event_name: "SubagentStart"}')
EXIT_CODE=$(echo "$INPUT" | bash "$START_HOOK" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$EXIT_CODE" "subagent-start: documented schema exits 0"

# subagent-start.sh appends to the global agent-log.jsonl but no longer writes
# to the per-session counter (agent-count.sh owns that). Verify the global log
# captured the schema event.
LOG_LAST=$(tail -1 "${STATE_DIR}/agent-log.jsonl" 2>/dev/null | jq -r '.agent.agent_type // empty' 2>/dev/null)
assert_eq "mercury" "$LOG_LAST" "subagent-start: agent_type written to global log"

# ---- SubagentStart: legacy schema fallback (subagent_type) -----------------
# Older payloads wrap the agent under .subagent_type. The hook's fallback
# chain must still surface it so the global log stays honest across upgrades.
SESSION_ID="sastart-legacy"
INPUT=$(jq -nc \
    --arg sid "$SESSION_ID" \
    --arg atype "graphene" \
    '{session_id: $sid, subagent_type: $atype}')
echo "$INPUT" | bash "$START_HOOK" >/dev/null 2>&1
LOG_LAST=$(tail -1 "${STATE_DIR}/agent-log.jsonl" 2>/dev/null | jq -r '.agent.subagent_type // empty' 2>/dev/null)
assert_eq "graphene" "$LOG_LAST" "subagent-start: legacy subagent_type fallback captured"

# ---- SubagentStop: documented schema reads agent_type ----------------------
# subagent-stop.sh must consume agent_type from the documented top-level
# field, then clear the tungsten-active marker when agent_type==tungsten.
SESSION_ID="sastop-tungsten"
: > "${STATE_DIR}/tungsten-active-${SESSION_ID}"
INPUT=$(jq -nc \
    --arg sid "$SESSION_ID" \
    --arg aid "agent-abc123" \
    --arg atype "tungsten" \
    --arg msg "Done with the task. Implementation complete with tests passing for all four cases described in the brief, and shellcheck clean across every modified file." \
    '{session_id: $sid, agent_id: $aid, agent_type: $atype, last_assistant_message: $msg, hook_event_name: "SubagentStop"}')
EXIT_CODE=$(echo "$INPUT" | bash "$STOP_HOOK" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$EXIT_CODE" "subagent-stop: tungsten payload exits 0"

if [ -f "${STATE_DIR}/tungsten-active-${SESSION_ID}" ]; then
    _marker_present=1
else
    _marker_present=0
fi
assert_eq 0 "$_marker_present" "subagent-stop: tungsten marker removed when agent_type=tungsten"

# ---- SubagentStop: non-tungsten agent leaves marker untouched --------------
# A mercury or graphene stop must NOT clear a sibling session's tungsten
# marker — the marker is keyed to one session at a time but multiple agent
# types can stop within it; only the matching type clears.
SESSION_ID="sastop-other"
: > "${STATE_DIR}/tungsten-active-${SESSION_ID}"
INPUT=$(jq -nc \
    --arg sid "$SESSION_ID" \
    --arg aid "agent-xyz789" \
    --arg atype "mercury" \
    --arg msg "Search complete. Found 3 relevant files matching the requested pattern across the codebase, and surfaced the most likely callers above for further inspection." \
    '{session_id: $sid, agent_id: $aid, agent_type: $atype, last_assistant_message: $msg}')
echo "$INPUT" | bash "$STOP_HOOK" >/dev/null 2>&1
if [ -f "${STATE_DIR}/tungsten-active-${SESSION_ID}" ]; then
    _marker_present=1
else
    _marker_present=0
fi
assert_eq 1 "$_marker_present" "subagent-stop: tungsten marker preserved when agent_type=mercury"

# ---- SubagentStop: session_id sanitization (CWE-22 guard) ------------------
# The hook strips path-traversal bytes from session_id before using it in a
# filesystem path. A payload like "../evil" must not delete a marker outside
# the state dir.
EVIL_MARKER="${TMP_HOME}/evil-marker"
: > "$EVIL_MARKER"
INPUT=$(jq -nc \
    --arg sid "../evil" \
    --arg aid "agent-evil" \
    --arg atype "tungsten" \
    '{session_id: $sid, agent_id: $aid, agent_type: $atype}')
echo "$INPUT" | bash "$STOP_HOOK" >/dev/null 2>&1
if [ -f "$EVIL_MARKER" ]; then
    _evil_present=1
else
    _evil_present=0
fi
assert_eq 1 "$_evil_present" "subagent-stop: traversal session_id cannot delete marker outside state dir"

done_testing
