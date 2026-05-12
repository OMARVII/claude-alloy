#!/usr/bin/env bash
# Tests for hooks/{lint,typecheck,auto-install}.sh thermal-runaway guard (v1.6.4).
#
# Exercises: cooldown (1st run seeds, 2nd run fast-exits), live-pid lock rejection,
# stale-pid lock recovery, pgroup-aware timeout (including descendant kill), shasum
# fallback, XDG_RUNTIME_DIR preference, and symlink rejection.
#
# Portable to macOS bash 3.2 and Ubuntu CI. Uses `pgrep -f` (widely portable) not
# BSD-only `ps -o command=` and not `pgrep -fa` (BSD pgrep lacks `-a`). Timeout-test
# wait is 4s — longer than the supervisor's internal SIGTERM -> sleep 2 -> SIGKILL
# so straggler checks are reliable.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

LINT_HOOK="${REPO_ROOT}/hooks/lint.sh"
TYPECHECK_HOOK="${REPO_ROOT}/hooks/typecheck.sh"
INSTALL_HOOK="${REPO_ROOT}/hooks/auto-install.sh"

# Every test creates a tempdir. Accumulate them so one trap sweeps everything.
TEMPDIRS=""
add_tempdir() {
    _d=$1
    if [ -z "$TEMPDIRS" ]; then TEMPDIRS=$_d; else TEMPDIRS="$TEMPDIRS $_d"; fi
}

cleanup_all() {
    # Kill any stray sleep markers our tests may have spawned.
    pkill -f 'alloy-thermal-marker-' 2>/dev/null || true
    if [ -n "$TEMPDIRS" ]; then
        # shellcheck disable=SC2086  # word-splitting intended
        rm -rf $TEMPDIRS
    fi
    rm -rf /tmp/alloy-thermal-test-*
}
trap cleanup_all EXIT INT TERM

# ---- fixtures ---------------------------------------------------------------

# Make an isolated state dir so cooldown/lock files never collide across tests.
make_state_dir() {
    _d=$(mktemp -d "/tmp/alloy-thermal-test-state.XXXXXX")
    add_tempdir "$_d"
    printf '%s' "$_d"
}

# Build a project dir with the manifest files each hook looks for. Deep enough
# that the hooks' walk-up loops find the manifest regardless of the file passed.
make_project() {
    _p=$(mktemp -d "/tmp/alloy-thermal-test-proj.XXXXXX")
    add_tempdir "$_p"
    printf '{}' > "$_p/package.json"
    printf '{}' > "$_p/tsconfig.json"
    # Give lint.sh something to detect (biome is fine; content irrelevant).
    printf '{}' > "$_p/biome.json"
    printf '\n' > "$_p/sample.ts"
    printf '\n' > "$_p/requirements.txt"
    printf '%s' "$_p"
}

# Build a PATH-shim directory that stubs npx/npm/pip with a fast script.
# The script just exits 0 — used to exercise cooldown/lock paths without waiting.
make_fast_shim() {
    _d=$(mktemp -d "/tmp/alloy-thermal-test-shim.XXXXXX")
    add_tempdir "$_d"
    for _bin in npx npm pip; do
        cat > "$_d/$_bin" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
        chmod +x "$_d/$_bin"
    done
    printf '%s' "$_d"
}

