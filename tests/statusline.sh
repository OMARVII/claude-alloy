#!/usr/bin/env bash
# Tests for hooks/statusline.sh — cost visibility + VERSION resolution.
# Pipes JSON into the hook as a subprocess, strips ANSI, and pattern-matches.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/statusline.sh"

# Minimal valid stdin payload — adjust per-test for cost field.
make_json() {
    # $1 = total_cost_usd numeric literal
    _cost=$1
    printf '{"model":{"display_name":"Opus 4.1"},"workspace":{"current_dir":"/tmp"},"session_id":"test","cost":{"total_cost_usd":%s}}' "$_cost"
}

contains() {
    # $1 = haystack, $2 = needle. Echo 1 if present, 0 otherwise.
    case "$1" in
        *"$2"*) printf '1' ;;
        *)      printf '0' ;;
    esac
}

# Literal-$ needles used below are intentionally single-quoted (not shell expansion).
# ---- Test 1: zero cost hides segment ----------------------------------------
# Proves: at cost=0, the awk gate (`cost > 0`) is FALSE → COST_SEG not built.
# Catches: gate being inverted or removed altogether.
OUT=$(make_json 0 | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" | strip_ansi)
# shellcheck disable=SC2016
assert_eq 0 "$(contains "$OUT" '$0.00')" "zero cost hides \$0.00 segment"

# ---- Test 2: non-zero cost shows segment (exact format) --------------------
# Exact-format assertion ($0.42 not just $) so a printf format regression
# (e.g. %.3f or %d) is caught, not just a "contains $" near-miss.
OUT=$(make_json 0.42 | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" | strip_ansi)
# shellcheck disable=SC2016
assert_eq 1 "$(contains "$OUT" '$0.42')" "non-zero cost renders \$0.42 segment (exact format)"

# ---- Test 2a: sub-penny cost exercises the awk gate boundary ---------------
# cost=0.001 is the canonical "gate is `cost > 0`, not `cost >= 0.01`" probe:
#   - With `cost > 0` (current):  gate TRUE  → segment built, printf %.2f → $0.00 shown.
#   - With `cost >= 0.01`:        gate FALSE → segment absent, $0.00 NOT shown.
# Asserting $0.00 IS present locks in the current contract: any non-zero cost,
# even sub-penny, shows the segment. Inverting or tightening the gate fails this.
OUT=$(make_json 0.001 | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" | strip_ansi)
# shellcheck disable=SC2016
assert_eq 1 "$(contains "$OUT" '$0.00')" "sub-penny cost (0.001) renders \$0.00 — gate is > 0"

# ---- Test 2b: half-penny cost rounds up to $0.01 ---------------------------
# cost=0.005: awk's printf "%.2f" rounds half-up → "0.01" on both BSD/GNU awk.
# Locks in both (a) segment visibility at 0.005 and (b) the %.2f rounding contract.
OUT=$(make_json 0.005 | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" | strip_ansi)
# shellcheck disable=SC2016
assert_eq 1 "$(contains "$OUT" '$0.01')" "half-penny cost (0.005) rounds up to \$0.01"

# ---- Test 3: VERSION resolves from CLAUDE_PLUGIN_ROOT/VERSION --------------
OUT=$(make_json 0 | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" | strip_ansi)
assert_eq 1 "$(contains "$OUT" '1.6.2')" "version reads from CLAUDE_PLUGIN_ROOT/VERSION"

# ---- Test 4: VERSION fallback to <script-dir>/../VERSION (CLAUDE_PLUGIN_ROOT unset) ----
# Unset CLAUDE_PLUGIN_ROOT so the hook must fall through the self-locating chain.
# hooks/ lives at repo-root/hooks, so SCRIPT_DIR/../VERSION (candidate #3) resolves
# to the real VERSION. Candidate #2 (SCRIPT_DIR/VERSION) does not exist for source
# checkouts, so candidate #3 is the one exercised here.
unset CLAUDE_PLUGIN_ROOT
OUT=$(make_json 0 | env -u CLAUDE_PLUGIN_ROOT bash "$HOOK" | strip_ansi)
assert_eq 1 "$(contains "$OUT" '1.6.2')" "SCRIPT_DIR/../VERSION fallback when CLAUDE_PLUGIN_ROOT unset"

# ---- Test 5: VERSION fallback to ~/.claude/.alloy-version (last-resort) ----
# Isolate candidate #4 by copying the hook alone into a temp dir where neither
# SCRIPT_DIR/VERSION nor SCRIPT_DIR/../VERSION exist, and overriding HOME so
# ~/.claude/.alloy-version points at our fixture. env -u CLAUDE_PLUGIN_ROOT
# removes candidate #1. That leaves candidate #4 as the only file the hook
# can find, proving the last-resort fallback is wired.
TMPHOME="$(mktemp -d)"
TMPRUN="$(mktemp -d)"
trap 'rm -rf "$TMPHOME" "$TMPRUN"' EXIT INT TERM
mkdir -p "$TMPHOME/.claude"
printf '9.9.9-testfallback' > "$TMPHOME/.claude/.alloy-version"
cp "$HOOK" "$TMPRUN/statusline.sh"
OUT5=$(make_json 0 | env -u CLAUDE_PLUGIN_ROOT HOME="$TMPHOME" bash "$TMPRUN/statusline.sh" 2>/dev/null | strip_ansi)
assert_eq 1 "$(contains "$OUT5" '9.9.9-testfallback')" "version fallback to ~/.claude/.alloy-version works"

done_testing
