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

done_testing