# Build a PATH-shim that blocks in `sleep 120` with a unique argv[0] marker so
# the timeout test can assert both (a) the hook exits near MAX_SEC and (b) no
# descendant `sleep` survives (pgroup kill worked). `exec -a "$marker"` sets
# argv[0] portably (bash 3.2+), which pgrep -f will match. Passing the marker
# as a sleep arg doesn't work on BSD sleep (macOS) — it rejects extra args.
#
# Two-marker shim: the stub spawns a background grandchild with GRAND_MARKER,
# then execs a parent sleep with PARENT_MARKER. The grandchild inherits the
# pgroup; if the hook's timeout supervisor only kills the direct child, the
# grandchild survives — which is the bug this test detects. Both must be
# absent post-timeout to prove full pgroup kill.
make_blocking_shim() {
    _parent_marker=$1
    _grand_marker=$2
    _d=$(mktemp -d "/tmp/alloy-thermal-test-blockshim.XXXXXX")
    add_tempdir "$_d"
    for _bin in npx npm pip; do
        cat > "$_d/$_bin" <<SHIM
#!/usr/bin/env bash
# Blocking stub for thermal-runaway test (parent=$_parent_marker, grand=$_grand_marker).
# Spawn grandchild with distinct marker (inherits pgroup from parent shell).
# Parent blocks under its own marker. Both must die when the pgroup is killed.
bash -c "exec -a '$_grand_marker' sleep 120" &
exec -a "$_parent_marker" sleep 120
SHIM
        chmod +x "$_d/$_bin"
    done
    printf '%s' "$_d"
}

# Payload-builder: emits JSON Claude Code hooks expect on stdin.
mk_payload() {
    printf '{"tool_input":{"file_path":"%s"}}' "$1"
}

# Run a hook with a custom state dir and PATH. Captures exit code + stderr.
# Usage: run_hook <hook> <file_path> <state_dir> <extra_path> [env...]
run_hook() {
    _hook=$1; _fp=$2; _state=$3; _xpath=$4; shift 4
    _err=$(mktemp "/tmp/alloy-thermal-test-err.XXXXXX")
    add_tempdir "$_err"
    (
        cd /tmp || exit 99
        env \
            ALLOY_AUTO_LINT=1 \
            ALLOY_AUTO_INSTALL=1 \
            XDG_RUNTIME_DIR="$_state" \
            PATH="$_xpath:$PATH" \
            "$@" \
            bash "$_hook" <<<"$(mk_payload "$_fp")" 2>"$_err" >/dev/null
    )
    _rc=$?
    _STDERR=$(cat "$_err" 2>/dev/null || echo "")
    rm -f "$_err"
    export LAST_STDERR="$_STDERR"
    return $_rc
}

# Compute the KEY a hook will derive from a given string (matches hook logic).
key_for() {
    _s=$1
    _s1=$(printf '%s' "$_s" | (command -v shasum >/dev/null 2>&1 && shasum) 2>/dev/null | awk '{print $1}')
    if [ -z "$_s1" ]; then
        _s1=$(printf '%s' "$_s" | sha1sum 2>/dev/null | awk '{print $1}')
    fi
    printf '%s' "$_s1"
}

# ---- helper assertions ------------------------------------------------------

# stderr_contains "haystack" "needle" → 1 if present, 0 otherwise
stderr_contains() {
    case "$1" in
        *"$2"*) printf '1' ;;
        *)      printf '0' ;;
    esac
}

# ============================================================================
# Per-hook suite: cooldown, live-lock, stale-lock recovery, timeout+pgroup kill.
# ============================================================================

# --- lint.sh ---------------------------------------------------------------
PROJ_L=$(make_project)
STATE_L=$(make_state_dir)
SHIM_L=$(make_fast_shim)
KEY_L=$(key_for "$PROJ_L")

# Test 1: cooldown — 1st run exits 0, 2nd run within 30s fast-exits + prints notice
run_hook "$LINT_HOOK" "$PROJ_L/sample.ts" "$STATE_L" "$SHIM_L"
assert_exit 0 "$?" "lint: first run exits 0 (seeds cooldown)"

_T0=$(date +%s)
run_hook "$LINT_HOOK" "$PROJ_L/sample.ts" "$STATE_L" "$SHIM_L"
_rc_cd=$?
_T1=$(date +%s)
_DELTA_L=$((_T1 - _T0))
_CD_STDERR_L=$LAST_STDERR
assert_exit 0 "$_rc_cd" "lint: cooldown 2nd run exits 0"
[ "$_DELTA_L" -le 3 ] && _fast=1 || _fast=0
assert_eq 1 "$_fast" "lint: cooldown 2nd run is fast (<=3s, measured ${_DELTA_L}s)"
assert_eq 1 "$(stderr_contains "$_CD_STDERR_L" 'cooldown active')" "lint: cooldown emits 'cooldown active' notice"

