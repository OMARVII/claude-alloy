#!/usr/bin/env bash
# Tests for hooks/pre-compact.sh — backup-dir creation + SESSION_ID sanitization.
#
# The hook produces two artifacts: a last-write-wins snapshot (legacy) and a
# per-compact backup dir at ${STATE_DIR}/compact-backup-${SESSION_ID}-${ts}/.
# These tests pin the backup-dir contract and the CWE-22 sanitization the
# hook applies to SESSION_ID before using it in a filesystem path.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/pre-compact.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — pre-compact hook requires jq for input parse\n'
    exit 0
fi

# Override HOME so the hook writes to a sandboxed STATE_DIR. The hook reads
# ${HOME}/.claude/.alloy-state — pointing HOME at a temp dir keeps the test
# from polluting (or depending on) the user's real state dir.
TMP_HOME=$(mktemp -d /tmp/alloy-precompact-test.XXXXXX)
export HOME="$TMP_HOME"
STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

cleanup() {
    rm -rf "$TMP_HOME" 2>/dev/null
    return 0
}
trap cleanup EXIT

# ---- happy-path: well-formed SESSION_ID writes the expected backup dir ----
SESSION_ID="test-abc"
INPUT=$(printf '{"session_id":"%s","transcript_path":"/dev/null"}' "$SESSION_ID")
EXIT_CODE=$(echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$EXIT_CODE" "happy-path: hook exits 0 on well-formed input"

# Backup dir name is compact-backup-${SESSION_ID}-${TS} where TS is unix epoch.
# We can't predict TS exactly, so glob for the prefix and assert exactly one
# match (most recent run).
MATCHES=$(find "$STATE_DIR" -maxdepth 1 -type d -name "compact-backup-${SESSION_ID}-*" 2>/dev/null | wc -l | tr -d ' ')
assert_eq 1 "$MATCHES" "happy-path: exactly one backup dir created with sanitized session id prefix"

# The dir exists and is a directory (already implied by the find -type d, but
# call it out explicitly so a regression in dir-creation is easy to read).
BACKUP_DIR=$(find "$STATE_DIR" -maxdepth 1 -type d -name "compact-backup-${SESSION_ID}-*" 2>/dev/null | head -1)
[ -d "$BACKUP_DIR" ] && DIR_OK="yes" || DIR_OK="no"
assert_eq "yes" "$DIR_OK" "happy-path: backup dir is a real directory"

# ---- path-traversal: ../evil → unknown (CWE-22 defense) -------------------
# The hook sanitizes via [[ =~ ^[A-Za-z0-9_-]+$ ]] || SESSION_ID="unknown".
# A malicious session_id ('../evil') must never become a path component.
rm -rf "$STATE_DIR"/compact-backup-* 2>/dev/null
EVIL_INPUT='{"session_id":"../evil","transcript_path":"/dev/null"}'
EVIL_EXIT=$(echo "$EVIL_INPUT" | bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$EVIL_EXIT" "traversal: hook exits 0 even on malicious session_id (advisory)"

# After sanitization, the backup dir must start with compact-backup-unknown-,
# not compact-backup-../evil- (which would escape STATE_DIR entirely).
UNKNOWN_MATCHES=$(find "$STATE_DIR" -maxdepth 1 -type d -name "compact-backup-unknown-*" 2>/dev/null | wc -l | tr -d ' ')
assert_eq 1 "$UNKNOWN_MATCHES" "traversal: backup dir falls back to 'unknown' prefix"

# Negative assertion: nothing escaped STATE_DIR. Anything matching evil under
# the parent of STATE_DIR (or higher) would indicate a path-traversal hit.
ESCAPED=$(find "${HOME}/.claude" -maxdepth 3 -name "*evil*" 2>/dev/null | wc -l | tr -d ' ')
assert_eq 0 "$ESCAPED" "traversal: no path component named 'evil' anywhere under HOME/.claude"

# ---- PreCompact block-decision during IGNITE + tungsten run ----------------
# When IGNITE is active AND a tungsten subagent is mid-run, the hook must emit
# {"decision":"block"} on stdout so Claude Code defers compaction. Outside
# either of those conditions the hook stays advisory (no decision output).
rm -rf "$STATE_DIR"/compact-backup-* 2>/dev/null

# (a) no IGNITE → no block
BLOCK_SESSION="pcblk-noignite"
NO_BLOCK_INPUT=$(printf '{"session_id":"%s","transcript_path":"/dev/null"}' "$BLOCK_SESSION")
OUT_NOIG=$(echo "$NO_BLOCK_INPUT" | bash "$HOOK" 2>/dev/null)
# Hook must not emit a decision:block when IGNITE is not active.
if echo "$OUT_NOIG" | grep -q '"decision"'; then _has_decision=1; else _has_decision=0; fi
assert_eq 0 "$_has_decision" "no IGNITE: pre-compact emits no decision block"

# (b) IGNITE active + no tungsten marker → no block
BLOCK_SESSION="pcblk-noTungsten"
: > "${STATE_DIR}/ignite-active-${BLOCK_SESSION}"
NO_TUNG_INPUT=$(printf '{"session_id":"%s","transcript_path":"/dev/null"}' "$BLOCK_SESSION")
OUT_NOTUNG=$(echo "$NO_TUNG_INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$OUT_NOTUNG" | grep -q '"decision"'; then _has_decision=1; else _has_decision=0; fi
assert_eq 0 "$_has_decision" "IGNITE + no tungsten: pre-compact emits no decision block"

# (c) IGNITE active + tungsten marker fresh → emits decision:block
BLOCK_SESSION="pcblk-active"
: > "${STATE_DIR}/ignite-active-${BLOCK_SESSION}"
: > "${STATE_DIR}/tungsten-active-${BLOCK_SESSION}"
BLOCK_INPUT=$(printf '{"session_id":"%s","transcript_path":"/dev/null"}' "$BLOCK_SESSION")
OUT_BLOCK=$(echo "$BLOCK_INPUT" | bash "$HOOK" 2>/dev/null)
BLOCK_DECISION=$(echo "$OUT_BLOCK" | jq -r '.decision // ""' 2>/dev/null)
assert_eq "block" "$BLOCK_DECISION" "IGNITE + active tungsten: pre-compact emits decision:block"
BLOCK_REASON=$(echo "$OUT_BLOCK" | jq -r '.reason // ""' 2>/dev/null)
case "$BLOCK_REASON" in
    *IGNITE*tungsten*) _reason_ok=1 ;;
    *) _reason_ok=0 ;;
esac
assert_eq 1 "$_reason_ok" "block decision includes IGNITE+tungsten reason"

# (d) tungsten marker stale (>30min by default) → no block
BLOCK_SESSION="pcblk-stale"
: > "${STATE_DIR}/ignite-active-${BLOCK_SESSION}"
: > "${STATE_DIR}/tungsten-active-${BLOCK_SESSION}"
# Backdate the tungsten marker by 1 hour.
ONE_HOUR_AGO=$(( $(date +%s) - 3600 ))
touch -t "$(date -r "$ONE_HOUR_AGO" '+%Y%m%d%H%M' 2>/dev/null || date -d "@$ONE_HOUR_AGO" '+%Y%m%d%H%M' 2>/dev/null)" \
    "${STATE_DIR}/tungsten-active-${BLOCK_SESSION}" 2>/dev/null || \
touch -d "@$ONE_HOUR_AGO" "${STATE_DIR}/tungsten-active-${BLOCK_SESSION}" 2>/dev/null
STALE_INPUT=$(printf '{"session_id":"%s","transcript_path":"/dev/null"}' "$BLOCK_SESSION")
OUT_STALE=$(echo "$STALE_INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$OUT_STALE" | grep -q '"decision"'; then _has_decision=1; else _has_decision=0; fi
assert_eq 0 "$_has_decision" "stale tungsten marker (>30min) does NOT block"

done_testing
