#!/usr/bin/env bash
# Pre-Compact Hook — Snapshots working state before context compaction.
# Runs as PreCompact hook. Always exits 0 (advisory; never blocks compaction).
#
# Two artifacts are produced:
#   1. ${STATE_DIR}/pre-compact-snapshot.md  — last-write-wins quick view (legacy).
#   2. ${STATE_DIR}/compact-backup-${SESSION_ID}-${ts}/
#        plan.md, prompt_plan.md, auto-loop-todo.md, .alloy-loop-active (when present)
#        transcript-tail.jsonl (last 200 lines of the live transcript)
#      — survives this and prior compactions; pruned by session-end.sh after 7d.

set -u

INPUT=$(cat)

# shellcheck source=hooks/_state-dir.sh
. "$(dirname "$0")/_state-dir.sh"
STATE_DIR="${HOME}/.claude/.alloy-state"
alloy_ensure_state_dir "$STATE_DIR" || exit 0

SNAPSHOT_FILE="${STATE_DIR}/pre-compact-snapshot.md"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Detect stat flavor and current epoch ONCE per invocation. is_fresh() is
# called twice below (ignite + tungsten markers); the previous form retried
# the BSD/GNU stat fallback and forked `date +%s` on every call, costing
# 3 forks per call → 6 forks per event. Caching at script scope drops it
# to 1 fork per call (just the stat itself).
if stat -c %Y /dev/null >/dev/null 2>&1; then
    STAT_MTIME_CMD="stat -c %Y"
else
    STAT_MTIME_CMD="stat -f %m"
fi
NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)

SOURCE="unknown"
SESSION_ID="unknown"
TRANSCRIPT_PATH=""
if command -v jq &>/dev/null; then
    SOURCE=$(echo "$INPUT" | jq -r '.compaction_source // "unknown"' 2>/dev/null) || SOURCE="unknown"
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || SESSION_ID="unknown"
    TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null) || TRANSCRIPT_PATH=""
fi
# Sanitize SESSION_ID against path traversal (CWE-22) — same allowlist as
# context-pressure.sh / statusline.sh / skill-reminder.sh.
[[ "$SESSION_ID" =~ ^[A-Za-z0-9_-]+$ ]] || SESSION_ID="unknown"

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "n/a")
UNCOMMITTED=$(git status --short 2>/dev/null || echo "n/a")
RECENT_LOG=$(git log --oneline -5 2>/dev/null || echo "n/a")

cat > "$SNAPSHOT_FILE" << EOF
# Pre-Compaction Snapshot

**Timestamp:** ${TIMESTAMP}
**Compaction source:** ${SOURCE}
**Git branch:** ${BRANCH}
**Session id:** ${SESSION_ID}

## Uncommitted files
${UNCOMMITTED:-none}

## Recent commits
${RECENT_LOG:-none}
EOF

# --- Per-compact backup dir (recovery insurance) -----------------------------
# Files we care about — plan/todo state Claude can rehydrate from after compact.
TS=$(date +%s)
BACKUP_DIR="${STATE_DIR}/compact-backup-${SESSION_ID}-${TS}"
mkdir -p "$BACKUP_DIR" 2>/dev/null || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
# -P preserves symlinks instead of dereferencing them. Same trust boundary as
# the user (so not exploitable), but a planted plan.md -> /etc/passwd would
# otherwise have its target copied into the backup dir; -P keeps the link.
for fname in plan.md prompt_plan.md auto-loop-todo.md .alloy-loop-active; do
    src="${PROJECT_DIR}/${fname}"
    [ -f "$src" ] && cp -P "$src" "${BACKUP_DIR}/" 2>/dev/null
done

# Transcript tail — last 200 lines preserves recent assistant turns + the user
# prompt that triggered compaction. Cheap (a few KB) and the most useful single
# artifact for post-compact recovery.
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    tail -n 200 "$TRANSCRIPT_PATH" > "${BACKUP_DIR}/transcript-tail.jsonl" 2>/dev/null || true
fi

# Tell the user where the backup lives. stderr only — stdout is reserved for
# hook protocol output (this hook emits none, so we don't pollute it).
echo "[pre-compact] Forensic snapshot saved at ${BACKUP_DIR}" >&2

# --- Block compaction while IGNITE+tungsten run is mid-flight -----------------
# Auto-compaction in the middle of a tungsten run truncates the agent's working
# context — the planner state, file paths it has touched, and the live todo set
# get summarized away even though the agent is still actively reasoning about
# them. Outside IGNITE that's an acceptable trade-off (the user can /resume).
# Inside IGNITE the user has explicitly opted into a high-context regime; mid-
# task compaction is far more damaging than the small delay of postponing it.
#
# Detection requires BOTH:
#   1. IGNITE flag fresh (TTL 2h, matching ignite-stop-gate.sh default)
#   2. tungsten-active marker fresh (TTL 30min — tungsten runs are bounded; a
#      stale marker indicates a missed subagent-stop, not an active run)
# Override either TTL via ALLOY_IGNITE_TTL / ALLOY_TUNGSTEN_TTL.
IGNITE_TTL=${ALLOY_IGNITE_TTL:-7200}
TUNGSTEN_TTL=${ALLOY_TUNGSTEN_TTL:-1800}

is_fresh() {
    # $1 = file path, $2 = ttl seconds. Echoes "true" / "false".
    # Uses script-scope STAT_MTIME_CMD + NOW_EPOCH (resolved once at script
    # start) instead of retrying the BSD/GNU stat fallback and re-forking
    # `date +%s` on every call. Saves 2 forks per call, 4 per event.
    _f=$1; _ttl=$2
    [ -f "$_f" ] || { printf 'false'; return; }
    _mt=$($STAT_MTIME_CMD "$_f" 2>/dev/null || echo 0)
    case "$_mt" in ''|*[!0-9]*) _mt=0 ;; esac
    _age=$(( NOW_EPOCH - _mt ))
    if [ "$_age" -ge 0 ] && [ "$_age" -le "$_ttl" ]; then
        printf 'true'
    else
        printf 'false'
    fi
}

# SESSION_ID is sanitized above (CWE-22 guard); only proceed if it's a real id.
if [ "$SESSION_ID" != "unknown" ]; then
    IGNITE_FRESH=$(is_fresh "${STATE_DIR}/ignite-active-${SESSION_ID}" "$IGNITE_TTL")
    TUNGSTEN_FRESH=$(is_fresh "${STATE_DIR}/tungsten-active-${SESSION_ID}" "$TUNGSTEN_TTL")
    if [ "$IGNITE_FRESH" = "true" ] && [ "$TUNGSTEN_FRESH" = "true" ]; then
        jq -nc --arg reason "PreCompact deferred: IGNITE+tungsten mid-run. Compaction would truncate the active agent's working context." \
            '{decision: "block", reason: $reason}'
        exit 0
    fi
fi

exit 0