# Test 2: live-pid lock — pre-create lock with current shell's pid → hook skips
STATE_L2=$(make_state_dir)
LOCK_DIR_L="$STATE_L2/claude-alloy-lint-$KEY_L.d"
mkdir "$LOCK_DIR_L"
echo $$ > "$LOCK_DIR_L/pid"
run_hook "$LINT_HOOK" "$PROJ_L/sample.ts" "$STATE_L2" "$SHIM_L"
_rc_live=$?
_LIVE_STDERR_L=$LAST_STDERR
assert_exit 0 "$_rc_live" "lint: live-pid lock → exit 0"
assert_eq 1 "$(stderr_contains "$_LIVE_STDERR_L" 'another run active')" "lint: live-pid lock emits 'another run active'"

# Test 3: stale-pid lock recovery — pre-create lock with a PID that is guaranteed dead
STATE_L3=$(make_state_dir)
LOCK_DIR_L3="$STATE_L3/claude-alloy-lint-$KEY_L.d"
mkdir "$LOCK_DIR_L3"
# Use an out-of-range PID: avoids PID-reuse race where a sleep-then-wait PID
# could be recycled by another process on a busy CI runner, causing the hook
# to incorrectly treat the lock as live (silently skipping the recovery path).
_DEAD_PID=99999999   # Out of range on all realistic kernels; guaranteed dead.
echo "$_DEAD_PID" > "$LOCK_DIR_L3/pid"
COOLDOWN_FILE_L3="$STATE_L3/claude-alloy-lint-$KEY_L.cooldown"
run_hook "$LINT_HOOK" "$PROJ_L/sample.ts" "$STATE_L3" "$SHIM_L"
_rc_stale=$?
assert_exit 0 "$_rc_stale" "lint: stale-pid lock → hook takes over (exit 0)"
# Cooldown file should now exist (proves the hook ran to completion, not skipped).
[ -f "$COOLDOWN_FILE_L3" ] && _ran=1 || _ran=0
assert_eq 1 "$_ran" "lint: stale-pid lock → hook ran (cooldown file written)"
# Second assertion proves the stale-lock-RECOVERY branch ran (not already-exists).
# Live-lock rejection exits early without creating the cooldown file.
[ -f "$COOLDOWN_FILE_L3" ] && _marker="yes" || _marker="no"
assert_eq "yes" "$_marker" "lint: stale-lock: recovery branch executed (cooldown file created)"

# Test 4: timeout + descendant kill (proves pgroup-wide kill, not just direct child)
STATE_L4=$(make_state_dir)
# Two distinct markers: parent execs under one, spawns grandchild under the other.
# High-resolution entropy prevents marker collisions across parallel test runs.
PARENT_MARKER_L="alloy-thermal-marker-lint-parent-$$-$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
GRAND_MARKER_L="alloy-thermal-marker-lint-grand-$$-$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
BLOCKSHIM_L=$(make_blocking_shim "$PARENT_MARKER_L" "$GRAND_MARKER_L")
_T0=$(date +%s)
run_hook "$LINT_HOOK" "$PROJ_L/sample.ts" "$STATE_L4" "$BLOCKSHIM_L"
_rc_to=$?
_T1=$(date +%s)
_ELAPSED_L=$((_T1 - _T0))
assert_exit 0 "$_rc_to" "lint: timeout path still exits 0 (PostToolUse always 0)"
# MAX_SEC=20 for lint; allow [18, 40] — broad upper bound for loaded CI runners.
[ "$_ELAPSED_L" -ge 18 ] && [ "$_ELAPSED_L" -le 40 ] && _in_bounds=1 || _in_bounds=0
assert_eq 1 "$_in_bounds" "lint: timeout elapsed in [18,40]s (measured ${_ELAPSED_L}s)"
# Wait 6s — longer than the supervisor's SIGTERM -> sleep 2 -> SIGKILL plus
# a 2s reap margin. Previously 4s; on loaded macOS runners the parent shim
# and its grandchild sleep would occasionally still surface in `pgrep -f`
# 4s after SIGKILL because the kernel had not yet flushed their cmdline
# entries from /proc-style scans. Observed pattern: 46/47 once, then 47/47
# without a code change (steel session memory 2026-05-08). Bumping the
# reap window to 6s closes the race without slowing the green path
# meaningfully (~6s total added across this and the two analogous timeout
# blocks below — typecheck (~line 306) and auto-install (~line 375)).
sleep 6
_PARENT_STRAG_L=$(pgrep -f "$PARENT_MARKER_L" 2>/dev/null || true)
_GRAND_STRAG_L=$(pgrep -f "$GRAND_MARKER_L" 2>/dev/null || true)
assert_eq "" "$_PARENT_STRAG_L" "lint: timeout: parent marker killed"
assert_eq "" "$_GRAND_STRAG_L" "lint: timeout: grandchild marker killed (proves pgroup kill)"

