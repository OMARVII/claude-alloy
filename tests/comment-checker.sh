#!/usr/bin/env bash
# Tests for hooks/comment-checker.sh — AI slop detection + opt-in
# recoverable blocking via ALLOY_BLOCK_AI_SLOP.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — comment-checker requires jq\n'
    exit 0
fi

HOOK="${REPO_ROOT}/hooks/comment-checker.sh"
TMP_DIR=$(mktemp -d /tmp/alloy-comment-checker.XXXXXX)

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null
    return 0
}
trap cleanup EXIT

# Plant a slop-laden TypeScript file.
SLOP_FILE="${TMP_DIR}/slop.ts"
cat > "$SLOP_FILE" <<'TS'
// This function adds two numbers together.
function add(a: number, b: number): number {
    return a + b;
}
TS

# Plant a clean TypeScript file (no slop).
CLEAN_FILE="${TMP_DIR}/clean.ts"
cat > "$CLEAN_FILE" <<'TS'
function add(a: number, b: number): number {
    return a + b;
}
TS

make_input() {
    jq -nc --arg path "$1" '{"tool_input":{"file_path":$path}}'
}

# 1. Default behavior on slop: warn-only, no `decision:block`.
OUT_DEFAULT=$(make_input "$SLOP_FILE" | bash "$HOOK" 2>&1)
case "$OUT_DEFAULT" in
    *additionalContext*) _has_warn=1 ;;
    *) _has_warn=0 ;;
esac
assert_eq 1 "$_has_warn" "default: slop file produces additionalContext warning"

if printf '%s' "$OUT_DEFAULT" | jq -e '.decision // empty | length > 0' >/dev/null 2>&1; then
    _has_block=1
else
    _has_block=0
fi
assert_eq 0 "$_has_block" "default: slop file does NOT emit decision:block"

# 2. Opt-in ALLOY_BLOCK_AI_SLOP=1: recoverable block.
OUT_BLOCK=$(make_input "$SLOP_FILE" | ALLOY_BLOCK_AI_SLOP=1 bash "$HOOK" 2>&1)
_decision=$(printf '%s' "$OUT_BLOCK" | jq -r '.decision // empty' 2>/dev/null)
assert_eq "block" "$_decision" "opt-in: slop file emits decision:block"

_continue=$(printf '%s' "$OUT_BLOCK" | jq -r '.hookSpecificOutput.continueOnBlock // empty' 2>/dev/null)
assert_eq "true" "$_continue" "opt-in: hookSpecificOutput.continueOnBlock=true"

_reason=$(printf '%s' "$OUT_BLOCK" | jq -r '.reason // empty' 2>/dev/null)
case "$_reason" in
    *"AI slop comments detected"*) _reason_ok=1 ;;
    *) _reason_ok=0 ;;
esac
assert_eq 1 "$_reason_ok" "opt-in: reason field describes the slop"

# 3. Opt-in but no slop: hook exits silently (no decision, no warning).
OUT_CLEAN=$(make_input "$CLEAN_FILE" | ALLOY_BLOCK_AI_SLOP=1 bash "$HOOK" 2>&1)
if [ -z "$OUT_CLEAN" ]; then
    _silent=1
else
    _silent=0
fi
assert_eq 1 "$_silent" "opt-in: clean file produces no output"

# 4. Sanity: explicit ALLOY_BLOCK_AI_SLOP=0 behaves like default.
OUT_OFF=$(make_input "$SLOP_FILE" | ALLOY_BLOCK_AI_SLOP=0 bash "$HOOK" 2>&1)
if printf '%s' "$OUT_OFF" | jq -e '.decision // empty | length > 0' >/dev/null 2>&1; then
    _off_blocks=1
else
    _off_blocks=0
fi
assert_eq 0 "$_off_blocks" "ALLOY_BLOCK_AI_SLOP=0: still warn-only (no block)"

done_testing
