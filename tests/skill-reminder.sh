#!/usr/bin/env bash
# Tests for hooks/skill-reminder.sh — precision threshold + delegation suppression.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/skill-reminder.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — skill-reminder hook exits early without it\n'
    exit 0
fi

TMP_HOME=$(mktemp -d /tmp/alloy-skillreminder-test.XXXXXX)
export HOME="$TMP_HOME"
STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

cleanup() {
    rm -rf "$TMP_HOME" 2>/dev/null
    return 0
}
trap cleanup EXIT

call_hook() {
    _tool=$1
    _sid=$2
    printf '{"tool_name":"%s","session_id":"%s"}' "$_tool" "$_sid" \
        | bash "$HOOK" 2>/dev/null
}

reminder_status() {
    _out=$1
    case "$_out" in
        *'Skill Reminder'*) printf 'yes' ;;
        *) printf 'no' ;;
    esac
}

# ---- threshold: routine direct work should not nudge too early --------------
SESSION_ID="skill-reminder-test-$$"

for _N in 1 2 3 4 5 6 7 8 9 10 11; do
    OUT=$(call_hook "Read" "$SESSION_ID")
    assert_eq "no" "$(reminder_status "$OUT")" "direct tool call ${_N}: reminder does NOT fire before threshold"
done

OUT=$(call_hook "Read" "$SESSION_ID")
assert_eq "yes" "$(reminder_status "$OUT")" "direct tool call 12: reminder fires at precision threshold"

MARKER="${STATE_DIR}/skill-reminded-${SESSION_ID}"
[ -f "$MARKER" ] && MARKER_OK="yes" || MARKER_OK="no"
assert_eq "yes" "$MARKER_OK" "threshold call: one-shot marker file is written"

OUT=$(call_hook "Read" "$SESSION_ID")
assert_eq "no" "$(reminder_status "$OUT")" "post-marker direct tool call: reminder does NOT re-fire"

# ---- env override: ALLOY_SKILL_REMINDER_WORK_THRESHOLD=2 fires at call 2 ----
SESSION_ID_ENV="skill-env-override-test-$$"
OUT_E1=$(ALLOY_SKILL_REMINDER_WORK_THRESHOLD=2 call_hook "Read" "$SESSION_ID_ENV")
assert_eq "no" "$(reminder_status "$OUT_E1")" "env override: call 1 below override threshold does NOT fire"
OUT_E2=$(ALLOY_SKILL_REMINDER_WORK_THRESHOLD=2 call_hook "Read" "$SESSION_ID_ENV")
assert_eq "yes" "$(reminder_status "$OUT_E2")" "env override: call 2 hits override threshold and fires"

# ---- delegation suppression: once an agent/skill was used, do not nag -------
DELEGATED_SESSION="skill-reminder-delegated-$$"
call_hook "Task" "$DELEGATED_SESSION" >/dev/null

for _N in 1 2 3 4 5 6 7 8 9 10 11 12; do
    OUT=$(call_hook "Read" "$DELEGATED_SESSION")
done
assert_eq "no" "$(reminder_status "$OUT")" "delegated session: reminder stays quiet after direct work"

done_testing
