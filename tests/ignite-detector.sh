#!/usr/bin/env bash
# Tests for hooks/ignite-detector.sh — context-aware activation.
#
# Regression target: v1.6.6 used naive `\big\b|\bignite\b` grep over the raw
# prompt. Quoted/code-fenced/descriptive mentions ("verify the IGNITE
# protocol", `'please IGNITE this'`) tripped the detector and forced 6+
# agents on prompts that merely DISCUSSED ignite. v1.6.7 strips quoted/code
# regions then skips matches preceded by descriptive modifier words.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/ignite-detector.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — ignite-detector exits early without it\n'
    exit 0
fi

# Sandbox HOME so the detector's STATE_DIR=${HOME}/.claude/.alloy-state lands
# in /tmp instead of writing the real ignite-active-* flag.
TMP_HOME=$(mktemp -d /tmp/alloy-ignitedetector-test.XXXXXX)
export HOME="$TMP_HOME"
STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

cleanup() {
    rm -rf "$TMP_HOME" 2>/dev/null
    return 0
}
trap cleanup EXIT

# call_hook PROMPT SESSION_ID
# Returns 0 if IGNITE flag was created, 1 otherwise. Wipes the flag between
# calls so each test is independent.
call_hook() {
    _prompt=$1
    _sid=$2
    rm -f "${STATE_DIR}/ignite-active-${_sid}" 2>/dev/null
    # jq -nc builds a properly-escaped JSON envelope so quotes/newlines in
    # the test prompt don't break stdin parsing.
    jq -nc --arg p "$_prompt" --arg s "$_sid" \
        '{prompt: $p, session_id: $s}' \
        | bash "$HOOK" >/dev/null 2>&1
    [ -f "${STATE_DIR}/ignite-active-${_sid}" ]
}

# ---- Positive: clear user-intent invocations should activate -----------------

call_hook "ig let's go" "pos-1" \
    && PASS=1 || PASS=0
assert_eq 1 "$PASS" "positive: bare 'ig' as imperative activates"

call_hook "ignite this task" "pos-2" \
    && PASS=1 || PASS=0
assert_eq 1 "$PASS" "positive: 'ignite this task' activates"

call_hook "ig deep audit please" "pos-3" \
    && PASS=1 || PASS=0
assert_eq 1 "$PASS" "positive: 'ig' followed by directive activates"

# ---- Negative: descriptive/referential mentions should NOT activate ----------

call_hook "verify the IGNITE 7-step protocol works" "neg-1" \
    && PASS=1 || PASS=0
assert_eq 0 "$PASS" "negative: 'verify the IGNITE protocol' does NOT activate"

call_hook "regarding IGNITE mode behavior" "neg-2" \
    && PASS=1 || PASS=0
assert_eq 0 "$PASS" "negative: 'regarding IGNITE mode' does NOT activate"

call_hook "test the IGNITE detector edge cases" "neg-3" \
    && PASS=1 || PASS=0
assert_eq 0 "$PASS" "negative: 'test the IGNITE detector' does NOT activate"

call_hook "describing our IGNITE protocol design" "neg-4" \
    && PASS=1 || PASS=0
assert_eq 0 "$PASS" "negative: 'describing our IGNITE' does NOT activate"

# ---- Quoted / code-fenced mentions should NOT activate -----------------------

call_hook 'please "IGNITE this" if you can' "neg-q1" \
    && PASS=1 || PASS=0
assert_eq 0 "$PASS" "negative: double-quoted 'IGNITE' does NOT activate"

call_hook "code reference: \`ignite\` is a slash command" "neg-q2" \
    && PASS=1 || PASS=0
assert_eq 0 "$PASS" "negative: backtick-quoted 'ignite' does NOT activate"

# Code fence — multi-line. The detector strips the fenced block before scanning.
# shellcheck disable=SC2016  # Backticks inside printf format are literal escape sequences, not command substitution
call_hook "$(printf 'see the example below:\n\`\`\`\nig start\n\`\`\`\nthat is the ignite invocation form')" "neg-q3" \
    && PASS=1 || PASS=0
# This one should NOT activate — both occurrences are in fenced/descriptive
# context. "the ignite invocation form" has "the" preceding it.
assert_eq 0 "$PASS" "negative: fenced code block + descriptive 'the ignite' does NOT activate"

# ---- Apostrophe-collapse regression (unbalanced single quotes) ---------------
# Pre-fix: greedy `s/'[^']*'//g` eats text between unpaired contractions and
# any later apostrophe, sometimes deleting the keyword itself.
# Example: "don't ignite, that's the goal" -> "dons the goal" (no match).
# Fix: skip single-quote stripping when apostrophe count is odd.

call_hook "don't ignite this — that's not what we'll do" "pos-apos-1" \
    && PASS=1 || PASS=0
assert_eq 1 "$PASS" "positive: contractions with odd apostrophe count don't collapse the keyword"

call_hook "let's ignite the build" "pos-apos-2" \
    && PASS=1 || PASS=0
assert_eq 1 "$PASS" "positive: 'let's ignite' (single contraction) activates"

# Balanced apostrophes — stripping should still happen, killing the reference.
call_hook "can you 'ignite' please" "neg-apos-1" \
    && PASS=1 || PASS=0
assert_eq 0 "$PASS" "negative: balanced single-quoted 'ignite' (even count) still strips and does NOT activate"

# ---- Fresh-activation reset (counter cleared on new IGNITE phase) ----------
# Pre-fix: a session that IGNITEd, fired N agents, then IGNITEd AGAIN later
# (in the same session) inherited the prior phase's count — the new phase's
# 6-agent gate could be satisfied without spawning anything fresh.
# Fix: detector clears agent-count + agents-spawned files when activating
# either fresh OR after the flag's TTL expires.

