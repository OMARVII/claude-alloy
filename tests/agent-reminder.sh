#!/usr/bin/env bash
# Tests for hooks/agent-reminder.sh — one-shot reminder + SESSION_ID safety.
#
# Regression target: v1.6.5 and earlier reset the search-counter to 0 after
# firing the reminder, so every two grep/glob/web tool calls re-injected the
# [Agent Usage Reminder] block into context. v1.6.6 added a one-shot marker
# (${STATE_DIR}/agent-reminded-${SESSION_ID}). These tests pin both:
#   - Reminder fires on the FIRST search call (threshold lowered from 2 in
#     v1.6.7's verification-pass fix-up — same-turn visibility for users)
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

# ---- one-shot: reminder fires on the 1st search call, then never again ----
SESSION_ID="reminder-test-$$"

# Call 1 — counter hits 1 (new threshold), reminder fires AND marker is written.
OUT1=$(call_hook "Grep" "$SESSION_ID")
case "$OUT1" in
    *'Agent Usage Reminder'*) FIRED1="yes" ;;
    *) FIRED1="no" ;;
esac
assert_eq "yes" "$FIRED1" "first search call: reminder fires immediately at threshold 1"

MARKER="${STATE_DIR}/agent-reminded-${SESSION_ID}"
[ -f "$MARKER" ] && MARKER_OK="yes" || MARKER_OK="no"
assert_eq "yes" "$MARKER_OK" "first search call: one-shot marker file is written"

# Calls 2, 3, 4, 5 — marker exists, the early-exit guard at the top of the hook
# returns before any output. stdout MUST be empty for all four.
for _N in 2 3 4 5; do
    OUTN=$(call_hook "Grep" "$SESSION_ID")
    assert_eq "" "$OUTN" "post-marker call ${_N}: reminder does NOT re-fire"
done

# ---- traversal: ../evil session_id never escapes STATE_DIR ----------------
# The hook sanitizes via `tr -cd 'a-zA-Z0-9_-'`, so `../evil` collapses to
# `evil`. Marker file lands at ${STATE_DIR}/agent-reminded-evil and nothing
# is written above STATE_DIR.
EVIL_SESSION="../evil"
# Single call now triggers marker creation (threshold lowered to 1 in v1.6.7).
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

# Positive: bash grep counts as search → reminder fires
SID_BG="bash-grep-$$"
OUT=$(call_bash "grep -rn 'pattern' src/" "$SID_BG")
case "$OUT" in
    *'Agent Usage Reminder'*) FIRED="yes" ;;
    *) FIRED="no" ;;
esac
assert_eq "yes" "$FIRED" "bash-grep: reminder fires on first 'grep ...' call"

# Positive: rg (ripgrep) counts as search
SID_RG="bash-rg-$$"
OUT=$(call_bash "rg 'TODO'" "$SID_RG")
case "$OUT" in
    *'Agent Usage Reminder'*) FIRED="yes" ;;
    *) FIRED="no" ;;
esac
assert_eq "yes" "$FIRED" "bash-rg: reminder fires on 'rg ...'"

# Positive: find counts as search (file-name lookup pattern)
SID_FIND="bash-find-$$"
OUT=$(call_bash "find . -name '*.py'" "$SID_FIND")
case "$OUT" in
    *'Agent Usage Reminder'*) FIRED="yes" ;;
    *) FIRED="no" ;;
esac
assert_eq "yes" "$FIRED" "bash-find: reminder fires on 'find -name ...'"

# Positive: git grep counts as search (second-token disambiguation)
SID_GG="bash-gg-$$"
OUT=$(call_bash "git grep 'pattern'" "$SID_GG")
case "$OUT" in
    *'Agent Usage Reminder'*) FIRED="yes" ;;
    *) FIRED="no" ;;
esac
assert_eq "yes" "$FIRED" "bash-git-grep: reminder fires"

# Positive: git log -S/-G counts as search (history search)
SID_GL="bash-gl-$$"
OUT=$(call_bash "git log -S'foo'" "$SID_GL")
case "$OUT" in
    *'Agent Usage Reminder'*) FIRED="yes" ;;
    *) FIRED="no" ;;
esac
assert_eq "yes" "$FIRED" "bash-git-log: reminder fires (history search)"

# Negative: regular bash commands (cat, ls, echo, mv) MUST NOT fire
SID_NEG="bash-neg-$$"
OUT=$(call_bash "ls -la" "$SID_NEG")
case "$OUT" in
    *'Agent Usage Reminder'*) FIRED="yes" ;;
    *) FIRED="no" ;;
esac
assert_eq "no" "$FIRED" "bash-non-search: 'ls -la' does NOT fire reminder"

SID_NEG2="bash-neg2-$$"
OUT=$(call_bash "git status" "$SID_NEG2")
case "$OUT" in
    *'Agent Usage Reminder'*) FIRED="yes" ;;
    *) FIRED="no" ;;
esac
assert_eq "no" "$FIRED" "bash-non-search: 'git status' does NOT fire (not grep/log)"

# Negative: echo with grep-looking content doesn't false-positive on first token
SID_NEG3="bash-neg3-$$"
OUT=$(call_bash "echo 'rg is a tool'" "$SID_NEG3")
case "$OUT" in
    *'Agent Usage Reminder'*) FIRED="yes" ;;
    *) FIRED="no" ;;
esac
assert_eq "no" "$FIRED" "bash-non-search: 'echo' with 'rg' inside string does NOT fire (first-token only)"

done_testing
