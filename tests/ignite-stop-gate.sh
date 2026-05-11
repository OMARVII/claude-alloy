#!/usr/bin/env bash
# Tests for hooks/ignite-stop-gate.sh — Edit/Write detection in transcript.
#
# Regression target: the previous gate ran `grep -qE 'Edit|Write'` against the
# last 500 transcript lines, which matches the bare words anywhere — including
# tool-schema mentions, agent-prompt prose, plan tables, and system reminders.
# Every research-only IGNITE turn would false-positive and demand
# sentinel/iridium/flint reviewers, wasting ~30K tokens per false positive.
#
# These tests pin the new behavior: detection must require a JSONL `tool_use`
# block with `"name":"Edit"` (or Write/MultiEdit/NotebookEdit) — not free text.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/ignite-stop-gate.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — gate exits 0 without it\n'
    exit 0
fi

# ---------------------------------------------------------------------------
# Test fixtures: simulate IGNITE-active session with 6 spawned agents
# (graphene + 5 mercuries). With the agent quota satisfied, the ONLY remaining
# violation lever is Check 3 (Edit/Write detection). That isolation lets us
# assert the regex change directly: false-positive transcript → exit 0,
# real tool_use transcript → exit 2.
# ---------------------------------------------------------------------------

ORIG_HOME=${HOME:-}
TEST_HOME=$(mktemp -d /tmp/alloy-ignite-stop-gate-home.XXXXXX)
export HOME="$TEST_HOME"

SESSION_ID="ignite-gate-test-$$"
STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"

# Mark IGNITE active for this session
printf '1\n' > "${STATE_DIR}/ignite-active-${SESSION_ID}"
# Satisfy Check 1: agent count >= 6
printf '6\n' > "${STATE_DIR}/agent-count-${SESSION_ID}"
# Satisfy Check 2: graphene was spawned (plus 5 mercuries to hit count)
{
    echo "graphene"
    echo "mercury"; echo "mercury"; echo "mercury"; echo "mercury"; echo "mercury"
} > "${STATE_DIR}/agents-spawned-${SESSION_ID}"

# Mirror the gate's BLOCK_KEY exactly: `echo "${SESSION_ID}-ignite" | cksum`.
# `echo` appends a newline, so the cksum input is "<session>-ignite\n" — using
# `printf` here without the newline would produce a different key and miss the
# block-file path entirely.
BLOCK_KEY=$(echo "${SESSION_ID}-ignite" | cksum | cut -d' ' -f1)
BLOCK_FILE="${STATE_DIR}/ignite-blocked-${BLOCK_KEY}"

cleanup() {
    if [ -n "$ORIG_HOME" ]; then
        export HOME="$ORIG_HOME"
    else
        unset HOME
    fi
    rm -rf "$TEST_HOME" 2>/dev/null
    [ -n "${TRANSCRIPT_FILE:-}" ] && rm -f "$TRANSCRIPT_FILE" 2>/dev/null
    [ -n "${NO_FLAG_TRANSCRIPT:-}" ] && rm -f "$NO_FLAG_TRANSCRIPT" 2>/dev/null
    return 0
}
trap cleanup EXIT

run_gate() {
    # $1 = transcript path. Emits exit code.
    _tx=$1
    printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":false}' \
        "$SESSION_ID" "$_tx" \
        | bash "$HOOK" >/dev/null 2>&1
    printf '%s' "$?"
}

TRANSCRIPT_FILE=$(mktemp /tmp/alloy-ignite-gate-test.XXXXXX)

# ---- corrupted count files fail closed -------------------------------------
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"no edit tool use"}]}}
JSONL

printf 'not-a-number\n' > "${STATE_DIR}/agent-count-${SESSION_ID}"
rm -f "$BLOCK_FILE" 2>/dev/null
assert_exit 2 "$(run_gate "$TRANSCRIPT_FILE")" \
    "corrupt agent-count file is treated as 0 and blocks"
printf '6\n' > "${STATE_DIR}/agent-count-${SESSION_ID}"

# ---- false-positive case: bare "Edit" / "Write" in prose ------------------
# This is exactly what the old grep matched: the words appear in conversational
# text, tool descriptions, and table headers — but NO actual tool_use block.
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"user","message":{"role":"user","content":"Should I use Edit or Write here?"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"You can Edit existing files or Write new ones. The Edit tool is preferred."}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/x"}}]}}
JSONL

