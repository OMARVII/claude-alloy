#!/usr/bin/env bash
# IGNITE Mode Stop Gate — Blocks exit if IGNITE protocol wasn't followed
# Runs as Stop hook
# Exit 0 = allow stop, Exit 2 = block stop

set -u

INPUT=$(cat)

command -v jq &>/dev/null || exit 0

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
# Stale-file cleanup is centralized in hooks/session-end.sh.

# Extract fields from input
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo "default")
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")

# Prevent infinite re-blocking loop
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Detect IGNITE mode — single source of truth: the flag file written by
# hooks/ignite-detector.sh. The detector applies context-aware filtering
# (skips quoted, descriptive, and test-context mentions) and is the ONLY
# path that should activate IGNITE.
#
# Pre-v1.6.7 we also scanned the transcript for "IGNITE MODE ACTIVATED" or
# "🔥 IGNITE" as a fallback, but that scan re-introduced the same false-
# positive class the detector was just fixed for: any prompt that QUOTES
# the IGNITE banner (test prompts, documentation, this changelog itself)
# would trip the gate. Removed in favor of detector-only authority.
#
# IGNITE_TTL freshness: a flag set hours ago shouldn't keep demanding 6+
# agents on unrelated stops afterwards. Statusline expires at 6h; the
# stop-gate uses a tighter 2h window because protocol enforcement is
# stricter than visual indication. Override via ALLOY_IGNITE_TTL=<seconds>.
IGNITE_TTL=${ALLOY_IGNITE_TTL:-7200}

IGNITE_ACTIVE=false
IGNITE_FLAG="${STATE_DIR}/ignite-active-${SESSION_ID}"
if [ -f "$IGNITE_FLAG" ]; then
    NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)
    # macOS `stat -f %m`, GNU `stat -c %Y` — try both, fall back to 0.
    FLAG_EPOCH=$(stat -f %m "$IGNITE_FLAG" 2>/dev/null || stat -c %Y "$IGNITE_FLAG" 2>/dev/null || echo 0)
    AGE=$(( NOW_EPOCH - FLAG_EPOCH ))
    if [ "$AGE" -ge 0 ] && [ "$AGE" -le "$IGNITE_TTL" ]; then
        IGNITE_ACTIVE=true
    fi
    # Older than TTL → flag stale; treat session as not in IGNITE.
fi

# Not an IGNITE session — allow stop
if [ "$IGNITE_ACTIVE" = "false" ]; then
    exit 0
fi

# === IGNITE compliance checks ===
VIOLATIONS=""

# Check 1: Agent count >= 6
AGENT_COUNT=0
COUNT_FILE="${STATE_DIR}/agent-count-${SESSION_ID}"
if [ -f "$COUNT_FILE" ]; then
    AGENT_COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo "0")
fi
if [ "$AGENT_COUNT" -lt 6 ]; then
    VIOLATIONS="${VIOLATIONS}Only ${AGENT_COUNT}/6 required agents spawned. "
fi

# Check 2: graphene must be present in spawned agents
AGENTS_FILE="${STATE_DIR}/agents-spawned-${SESSION_ID}"
if [ -f "$AGENTS_FILE" ]; then
    if ! grep -qi "graphene" "$AGENTS_FILE" 2>/dev/null; then
        VIOLATIONS="${VIOLATIONS}graphene agent never spawned (mandatory for IGNITE). "
    fi
else
    VIOLATIONS="${VIOLATIONS}No agent spawn records found. "
fi

# Check 3: If code was edited, review agents must have been spawned
# Match Claude Code transcript JSONL tool_use blocks specifically. Bare "Edit|Write"
# matches free-text mentions in tool schemas, agent prompts, plan tables, and system
# reminders — every research-only IGNITE turn would false-positive and force
# sentinel/iridium/flint to spawn unnecessarily. The pattern below requires the
# string to appear as a tool_use `name` field value.
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    if tail -500 "$TRANSCRIPT_PATH" 2>/dev/null | grep -qE '"name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit|NotebookEdit)"'; then
        MISSING_REVIEWERS=""
        if [ -f "$AGENTS_FILE" ]; then
            if ! grep -qi "sentinel" "$AGENTS_FILE" 2>/dev/null; then
                MISSING_REVIEWERS="${MISSING_REVIEWERS}sentinel "
            fi
            if ! grep -qi "iridium" "$AGENTS_FILE" 2>/dev/null; then
                MISSING_REVIEWERS="${MISSING_REVIEWERS}iridium "
            fi
            if ! grep -qi "flint" "$AGENTS_FILE" 2>/dev/null; then
                MISSING_REVIEWERS="${MISSING_REVIEWERS}flint "
            fi
        else
            MISSING_REVIEWERS="sentinel iridium flint"
        fi
        if [ -n "$MISSING_REVIEWERS" ]; then
            VIOLATIONS="${VIOLATIONS}Code was edited but review agents missing: ${MISSING_REVIEWERS}. "
        fi
    fi
fi

# No violations — allow stop, clean up block file
if [ -z "$VIOLATIONS" ]; then
    BLOCK_KEY=$(echo "${SESSION_ID}-ignite" | cksum | cut -d' ' -f1)
    rm -f "${STATE_DIR}/ignite-blocked-${BLOCK_KEY}" 2>/dev/null || true
    exit 0
fi

# Block-file dedup pattern: first attempt blocks, second allows with warning
BLOCK_KEY=$(echo "${SESSION_ID}-ignite" | cksum | cut -d' ' -f1)
BLOCK_FILE="${STATE_DIR}/ignite-blocked-${BLOCK_KEY}"

if [ -f "$BLOCK_FILE" ]; then
    # Second attempt — allow stop but warn
    rm -f "$BLOCK_FILE"
    jq -nc --arg msg "IGNITE compliance warnings: ${VIOLATIONS}" \
        '{systemMessage: $msg}'
    exit 0
fi

# First attempt — block stop
echo "1" > "$BLOCK_FILE"
jq -nc --arg reason "IGNITE violations: ${VIOLATIONS}Fix before stopping." \
    '{decision: "block", reason: $reason}'
exit 2
