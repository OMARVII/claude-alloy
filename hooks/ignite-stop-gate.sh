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
    # BSD `stat -f %m` on Linux exits 0 with garbage output (mount point) —
    # always try GNU `stat -c %Y` first, then BSD as fallback.
    FLAG_EPOCH=$(stat -c %Y "$IGNITE_FLAG" 2>/dev/null || stat -f %m "$IGNITE_FLAG" 2>/dev/null || echo 0)
    case "$FLAG_EPOCH" in
        ''|*[!0-9]*) FLAG_EPOCH=0 ;;
    esac
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
case "$AGENT_COUNT" in
    ''|*[!0-9]*) AGENT_COUNT=0 ;;
esac
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
# Match Claude Code transcript JSONL tool_use blocks specifically. Internal
# writes to Alloy's state dir are bookkeeping, not implementation edits.
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    CODE_EDITED=false
    EDIT_MARKER="${STATE_DIR}/code-edited-${SESSION_ID}"
    if [ -s "$EDIT_MARKER" ]; then
        CODE_EDITED=true
    else
        EDIT_RECORDS=$(tail -500 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '
            .. | objects
            | select(.type? == "tool_use")
            | select(.name? == "Edit" or .name? == "Write" or .name? == "MultiEdit" or .name? == "NotebookEdit")
            | [.name, (.input.file_path // .input.path // "")]
            | @tsv
        ' 2>/dev/null)
        if [ -n "$EDIT_RECORDS" ]; then
            while IFS=$'\t' read -r _TOOL_NAME FILE_PATH; do
                IS_STATE_BOOKKEEPING=false
                case "$FILE_PATH" in
                    "$STATE_DIR"/*)
                        STATE_FILE=${FILE_PATH#"$STATE_DIR"/}
                        case "$STATE_FILE" in
                            */*|.*|*..*) ;;
                            agent-count-*|agents-spawned-*|ignite-active-*|ignite-blocked-*)
                                if [ ! -L "$FILE_PATH" ]; then
                                    IS_STATE_BOOKKEEPING=true
                                fi
                                ;;
                        esac
                        ;;
                esac
                if [ "$IS_STATE_BOOKKEEPING" != "true" ]; then
                    CODE_EDITED=true
                fi
                if [ "$CODE_EDITED" = "true" ]; then
                    break
                fi
            done <<< "$EDIT_RECORDS"
        fi
    fi
    if [ "$CODE_EDITED" = "true" ]; then
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
