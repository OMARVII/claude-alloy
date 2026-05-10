#!/usr/bin/env bash
# IGNITE Detector — Detects "ig"/"ignite" in user prompt and sets flag
# Runs as UserPromptSubmit hook
# Exit 0 = always allow

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

# shellcheck source=./_state-dir.sh
. "$(dirname "$0")/_state-dir.sh"
STATE_DIR="${HOME}/.claude/.alloy-state"
alloy_ensure_state_dir "$STATE_DIR" || exit 0
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

# Detect "ig" or "ignite" as USER INTENT, not as a referential mention.
#
# Pre-v1.6.7 behavior: naive `\big\b|\bignite\b` matched the keyword anywhere
# — including inside quoted strings, code fences, and descriptive phrases like
# "verify the IGNITE protocol works" or "regarding ignite mode". That tripped
# the stop-gate on test prompts that merely DISCUSSED IGNITE without invoking
# it (a real false-positive caught during v1.6.7 verification).
#
# New approach:
#   1. Strip code fences (``` … ```), inline code (`…`), and quoted spans
#      ("…", '…') from the prompt before matching. References inside those
#      regions don't count as user intent.
#   2. After stripping, if the keyword is preceded by a descriptive modifier
#      (the/an/this/that/our/about/regarding/describes/describing/protocol/
#      mode/test/testing/verify/verification), treat it as a reference, not
#      an invocation.
IGNITE_DETECTED=false

# Stage 1 — strip code/quoted regions. perl handles multi-line code fences;
# falls back to passthrough if perl is missing (rare on macOS/Linux).
if command -v perl >/dev/null 2>&1; then
    STRIPPED=$(printf '%s' "$PROMPT_TEXT" | perl -0777 -pe 's/```.*?```//gs' 2>/dev/null)
else
    STRIPPED="$PROMPT_TEXT"
fi
# Single-line code spans + quoted strings. Use sed with separate -e blocks
# so single-quote stripping works (the literal single-quote in the pattern
# would otherwise close the bash string). Sed scripts are deliberately in
# single quotes — backticks and dollar signs in these regexes are literal
# pattern characters, not bash expansions.
# shellcheck disable=SC2016
STRIPPED=$(printf '%s' "$STRIPPED" \
    | sed -E 's/`[^`]*`//g' \
    | sed -E 's/"[^"]*"//g')
# Single-quote stripping is conditional: only collapse if the prompt has an
# EVEN number of apostrophes. An unpaired apostrophe means at least one is a
# conversational contraction ("don't", "let's"), not a quote delimiter — and
# greedy `'[^']*'` would eat real text between the contraction and the next
# stray apostrophe, sometimes suppressing a legitimate IGNITE keyword.
QUOTE_COUNT=$(printf '%s' "$STRIPPED" | tr -cd "'" | wc -c | tr -d ' ')
if [ $((QUOTE_COUNT % 2)) -eq 0 ] && [ "$QUOTE_COUNT" -gt 0 ]; then
    STRIPPED=$(printf '%s' "$STRIPPED" | sed "s/'[^']*'//g")
fi

# Stage 2 — match candidate then re-check context.
if printf '%s' "$STRIPPED" | grep -qiE '\b(ig|ignite)\b'; then
    # If a descriptive modifier precedes the keyword anywhere, treat as
    # reference. Word-boundary on each side keeps "this" from matching
    # "thistle" etc.
    if printf '%s' "$STRIPPED" | grep -qiE '\b(the|an|this|that|our|about|regarding|describes|describing|protocol|mode|test|testing|verify|verification) +(ig|ignite)\b'; then
        IGNITE_DETECTED=false
    else
        IGNITE_DETECTED=true
    fi
fi

if [ "${ALLOY_DEBUG:-0}" = "1" ]; then
    printf '[alloy] ignite-detector raw=%q stripped=%q detected=%s\n' \
        "$PROMPT_TEXT" "$STRIPPED" "$IGNITE_DETECTED" >&2
fi

if [ "$IGNITE_DETECTED" = "false" ]; then
    exit 0
fi

# Set IGNITE flag with timestamp.
#
# Fresh-activation reset: if no flag exists OR the flag is older than the
# stop-gate's TTL (default 2h via ALLOY_IGNITE_TTL), this is a NEW IGNITE
# phase — clear the per-session counter and ledger so stale counts from
# a prior IGNITE phase in the same session don't satisfy the new phase's
# 6-agent floor. Without this, a user IGNITEs at T+0, fires 30 agents,
# idles 3h (flag expires), re-IGNITEs at T+3h with 0 agents → gate
# falsely passes because counter still reads 30.
IGNITE_FLAG="${STATE_DIR}/ignite-active-${SESSION_ID}"
IGNITE_TTL=${ALLOY_IGNITE_TTL:-7200}
RESET_COUNTERS=false
if [ ! -f "$IGNITE_FLAG" ]; then
    RESET_COUNTERS=true
else
    NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)
    # BSD `stat -f %m` on Linux exits 0 with garbage output — always try GNU first.
    FLAG_EPOCH=$(stat -c %Y "$IGNITE_FLAG" 2>/dev/null || stat -f %m "$IGNITE_FLAG" 2>/dev/null || echo 0)
    case "$FLAG_EPOCH" in
        ''|*[!0-9]*) FLAG_EPOCH=0 ;;
    esac
    AGE=$(( NOW_EPOCH - FLAG_EPOCH ))
    if [ "$AGE" -gt "$IGNITE_TTL" ]; then
        RESET_COUNTERS=true
    fi
fi
if [ "$RESET_COUNTERS" = "true" ]; then
    rm -f "${STATE_DIR}/agent-count-${SESSION_ID}" \
          "${STATE_DIR}/agents-spawned-${SESSION_ID}" 2>/dev/null || true
fi
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$IGNITE_FLAG"

# Output context injection for the LLM
jq -nc --arg ctx '[IGNITE PROTOCOL] Maximum-effort mode detected. Requirements: (1) 6+ background agents including graphene, (2) tungsten for all implementation, (3) sentinel/iridium/flint after code changes, (4) detailed todos via TaskWrite, (5) manual QA before completion.' \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'

exit 0