# --- typecheck.sh ----------------------------------------------------------
PROJ_T=$(make_project)
STATE_T=$(make_state_dir)
SHIM_T=$(make_fast_shim)
KEY_T=$(key_for "$PROJ_T")

# Test 5: cooldown
run_hook "$TYPECHECK_HOOK" "$PROJ_T/sample.ts" "$STATE_T" "$SHIM_T"
assert_exit 0 "$?" "typecheck: first run exits 0 (seeds cooldown)"

_T0=$(date +%s)
run_hook "$TYPECHECK_HOOK" "$PROJ_T/sample.ts" "$STATE_T" "$SHIM_T"
_rc_cd_t=$?
_T1=$(date +%s)
_DELTA_T=$((_T1 - _T0))
_CD_STDERR_T=$LAST_STDERR
assert_exit 0 "$_rc_cd_t" "typecheck: cooldown 2nd run exits 0"
[ "$_DELTA_T" -le 3 ] && _fast=1 || _fast=0
assert_eq 1 "$_fast" "typecheck: cooldown 2nd run is fast (<=3s, measured ${_DELTA_T}s)"
assert_eq 1 "$(stderr_contains "$_CD_STDERR_T" 'cooldown active')" "typecheck: cooldown emits 'cooldown active' notice"

# Test 6: live-pid lock
STATE_T2=$(make_state_dir)
LOCK_DIR_T="$STATE_T2/claude-alloy-typecheck-$KEY_T.d"
mkdir "$LOCK_DIR_T"
echo $$ > "$LOCK_DIR_T/pid"
run_hook "$TYPECHECK_HOOK" "$PROJ_T/sample.ts" "$STATE_T2" "$SHIM_T"
_rc_live_t=$?
_LIVE_STDERR_T=$LAST_STDERR
assert_exit 0 "$_rc_live_t" "typecheck: live-pid lock → exit 0"
assert_eq 1 "$(stderr_contains "$_LIVE_STDERR_T" 'another run active')" "typecheck: live-pid lock emits 'another run active'"

# Test 7: stale-pid lock recovery — use guaranteed-dead out-of-range PID
STATE_T3=$(make_state_dir)
LOCK_DIR_T3="$STATE_T3/claude-alloy-typecheck-$KEY_T.d"
mkdir "$LOCK_DIR_T3"
_DEAD_PID=99999999   # Out of range on all realistic kernels; guaranteed dead.
echo "$_DEAD_PID" > "$LOCK_DIR_T3/pid"
COOLDOWN_FILE_T3="$STATE_T3/claude-alloy-typecheck-$KEY_T.cooldown"
run_hook "$TYPECHECK_HOOK" "$PROJ_T/sample.ts" "$STATE_T3" "$SHIM_T"
_rc_stale_t=$?
assert_exit 0 "$_rc_stale_t" "typecheck: stale-pid lock → hook takes over (exit 0)"
[ -f "$COOLDOWN_FILE_T3" ] && _ran=1 || _ran=0
assert_eq 1 "$_ran" "typecheck: stale-pid lock → hook ran (cooldown file written)"
[ -f "$COOLDOWN_FILE_T3" ] && _marker="yes" || _marker="no"
assert_eq "yes" "$_marker" "typecheck: stale-lock: recovery branch executed (cooldown file created)"