rm -f "$BLOCK_FILE" 2>/dev/null
assert_exit 0 "$(run_gate "$TRANSCRIPT_FILE")" \
    "false-positive: 'Edit'/'Write' in prose alone does NOT trip Check 3"

# ---- true-positive case: actual tool_use Edit block -----------------------
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"user","message":{"role":"user","content":"Apply the fix"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"}}]}}
JSONL

rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null

# Real Edit happened, but reviewers (sentinel/iridium/flint) were not spawned —
# Check 3 should now FIRE and the gate should block (exit 2 on first attempt).
assert_exit 2 "$(run_gate "$TRANSCRIPT_FILE")" \
    "true-positive: tool_use name=Edit triggers Check 3 (block on missing reviewers)"

# ---- true-positive case: tool_use Write block -----------------------------
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/y","content":"hi"}}]}}
JSONL

rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null
assert_exit 2 "$(run_gate "$TRANSCRIPT_FILE")" \
    "true-positive: tool_use name=Write triggers Check 3"

# ---- true-positive case: tool_use MultiEdit block -------------------------
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"MultiEdit","input":{"file_path":"/tmp/z"}}]}}
JSONL

rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null
assert_exit 2 "$(run_gate "$TRANSCRIPT_FILE")" \
    "true-positive: tool_use name=MultiEdit triggers Check 3"

# ---- true-positive case: NotebookEdit block -------------------------------
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"NotebookEdit","input":{"file_path":"/tmp/notebook.ipynb"}}]}}
JSONL

rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null
assert_exit 2 "$(run_gate "$TRANSCRIPT_FILE")" \
    "true-positive: tool_use name=NotebookEdit triggers Check 3"

# ---- state bookkeeping writes are not implementation edits -----------------
cat > "$TRANSCRIPT_FILE" <<JSONL
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"${STATE_DIR}/agent-count-${SESSION_ID}","content":"6"}}]}}
JSONL

rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null
assert_exit 0 "$(run_gate "$TRANSCRIPT_FILE")" \
    ".alloy-state bookkeeping Write does NOT require reviewers"

# ---- traversal-looking state paths are still implementation edits ----------
cat > "$TRANSCRIPT_FILE" <<JSONL
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"${STATE_DIR}/../project-file","content":"x"}}]}}
JSONL

rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null
assert_exit 2 "$(run_gate "$TRANSCRIPT_FILE")" \
    "state-dir traversal path still triggers reviewer gate"

# ---- nested subagent tool_use inside Agent tool_result is NOT a parent edit -
# Pre-fix bug: the gate's jq used `.. | objects | select(.type=="tool_use")`,
# a deep-walk that recursed INTO Agent tool_result.content blocks. Subagent
# transcripts get echoed back into the parent transcript inside those results.
# If a subagent (even a read-only audit agent) emitted any Edit/Write tool_use,
# the deep-walk surfaced it and counted it as a parent-session implementation
# edit — falsely demanding sentinel/iridium/flint review on a read-only turn.
#
# Fix: restrict to `.message.content[]` of assistant turns. Parent-session only.
# Lock that in here: a transcript whose ONLY Edit blocks live INSIDE a
# tool_result.content[] array must NOT trip Check 3.
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"user","message":{"role":"user","content":"Run a read-only audit subagent"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"sentinel","prompt":"audit"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/sub/agent/edit.ts","old_string":"a","new_string":"b"}},{"type":"tool_use","name":"Write","input":{"file_path":"/sub/agent/new.ts","content":"hi"}}]}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Audit complete — no parent-session edits."}]}}
JSONL

rm -f "$BLOCK_FILE" 2>/dev/null
assert_exit 0 "$(run_gate "$TRANSCRIPT_FILE")" \
    "nested subagent tool_use inside tool_result does NOT count as parent edit"

# ---- explicit edit marker triggers reviewer gate without transcript edit ----
printf '2026-01-01T00:00:00Z\tWrite\t/tmp/changed\n' > "${STATE_DIR}/code-edited-${SESSION_ID}"
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"no edit tool use in recent tail"}]}}
JSONL

rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null
assert_exit 2 "$(run_gate "$TRANSCRIPT_FILE")" \
    "code-edited marker triggers reviewer gate without transcript scan hit"
rm -f "${STATE_DIR}/code-edited-${SESSION_ID}" 2>/dev/null

# ---- stop_hook_active guard prevents recursive blocking --------------------
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/x","content":"x"}}]}}
JSONL

STOP_ACTIVE_RESULT=$(printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":true}' \
    "$SESSION_ID" "$TRANSCRIPT_FILE" \
    | bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$STOP_ACTIVE_RESULT" \
    "stop_hook_active=true bypasses stop-gate recursion"

# ---- TTL: stale IGNITE flag (>2h old) is treated as expired ---------------
# Set the flag's mtime to 3 hours ago. With ALLOY_IGNITE_TTL=7200 (2h default),
# the flag is stale → IGNITE_ACTIVE falls through to transcript scan. The
# transcript here has NO IGNITE invocation, so the gate should allow stop.
THREE_HOURS_AGO=$(( $(date +%s) - 10800 ))
# macOS: -t YYYYMMDDhhmm; Linux: -d @epoch — try both.
touch -t "$(date -r "$THREE_HOURS_AGO" '+%Y%m%d%H%M' 2>/dev/null || date -d "@$THREE_HOURS_AGO" '+%Y%m%d%H%M' 2>/dev/null)" \
    "${STATE_DIR}/ignite-active-${SESSION_ID}" 2>/dev/null || \
touch -d "@$THREE_HOURS_AGO" "${STATE_DIR}/ignite-active-${SESSION_ID}" 2>/dev/null

# Transcript with no IGNITE keywords — fallback scan returns false.
cat > "$TRANSCRIPT_FILE" <<'JSONL'
{"type":"user","message":{"role":"user","content":"normal question, no IGNITE keyword"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"normal reply"}]}}
JSONL
rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null
assert_exit 0 "$(run_gate "$TRANSCRIPT_FILE")" \
    "TTL: stale IGNITE flag (>2h) + no fresh transcript invocation → gate allows stop"

# Restore fresh mtime so cleanup works cleanly.
touch "${STATE_DIR}/ignite-active-${SESSION_ID}" 2>/dev/null

# ---- Single-source-of-truth: transcript mention without flag must NOT activate ----
# Pre-fix bug: the gate scanned the transcript for "IGNITE MODE ACTIVATED" or
# "🔥 IGNITE" as a fallback. That re-introduced the same false-positive class
# the detector was just fixed for: a test prompt or documentation that QUOTES
# the IGNITE banner trips the gate even when the user never invoked IGNITE
# (the detector correctly skipped because of context-aware matching).
#
# Fix: gate trusts the flag file as the only authority. Transcript scan removed.
# Lock that in: when no flag exists but the transcript contains "🔥 IGNITE" as
# documentation/quotation, the gate MUST allow stop (exit 0).
NO_FLAG_SESSION="ignite-noflag-test-$$"
NO_FLAG_TRANSCRIPT=$(mktemp /tmp/alloy-ignite-noflag.XXXXXX)
cat > "$NO_FLAG_TRANSCRIPT" <<'JSONL'
{"type":"user","message":{"role":"user","content":"verify the 🔥 IGNITE header is not a false trigger"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Documentation reference: 🔥 IGNITE banner appears in steel.md."}]}}
JSONL

# No flag file for this session_id. With the fix, gate MUST allow stop.
NO_FLAG_BLOCK_KEY=$(echo "${NO_FLAG_SESSION}-ignite" | cksum | cut -d' ' -f1)
rm -f "${STATE_DIR}/ignite-blocked-${NO_FLAG_BLOCK_KEY}" 2>/dev/null
NO_FLAG_RESULT=$(printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":false}' \
    "$NO_FLAG_SESSION" "$NO_FLAG_TRANSCRIPT" \
    | bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$NO_FLAG_RESULT" \
    "single-source-of-truth: transcript '🔥 IGNITE' mention without flag does NOT activate gate"

rm -f "$NO_FLAG_TRANSCRIPT" "${STATE_DIR}/ignite-blocked-${NO_FLAG_BLOCK_KEY}" 2>/dev/null

done_testing
