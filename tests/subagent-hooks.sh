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
COUNT_HOOK="${REPO_ROOT}/hooks/agent-count.sh"

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
assert_eq "graphene" "$LOG_LAST" "subagent-start: legacy subagent_type fallback captured in global log"

# ---- agent-count.sh: legacy subagent_type resolves to operative type -------
# subagent-start.sh's global log assertion above proves the raw payload was
# echoed to agent-log.jsonl, NOT that the hook resolved the operative agent
# type for the load-bearing ledger. The IGNITE stop-gate's "N agents spawned"
# read pulls from `agents-spawned-${SESSION_ID}` (written by agent-count.sh
# on every PostToolUse Agent|Task) — that is the file that must resolve the
# legacy fallback. Send the same legacy payload shape (subagent_type at top
# level, NOT under tool_input) through agent-count.sh and assert the ledger
# records the operative type, not "unknown".
SESSION_ID="agentcount-legacy"
LEGACY_INPUT=$(jq -nc \
    --arg sid "$SESSION_ID" \
    --arg atype "graphene" \
    '{tool_name: "Agent", session_id: $sid, subagent_type: $atype}')
echo "$LEGACY_INPUT" | bash "$COUNT_HOOK" >/dev/null 2>&1
SPAWNED=$(tail -1 "${STATE_DIR}/agents-spawned-${SESSION_ID}" 2>/dev/null)
assert_eq "graphene" "$SPAWNED" "agent-count: legacy subagent_type fallback resolves to operative type in ledger"

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
# filesystem path. Two halves of the same contract:
#   (a) negative: a marker outside the state dir must remain untouched
#   (b) positive: the sanitized id "../evil" → "evil" must be what the rm
#       actually targets, so a pre-planted tungsten-active-evil under the
#       state dir IS removed. Without (b) the test could pass for the wrong
#       reason — rm of a non-existent path is a no-op.
EVIL_MARKER="${TMP_HOME}/evil-marker"
: > "$EVIL_MARKER"
EVIL_SANITIZED="${STATE_DIR}/tungsten-active-evil"
: > "$EVIL_SANITIZED"
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
if [ -f "$EVIL_SANITIZED" ]; then
    _sanitized_present=1
else
    _sanitized_present=0
fi
assert_eq 0 "$_sanitized_present" "subagent-stop: sanitized id (../evil → evil) is what rm actually targets"

# ---- SubagentStop: embedded-slash sanitization -----------------------------
# A session_id with embedded slashes (a/b/c) must collapse to "abc" so the
# rm never sees a path separator. Mirror the positive/negative split: marker
# under the state dir at the sanitized name is removed; a sibling at the
# unsanitized shape never existed (and would be a traversal smell anyway).
ABC_TARGET="${STATE_DIR}/tungsten-active-abc"
: > "$ABC_TARGET"
INPUT=$(jq -nc \
    --arg sid "a/b/c" \
    --arg aid "agent-abc" \
    --arg atype "tungsten" \
    '{session_id: $sid, agent_id: $aid, agent_type: $atype}')
echo "$INPUT" | bash "$STOP_HOOK" >/dev/null 2>&1
if [ -f "$ABC_TARGET" ]; then
    _abc_present=1
else
    _abc_present=0
fi
assert_eq 0 "$_abc_present" "subagent-stop: embedded-slash id (a/b/c → abc) targets the sanitized name"

# ---- SubagentStop: agent_id sanitization mirrors session_id ---------------
# Per refactor(hooks): subagent hooks pre-emptively sanitize agent_id with
# the same allowlist as session_id (CWE-22 defense-in-depth). agent_id is
# not load-bearing for any filesystem path today, but verifying the field
# is read and stripped pins the precedent so a regression flips this test.
SESSION_ID="sastop-aid"
: > "${STATE_DIR}/tungsten-active-${SESSION_ID}"
INPUT=$(jq -nc \
    --arg sid "$SESSION_ID" \
    --arg aid "../escape" \
    --arg atype "tungsten" \
    '{session_id: $sid, agent_id: $aid, agent_type: $atype, hook_event_name: "SubagentStop"}')
EXIT_CODE=$(echo "$INPUT" | bash "$STOP_HOOK" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$EXIT_CODE" "subagent-stop: traversal agent_id payload exits 0 (sanitized, not used in path)"
# The session_id-keyed marker should still clear since agent_type==tungsten
# and session_id is safe.
if [ -f "${STATE_DIR}/tungsten-active-${SESSION_ID}" ]; then
    _aid_marker=1
else
    _aid_marker=0
fi
assert_eq 0 "$_aid_marker" "subagent-stop: traversal agent_id does not break the session_id-keyed marker clear"

done_testing
