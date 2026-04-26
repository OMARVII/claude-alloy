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

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

SNAPSHOT_FILE="${STATE_DIR}/pre-compact-snapshot.md"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

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

exit 0