# Seed prior-phase counters for a fresh session id
RESET_SID="reset-test-$$"
echo "30" > "${STATE_DIR}/agent-count-${RESET_SID}"
printf 'graphene\nmercury\nmercury\n' > "${STATE_DIR}/agents-spawned-${RESET_SID}"

# Activate IGNITE for the first time on this session — RESET should fire
# because the flag does NOT exist yet (fresh activation).
call_hook "ig let's go" "$RESET_SID" >/dev/null

# Counter file should be removed (or empty) after reset
COUNT_AFTER_RESET=$([ -f "${STATE_DIR}/agent-count-${RESET_SID}" ] && cat "${STATE_DIR}/agent-count-${RESET_SID}" || echo "missing")
assert_eq "missing" "$COUNT_AFTER_RESET" "fresh-activation reset: prior agent-count file is removed"

LEDGER_AFTER_RESET=$([ -f "${STATE_DIR}/agents-spawned-${RESET_SID}" ] && echo "exists" || echo "missing")
assert_eq "missing" "$LEDGER_AFTER_RESET" "fresh-activation reset: prior agents-spawned ledger is removed"

# IGNITE flag must now be set
[ -f "${STATE_DIR}/ignite-active-${RESET_SID}" ] && FLAG="set" || FLAG="missing"
assert_eq "set" "$FLAG" "fresh-activation reset: IGNITE flag is set after reset"

# Re-activation while flag is FRESH (within TTL) must NOT reset — counts
# accumulated during the active phase belong to that phase. The standard
# call_hook helper removes the flag pre-call, so we invoke the hook
# directly here to preserve the flag set by the first activation above.
echo "5" > "${STATE_DIR}/agent-count-${RESET_SID}"
printf 'mercury\nmercury\nmercury\nmercury\nmercury\n' > "${STATE_DIR}/agents-spawned-${RESET_SID}"
jq -nc --arg p "ig keep going" --arg s "$RESET_SID" \
    '{prompt: $p, session_id: $s}' \
    | bash "$HOOK" >/dev/null 2>&1
PRESERVED_COUNT=$(cat "${STATE_DIR}/agent-count-${RESET_SID}" 2>/dev/null || echo "missing")
assert_eq "5" "$PRESERVED_COUNT" "in-phase re-activation does NOT reset counter (flag still fresh)"

# ---- sessionTitle on first IGNITE activation -------------------------------
# Per https://code.claude.com/docs/en/hooks, UserPromptSubmit hooks can set
# hookSpecificOutput.sessionTitle. The detector emits the title ONLY on the
# first IGNITE activation per session (gated by a per-session marker file) so
# follow-up IGNITE prompts in the same session don't keep retitling.

TITLE_SID="title-test-$$"
rm -f "${STATE_DIR}/ignite-titled-${TITLE_SID}" "${STATE_DIR}/ignite-active-${TITLE_SID}" 2>/dev/null

FIRST_OUT=$(jq -nc --arg p "ig kick off the v1.7.0 release" --arg s "$TITLE_SID" \
    '{prompt: $p, session_id: $s}' \
    | bash "$HOOK" 2>/dev/null)
HAS_TITLE=$(printf '%s' "$FIRST_OUT" | jq -r '.hookSpecificOutput.sessionTitle // empty' 2>/dev/null)
if [ -n "$HAS_TITLE" ]; then PASS=1; else PASS=0; fi
assert_eq 1 "$PASS" "sessionTitle: emitted on first IGNITE activation in a session"

# Non-IGNITE prompt: must NOT emit sessionTitle. The detector exits 0 early
# on non-IGNITE input and writes nothing to stdout, so the captured output is
# empty. We assert on the absence of any "sessionTitle" substring rather than
# trying to jq-parse empty input.
NOIG_SID="noig-test-$$"
NOIG_OUT=$(jq -nc --arg p "please summarize the changelog" --arg s "$NOIG_SID" \
    '{prompt: $p, session_id: $s}' \
    | bash "$HOOK" 2>/dev/null)
if printf '%s' "$NOIG_OUT" | grep -q 'sessionTitle'; then
    NOIG_HAS_TITLE=1
else
    NOIG_HAS_TITLE=0
fi
assert_eq 0 "$NOIG_HAS_TITLE" "sessionTitle: NOT emitted on non-IGNITE prompts"

# ---- sessionTitle strips ALL C0 control bytes ------------------------------
# Previously the title pass replaced only \n\r\t with spaces, letting bytes
# like 0x01-0x08, 0x0B, 0x0C, 0x0E-0x1F pass through where jq escapes them as
# \uXXXX in the JSON output. Not exploitable but ugly in the sidebar. The
# tr -d '\000-\037' filter deletes ALL C0 control bytes; assert the emitted
# title contains no byte in that range.
CTL_SID="ctl-test-$$"
rm -f "${STATE_DIR}/ignite-titled-${CTL_SID}" "${STATE_DIR}/ignite-active-${CTL_SID}" 2>/dev/null
CTL_PROMPT=$(printf 'ignite \001\002\003 dangerous test')
CTL_OUT=$(jq -nc --arg p "$CTL_PROMPT" --arg s "$CTL_SID" \
    '{prompt: $p, session_id: $s}' \
    | bash "$HOOK" 2>/dev/null)
CTL_TITLE=$(printf '%s' "$CTL_OUT" | jq -r '.hookSpecificOutput.sessionTitle // empty' 2>/dev/null)
# Count any bytes in the 0x01-0x1F control range that survived sanitization.
HAS_CTL=$(printf '%s' "$CTL_TITLE" | LC_ALL=C tr -cd '\001-\037' | wc -c | tr -d ' ')
assert_eq 0 "$HAS_CTL" "sessionTitle: strips C0 control bytes from the prompt"

done_testing
