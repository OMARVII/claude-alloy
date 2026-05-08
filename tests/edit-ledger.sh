#!/usr/bin/env bash
# Tests for hooks/edit-ledger.sh — records real edits, skips hook bookkeeping.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/edit-ledger.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — edit-ledger exits early without it\n'
    exit 0
fi

ORIG_HOME=${HOME:-}
TEST_HOME=$(mktemp -d /tmp/alloy-edit-ledger-home.XXXXXX)
export HOME="$TEST_HOME"
STATE_DIR="${HOME}/.claude/.alloy-state"

cleanup() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME" 2>/dev/null
    return 0
}
trap cleanup EXIT

run_ledger() {
    _session=$1
    _tool=$2
    _path=$3
    printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' \
        "$_session" "$_tool" "$_path" \
        | bash "$HOOK" >/dev/null 2>&1
    printf '%s' "$?"
}

SID="edit-ledger-test-$$"
MARKER="${STATE_DIR}/code-edited-${SID}"

assert_exit 0 "$(run_ledger "$SID" Write "/tmp/changed")" \
    "real Write exits cleanly"
[ -s "$MARKER" ] && _marker_created=1 || _marker_created=0
assert_eq 1 "$_marker_created" "real Write creates code-edited marker"

STATE_SID="state-ledger-test-$$"
STATE_MARKER="${STATE_DIR}/code-edited-${STATE_SID}"
mkdir -p "$STATE_DIR"
assert_exit 0 "$(run_ledger "$STATE_SID" Write "${STATE_DIR}/agent-count-${STATE_SID}")" \
    "state bookkeeping Write exits cleanly"
[ -e "$STATE_MARKER" ] && _state_marker=1 || _state_marker=0
assert_eq 0 "$_state_marker" "state bookkeeping Write does not create marker"

TRAVERSAL_SID="traversal-ledger-test-$$"
TRAVERSAL_MARKER="${STATE_DIR}/code-edited-${TRAVERSAL_SID}"
assert_exit 0 "$(run_ledger "$TRAVERSAL_SID" Write "${STATE_DIR}/../project-file")" \
    "traversal-looking Write exits cleanly"
[ -s "$TRAVERSAL_MARKER" ] && _traversal_marker=1 || _traversal_marker=0
assert_eq 1 "$_traversal_marker" "traversal-looking state path creates marker"

NOTEBOOK_SID="notebook-ledger-test-$$"
NOTEBOOK_MARKER="${STATE_DIR}/code-edited-${NOTEBOOK_SID}"
assert_exit 0 "$(run_ledger "$NOTEBOOK_SID" NotebookEdit "/tmp/notebook.ipynb")" \
    "NotebookEdit exits cleanly"
[ -s "$NOTEBOOK_MARKER" ] && _notebook_marker=1 || _notebook_marker=0
assert_eq 1 "$_notebook_marker" "NotebookEdit creates marker"

done_testing
