#!/usr/bin/env bash
# Tests for hooks/agent-reminder.sh — one-shot reminder + SESSION_ID safety.
#
# Regression target: v1.6.5 and earlier reset the search-counter to 0 after
# firing the reminder, so every two grep/glob/web tool calls re-injected the
# [Agent Usage Reminder] block into context. v1.6.6 added a one-shot marker
# (${STATE_DIR}/agent-reminded-${SESSION_ID}). These tests pin both:
#   - Reminder fires only after sustained direct searching (default threshold 5)
#   - Reminder never fires again in the same session (one-shot marker)
#   - SESSION_ID sanitization (tr -cd 'a-zA-Z0-9_-') prevents the marker
#     from being written outside STATE_DIR.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/agent-reminder.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — agent-reminder hook exits early without it\n'
    exit 0
fi

# Sandbox HOME so the hook's STATE_DIR=${HOME}/.claude/.alloy-state lands in
# /tmp instead of polluting the user's real state.
TMP_HOME=$(mktemp -d /tmp/alloy-agentreminder-test.XXXXXX)
export HOME="$TMP_HOME"
STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

cleanup() {
    rm -rf "$TMP_HOME" 2>/dev/null
    return 0
}
trap cleanup EXIT

call_hook() {
    # $1 = tool_name, $2 = session_id. Emits stdout (used to assert reminder
    # fires) and exits with the hook's status (always 0 in practice).
    _tool=$1
    _sid=$2
    printf '{"tool_name":"%s","session_id":"%s"}' "$_tool" "$_sid" \
        | bash "$HOOK" 2>/dev/null
}

call_bash() {
    # $1 = bash command, $2 = session_id. Emits stdout. Used to verify the
    # bash-as-search fallback (grep/rg/ag/find/fd/git-grep/git-log).
    _cmd=$1
    _sid=$2
    jq -nc --arg c "$_cmd" --arg s "$_sid" \
        '{tool_name: "Bash", tool_input: {command: $c}, session_id: $s}' \
        | bash "$HOOK" 2>/dev/null
}

fifth_bash_output() {
    _cmd=$1
    _sid=$2
    call_bash "$_cmd" "$_sid" >/dev/null
    call_bash "$_cmd" "$_sid" >/dev/null
    call_bash "$_cmd" "$_sid" >/dev/null
    call_bash "$_cmd" "$_sid" >/dev/null
    call_bash "$_cmd" "$_sid"
}

reminder_status() {
    _out=$1
    case "$_out" in
        *'Agent Usage Reminder'*) printf 'yes' ;;
        *) printf 'no' ;;
    esac
}

# ---- one-shot: reminder fires on the 5th search call, then never again ----
SESSION_ID="reminder-test-$$"

# Calls 1-4 — direct searches are still local enough to avoid nudging.
OUT1=$(call_hook "Grep" "$SESSION_ID")
assert_eq "no" "$(reminder_status "$OUT1")" "first search call: reminder does NOT fire before threshold"

OUT2=$(call_hook "Grep" "$SESSION_ID")
assert_eq "no" "$(reminder_status "$OUT2")" "second search call: reminder does NOT fire before threshold"

OUT3=$(call_hook "Grep" "$SESSION_ID")
assert_eq "no" "$(reminder_status "$OUT3")" "third search call: reminder does NOT fire before threshold"

OUT4=$(call_hook "Grep" "$SESSION_ID")
assert_eq "no" "$(reminder_status "$OUT4")" "fourth search call: reminder does NOT fire before threshold"

# Call 5 — counter reaches threshold, reminder fires AND marker is written.
OUT5=$(call_hook "Grep" "$SESSION_ID")
assert_eq "yes" "$(reminder_status "$OUT5")" "fifth search call: reminder fires at threshold 5"

MARKER="${STATE_DIR}/agent-reminded-${SESSION_ID}"
[ -f "$MARKER" ] && MARKER_OK="yes" || MARKER_OK="no"
assert_eq "yes" "$MARKER_OK" "threshold search call: one-shot marker file is written"

# Calls 6, 7, 8, 9 — marker exists, the early-exit guard at the top of the hook
# returns before any output. stdout MUST be empty for all four.
for _N in 6 7 8 9; do
    OUTN=$(call_hook "Grep" "$SESSION_ID")
    assert_eq "" "$OUTN" "post-marker call ${_N}: reminder does NOT re-fire"
done

