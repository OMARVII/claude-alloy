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

done_testing