# Test 8: timeout + descendant kill (proves pgroup-wide kill)
STATE_T4=$(make_state_dir)
PARENT_MARKER_T="alloy-thermal-marker-typecheck-parent-$$-$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
GRAND_MARKER_T="alloy-thermal-marker-typecheck-grand-$$-$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
BLOCKSHIM_T=$(make_blocking_shim "$PARENT_MARKER_T" "$GRAND_MARKER_T")
_T0=$(date +%s)
run_hook "$TYPECHECK_HOOK" "$PROJ_T/sample.ts" "$STATE_T4" "$BLOCKSHIM_T"
_rc_to_t=$?
_T1=$(date +%s)
_ELAPSED_T=$((_T1 - _T0))
assert_exit 0 "$_rc_to_t" "typecheck: timeout path still exits 0"
# MAX_SEC=25 for typecheck; allow [23, 45].
[ "$_ELAPSED_T" -ge 23 ] && [ "$_ELAPSED_T" -le 45 ] && _in_bounds=1 || _in_bounds=0
assert_eq 1 "$_in_bounds" "typecheck: timeout elapsed in [23,45]s (measured ${_ELAPSED_T}s)"
# Reap-window guard: see lint-block comment near line 235 for rationale.
sleep 6
_PARENT_STRAG_T=$(pgrep -f "$PARENT_MARKER_T" 2>/dev/null || true)
_GRAND_STRAG_T=$(pgrep -f "$GRAND_MARKER_T" 2>/dev/null || true)
assert_eq "" "$_PARENT_STRAG_T" "typecheck: timeout: parent marker killed"
assert_eq "" "$_GRAND_STRAG_T" "typecheck: timeout: grandchild marker killed (proves pgroup kill)"

# --- auto-install.sh --------------------------------------------------------
PROJ_I=$(make_project)
STATE_I=$(make_state_dir)
SHIM_I=$(make_fast_shim)
# auto-install keys on $FILE_PATH (the manifest), not $PROJ_DIR.
MANIFEST_I="$PROJ_I/package.json"
KEY_I=$(key_for "$MANIFEST_I")

# Test 9: cooldown
run_hook "$INSTALL_HOOK" "$MANIFEST_I" "$STATE_I" "$SHIM_I"
assert_exit 0 "$?" "auto-install: first run exits 0 (seeds cooldown)"

_T0=$(date +%s)
run_hook "$INSTALL_HOOK" "$MANIFEST_I" "$STATE_I" "$SHIM_I"
_rc_cd_i=$?
_T1=$(date +%s)
_DELTA_I=$((_T1 - _T0))
_CD_STDERR_I=$LAST_STDERR
assert_exit 0 "$_rc_cd_i" "auto-install: cooldown 2nd run exits 0"
[ "$_DELTA_I" -le 3 ] && _fast=1 || _fast=0
assert_eq 1 "$_fast" "auto-install: cooldown 2nd run is fast (<=3s, measured ${_DELTA_I}s)"
assert_eq 1 "$(stderr_contains "$_CD_STDERR_I" 'cooldown active')" "auto-install: cooldown emits 'cooldown active' notice"

# Test 10: live-pid lock
STATE_I2=$(make_state_dir)
LOCK_DIR_I="$STATE_I2/claude-alloy-auto-install-$KEY_I.d"
mkdir "$LOCK_DIR_I"
echo $$ > "$LOCK_DIR_I/pid"
run_hook "$INSTALL_HOOK" "$MANIFEST_I" "$STATE_I2" "$SHIM_I"
_rc_live_i=$?
_LIVE_STDERR_I=$LAST_STDERR
assert_exit 0 "$_rc_live_i" "auto-install: live-pid lock → exit 0"
assert_eq 1 "$(stderr_contains "$_LIVE_STDERR_I" 'another run active')" "auto-install: live-pid lock emits 'another run active'"

