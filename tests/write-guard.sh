#!/usr/bin/env bash
# Tests for hooks/write-guard.sh — path traversal rejection + existing-file block.
# Runs the hook as a subprocess with crafted JSON on stdin and asserts exit codes.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/write-guard.sh"

run_guard() {
    # $1 = file_path payload. Emits exit code on stdout.
    _path=$1
    printf '{"tool_input":{"file_path":"%s"}}' "$_path" \
        | bash "$HOOK" >/dev/null 2>&1
    printf '%s' "$?"
}

# ---- traversal matrix -------------------------------------------------------
assert_exit 0 "$(run_guard 'foo.txt')"                   "plain filename allowed"
assert_exit 2 "$(run_guard '../etc/passwd')"             "leading ../ blocked"
assert_exit 2 "$(run_guard 'foo/../bar')"                "mid-path ../ blocked"
assert_exit 2 "$(run_guard 'foo/..')"                    "trailing /.. blocked"
assert_exit 2 "$(run_guard '..')"                        "bare .. blocked"
assert_exit 0 "$(run_guard 'foo.txt.lock')"              "lock file allowed"
assert_exit 2 "$(run_guard 'path/with/../traversal')"    "mid-path traversal blocked"
assert_exit 0 "$(run_guard 'legitimate..name.txt')"      "double-dot inside filename allowed"

# ---- existing-file overwrite block ------------------------------------------
TMPFILE=$(mktemp /tmp/alloy-write-guard-test.XXXXXX)
[ -n "$TMPFILE" ] || { echo "mktemp failed" >&2; exit 1; }
printf 'existing content\n' > "$TMPFILE"

# ---- allowlist bypass: existing .lock file should still be allowed ---------
# The allowlist case-match in write-guard.sh runs BEFORE the -f existence check,
# meaning an existing non-empty .lock file (e.g. package-lock.json regen) must
# pass through cleanly. macOS mktemp has no --suffix; create-then-rename.
LOCKFILE="$(mktemp /tmp/alloy-write-guard-test.XXXXXX)"
[ -n "$LOCKFILE" ] || { echo "mktemp failed" >&2; exit 1; }
mv "$LOCKFILE" "${LOCKFILE}.lock"
LOCKFILE="${LOCKFILE}.lock"
printf 'existing lock content' > "$LOCKFILE"
trap 'rm -f "$TMPFILE" "$LOCKFILE"' EXIT

assert_exit 2 "$(run_guard "$TMPFILE")" "existing non-empty file blocks overwrite"
assert_exit 0 "$(run_guard "$LOCKFILE")" "existing .lock file allowed to overwrite (allowlist bypass)"

done_testing