# ---- env override: ALLOY_AGENT_REMINDER_SEARCH_THRESHOLD=2 fires at call 2 ----
SESSION_ID_ENV="env-override-test-$$"
OUT_E1=$(ALLOY_AGENT_REMINDER_SEARCH_THRESHOLD=2 call_hook "Grep" "$SESSION_ID_ENV")
assert_eq "no" "$(reminder_status "$OUT_E1")" "env override: call 1 below override threshold does NOT fire"
OUT_E2=$(ALLOY_AGENT_REMINDER_SEARCH_THRESHOLD=2 call_hook "Grep" "$SESSION_ID_ENV")
assert_eq "yes" "$(reminder_status "$OUT_E2")" "env override: call 2 hits override threshold and fires"

# ---- traversal: ../evil session_id never escapes STATE_DIR ----------------
# The hook sanitizes via `tr -cd 'a-zA-Z0-9_-'`, so `../evil` collapses to
# `evil`. Marker file lands at ${STATE_DIR}/agent-reminded-evil and nothing
# is written above STATE_DIR.
EVIL_SESSION="../evil"
# Fifth call triggers marker creation.
call_hook "Grep" "$EVIL_SESSION" >/dev/null
call_hook "Grep" "$EVIL_SESSION" >/dev/null
call_hook "Grep" "$EVIL_SESSION" >/dev/null
call_hook "Grep" "$EVIL_SESSION" >/dev/null
call_hook "Grep" "$EVIL_SESSION" >/dev/null

# After sanitization, marker must be at agent-reminded-evil (not -../evil).
SANITIZED_MARKER="${STATE_DIR}/agent-reminded-evil"
[ -f "$SANITIZED_MARKER" ] && SAN_OK="yes" || SAN_OK="no"
assert_eq "yes" "$SAN_OK" "traversal: marker written under sanitized name (no '..' component)"

# Negative assertion — nothing escaped STATE_DIR. Anything named '..evil' or
# similar above STATE_DIR would indicate the sanitization missed.
ESCAPED=$(find "${HOME}/.claude" -maxdepth 3 -name '*evil*' -not -path "${STATE_DIR}/*" 2>/dev/null | wc -l | tr -d ' ')
assert_eq 0 "$ESCAPED" "traversal: no 'evil'-named files outside STATE_DIR"

# ---- bash-as-search fallback: when native Grep tool isn't loadable -----------
# Some Claude Code project configs don't expose the native Grep tool, forcing
# users to fall back to bash invocations. The reminder must fire on those too,
# so users in restricted-tool-registry projects still get the delegation nudge.

# Each case uses a fresh session ID so the one-shot marker doesn't suppress.

# Positive: bash grep counts as search → reminder fires after sustained search
SID_BG="bash-grep-$$"
OUT=$(fifth_bash_output "grep -rn 'pattern' src/" "$SID_BG")
assert_eq "yes" "$(reminder_status "$OUT")" "bash-grep: reminder fires on fifth 'grep ...' call"

# Positive: rg (ripgrep) counts as search
SID_RG="bash-rg-$$"
OUT=$(fifth_bash_output "rg 'TODO'" "$SID_RG")
assert_eq "yes" "$(reminder_status "$OUT")" "bash-rg: reminder fires on fifth 'rg ...'"

# Positive: find counts as search (file-name lookup pattern)
SID_FIND="bash-find-$$"
OUT=$(fifth_bash_output "find . -name '*.py'" "$SID_FIND")
assert_eq "yes" "$(reminder_status "$OUT")" "bash-find: reminder fires on fifth 'find -name ...'"

# Positive: git grep counts as search (second-token disambiguation)
SID_GG="bash-gg-$$"
OUT=$(fifth_bash_output "git grep 'pattern'" "$SID_GG")
assert_eq "yes" "$(reminder_status "$OUT")" "bash-git-grep: reminder fires on fifth search"

# Positive: git log -S/-G counts as search (history search)
SID_GL="bash-gl-$$"
OUT=$(fifth_bash_output "git log -S'foo'" "$SID_GL")
assert_eq "yes" "$(reminder_status "$OUT")" "bash-git-log: reminder fires on fifth history search"

# Negative: regular bash commands (cat, ls, echo, mv) MUST NOT fire
SID_NEG="bash-neg-$$"
OUT=$(call_bash "ls -la" "$SID_NEG")
assert_eq "no" "$(reminder_status "$OUT")" "bash-non-search: 'ls -la' does NOT fire reminder"

SID_NEG2="bash-neg2-$$"
OUT=$(call_bash "git status" "$SID_NEG2")
assert_eq "no" "$(reminder_status "$OUT")" "bash-non-search: 'git status' does NOT fire (not grep/log)"

# Negative: echo with grep-looking content doesn't false-positive on first token
SID_NEG3="bash-neg3-$$"
OUT=$(call_bash "echo 'rg is a tool'" "$SID_NEG3")
assert_eq "no" "$(reminder_status "$OUT")" "bash-non-search: 'echo' with 'rg' inside string does NOT fire (first-token only)"

done_testing