# Test 11: stale-pid lock recovery — use guaranteed-dead out-of-range PID
STATE_I3=$(make_state_dir)
LOCK_DIR_I3="$STATE_I3/claude-alloy-auto-install-$KEY_I.d"
mkdir "$LOCK_DIR_I3"
_DEAD_PID=99999999   # Out of range on all realistic kernels; guaranteed dead.
echo "$_DEAD_PID" > "$LOCK_DIR_I3/pid"
COOLDOWN_FILE_I3="$STATE_I3/claude-alloy-auto-install-$KEY_I.cooldown"
run_hook "$INSTALL_HOOK" "$MANIFEST_I" "$STATE_I3" "$SHIM_I"
_rc_stale_i=$?
assert_exit 0 "$_rc_stale_i" "auto-install: stale-pid lock → hook takes over (exit 0)"
[ -f "$COOLDOWN_FILE_I3" ] && _ran=1 || _ran=0
assert_eq 1 "$_ran" "auto-install: stale-pid lock → hook ran (cooldown file written)"
[ -f "$COOLDOWN_FILE_I3" ] && _marker="yes" || _marker="no"
assert_eq "yes" "$_marker" "auto-install: stale-lock: recovery branch executed (cooldown file created)"

# Test 12: timeout + descendant kill (auto-install has MAX_SEC=45)
STATE_I4=$(make_state_dir)
PARENT_MARKER_I="alloy-thermal-marker-install-parent-$$-$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
GRAND_MARKER_I="alloy-thermal-marker-install-grand-$$-$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
BLOCKSHIM_I=$(make_blocking_shim "$PARENT_MARKER_I" "$GRAND_MARKER_I")
_T0=$(date +%s)
run_hook "$INSTALL_HOOK" "$MANIFEST_I" "$STATE_I4" "$BLOCKSHIM_I"
_rc_to_i=$?
_T1=$(date +%s)
_ELAPSED_I=$((_T1 - _T0))
assert_exit 0 "$_rc_to_i" "auto-install: timeout path still exits 0"
# MAX_SEC=45 for auto-install; allow [43, 65].
[ "$_ELAPSED_I" -ge 43 ] && [ "$_ELAPSED_I" -le 65 ] && _in_bounds=1 || _in_bounds=0
assert_eq 1 "$_in_bounds" "auto-install: timeout elapsed in [43,65]s (measured ${_ELAPSED_I}s)"
# Reap-window guard: see lint-block comment near line 235 for rationale.
sleep 6
_PARENT_STRAG_I=$(pgrep -f "$PARENT_MARKER_I" 2>/dev/null || true)
_GRAND_STRAG_I=$(pgrep -f "$GRAND_MARKER_I" 2>/dev/null || true)
assert_eq "" "$_PARENT_STRAG_I" "auto-install: timeout: parent marker killed"
assert_eq "" "$_GRAND_STRAG_I" "auto-install: timeout: grandchild marker killed (proves pgroup kill)"

# ============================================================================
# Cross-cutting assertions (one per scenario — lint is the representative hook).
# ============================================================================

# Test 13: shasum fallback — put a broken `shasum` wrapper on PATH and verify
# the hook still derives a non-empty KEY (via sha1sum) and runs to completion.
PROJ_S=$(make_project)
STATE_S=$(make_state_dir)
SHIM_S=$(make_fast_shim)
NOSHASUM_DIR=$(mktemp -d "/tmp/alloy-thermal-test-noshasum.XXXXXX")
add_tempdir "$NOSHASUM_DIR"
cat > "$NOSHASUM_DIR/shasum" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$NOSHASUM_DIR/shasum"
# Prepend NOSHASUM_DIR so `command -v shasum` sees it, but its `shasum >/dev/null` fails,
# triggering the `|| sha1sum` fallback inside the hook. On machines without `sha1sum`
# at all (macOS < 13), this test would simply exit 0 via [ -z "$KEY" ] guard, which
# is still a valid outcome (no state poisoning).
run_hook "$LINT_HOOK" "$PROJ_S/sample.ts" "$STATE_S" "$NOSHASUM_DIR:$SHIM_S"
_rc_sh=$?
assert_exit 0 "$_rc_sh" "shasum-fallback: lint exits 0 with broken shasum"
# If sha1sum exists (typical Ubuntu/macOS 13+), cooldown file should land with a
# non-empty KEY suffix. If not, we just assert exit 0 above (KEY-empty path).
if command -v sha1sum >/dev/null 2>&1; then
    _KEY_VIA_SHA1SUM=$(printf '%s' "$PROJ_S" | sha1sum | awk '{print $1}')
    _CD_S="$STATE_S/claude-alloy-lint-$_KEY_VIA_SHA1SUM.cooldown"
    [ -f "$_CD_S" ] && _fallback_ok=1 || _fallback_ok=0
    assert_eq 1 "$_fallback_ok" "shasum-fallback: sha1sum-derived cooldown file exists"
fi

# Test 14: XDG_RUNTIME_DIR preference — cooldown/lock land in XDG_RUNTIME_DIR,
# not in /tmp. We already use XDG_RUNTIME_DIR for all tests above via run_hook;
# this test makes the invariant explicit and asserts a sibling /tmp file absent.
PROJ_X=$(make_project)
STATE_X=$(make_state_dir)
SHIM_X=$(make_fast_shim)
KEY_X=$(key_for "$PROJ_X")
run_hook "$LINT_HOOK" "$PROJ_X/sample.ts" "$STATE_X" "$SHIM_X"
_rc_x=$?
assert_exit 0 "$_rc_x" "xdg-pref: lint exits 0 with XDG_RUNTIME_DIR set"
_CD_X="$STATE_X/claude-alloy-lint-$KEY_X.cooldown"
[ -f "$_CD_X" ] && _in_xdg=1 || _in_xdg=0
assert_eq 1 "$_in_xdg" "xdg-pref: cooldown landed in XDG_RUNTIME_DIR (not /tmp)"
# Sibling /tmp file should NOT exist (we never wrote there).
[ -f "/tmp/claude-alloy-lint-$KEY_X.cooldown" ] && _tmp_poisoned=1 || _tmp_poisoned=0
assert_eq 0 "$_tmp_poisoned" "xdg-pref: no sibling cooldown file leaked to /tmp"

# Test 15: symlink rejection — pre-create $COOLDOWN_FILE as a symlink → hook
# must exit 0 WITHOUT running the external tool (cooldown file stays a symlink).
PROJ_Y=$(make_project)
STATE_Y=$(make_state_dir)
SHIM_Y=$(make_fast_shim)
KEY_Y=$(key_for "$PROJ_Y")
CD_Y="$STATE_Y/claude-alloy-lint-$KEY_Y.cooldown"
ln -s /dev/null "$CD_Y"
run_hook "$LINT_HOOK" "$PROJ_Y/sample.ts" "$STATE_Y" "$SHIM_Y"
_rc_y=$?
assert_exit 0 "$_rc_y" "symlink-reject: lint exits 0 with cooldown as symlink"
# Cooldown file must still be a symlink (not rewritten by `touch` at cleanup).
[ -L "$CD_Y" ] && _still_symlink=1 || _still_symlink=0
assert_eq 1 "$_still_symlink" "symlink-reject: cooldown file remained a symlink (no overwrite)"
# Lock dir must NOT have been created (hook exited before Layer 2).
LOCK_Y="$STATE_Y/claude-alloy-lint-$KEY_Y.d"
[ -d "$LOCK_Y" ] && _lock_created=1 || _lock_created=0
assert_eq 0 "$_lock_created" "symlink-reject: lock dir never created (guard fired pre-lock)"

done_testing
