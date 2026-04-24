#!/usr/bin/env bash
# Tests for hooks/branch-guard.sh — precedence ladder, docs allowlist, extractor fallbacks.
# Each test creates an isolated tempdir git repo, cd's into it, pipes a crafted
# JSON payload into the hook as a subprocess, then asserts on exit code and stderr.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

HOOK="${REPO_ROOT}/hooks/branch-guard.sh"

# ---- fixtures ---------------------------------------------------------------
# A disposable tempdir for every scenario. Caller cd's into it before running.
make_repo() {
    _raw=$(mktemp -d /tmp/alloy-branch-guard-test.XXXXXX)
    # macOS returns /tmp/... from mktemp but git rev-parse --show-toplevel
    # resolves it to /private/tmp/...  The hook's REPO_ROOT uses the resolved
    # form, so tests must pass resolved paths too or REL-prefix stripping misses.
    _dir=$(cd "$_raw" && pwd -P)
    git -C "$_dir" init -q -b main 2>/dev/null || {
        # older git lacks -b flag; fall back to init + rename
        git -C "$_dir" init -q
        git -C "$_dir" symbolic-ref HEAD refs/heads/main
    }
    git -C "$_dir" config user.email t@t
    git -C "$_dir" config user.name t
    printf 'seed\n' > "$_dir/seed.txt"
    git -C "$_dir" add seed.txt >/dev/null 2>&1
    git -C "$_dir" commit -qm init 2>/dev/null
    printf '%s' "$_dir"
}

# Simulate a populated remote: bare repo + fetch. This creates loose refs under
# .git/refs/remotes/origin/ which is what the hook's primary filesystem check
# looks for.
attach_remote() {
    _dir=$1
    _raw=$(mktemp -d /tmp/alloy-branch-guard-remote.XXXXXX)
    _bare=$(cd "$_raw" && pwd -P)
    git init --bare -q "$_bare"
    git -C "$_dir" remote add origin "$_bare"
    # Push current HEAD so the bare repo has something to fetch.
    git -C "$_dir" push -q origin HEAD:refs/heads/main 2>/dev/null \
        || git -C "$_dir" push -q origin HEAD:refs/heads/master 2>/dev/null
    git -C "$_dir" fetch -q origin
    printf '%s' "$_bare"
}

# Collapse loose refs into packed-refs to exercise the elif branch.
pack_remote_refs() {
    _dir=$1
    git -C "$_dir" pack-refs --all
    # Also delete the loose refs/remotes dir so only packed-refs remains.
    rm -rf "$_dir/.git/refs/remotes"
}

run_hook() {
    # $1 = cwd, $2 = json payload, rest = env assignments (e.g. "PATH=/bin")
    _cwd=$1; _json=$2; shift 2
    (
        cd "$_cwd" || exit 99
        if [ $# -gt 0 ]; then
            env "$@" bash "$HOOK" <<<"$_json" 2>/tmp/alloy-bg-stderr.$$
        else
            bash "$HOOK" <<<"$_json" 2>/tmp/alloy-bg-stderr.$$
        fi
    )
    _rc=$?
    cat /tmp/alloy-bg-stderr.$$ 1>&2
    rm -f /tmp/alloy-bg-stderr.$$
    return $_rc
}

capture_stderr() {
    # $1 = cwd, $2 = json payload, rest = env assignments. Echoes stderr.
    _cwd=$1; _json=$2; shift 2
    (
        cd "$_cwd" || exit 99
        if [ $# -gt 0 ]; then
            env "$@" bash "$HOOK" <<<"$_json" 2>&1 >/dev/null
        else
            bash "$HOOK" <<<"$_json" 2>&1 >/dev/null
        fi
    )
}

cleanup() {
    # Remove every tempdir ever allocated by the suite (covers macOS /private/tmp).
    rm -rf /tmp/alloy-branch-guard-test.* /tmp/alloy-branch-guard-remote.* \
           /tmp/alloy-branch-guard-nojq.* \
           /private/tmp/alloy-branch-guard-test.* /private/tmp/alloy-branch-guard-remote.* \
           /private/tmp/alloy-branch-guard-nojq.*
}
trap cleanup EXIT INT TERM

# ---- Test 1: no-remote silent pass ------------------------------------------
# Bare repo on main with no remote attached. Even on a blocked config, hook
# must exit 0 with no stderr (Piece D).
REPO1=$(make_repo)
STDERR1=$(capture_stderr "$REPO1" '{"tool_input":{"file_path":"'"$REPO1"'/foo.py"}}')
( cd "$REPO1" && bash "$HOOK" <<<'{"tool_input":{"file_path":"foo.py"}}' >/dev/null 2>&1 )
assert_exit 0 "$?" "no-remote repo: silent pass (Piece D)"
assert_eq "" "$STDERR1" "no-remote repo: stderr is empty"

# ---- Test 2: docs allowlist via jq (loose remote refs) ----------------------
# Repo with a real fetched remote, main branch, editing a .md file under docs/.
# Expected: exit 0, stderr contains "allowing docs".
REPO2=$(make_repo)
attach_remote "$REPO2" >/dev/null
mkdir -p "$REPO2/docs"
STDERR2=$(capture_stderr "$REPO2" '{"tool_input":{"file_path":"'"$REPO2"'/docs/SETUP.md"}}')
( cd "$REPO2" && bash "$HOOK" <<<'{"tool_input":{"file_path":"'"$REPO2"'/docs/SETUP.md"}}' >/dev/null 2>&1 )
assert_exit 0 "$?" "docs allowlist (jq): exit 0 on docs/SETUP.md"
case "$STDERR2" in
    *"allowing docs"*) assert_eq 1 1 "docs allowlist (jq): stderr contains 'allowing docs'" ;;
    *)                 assert_eq 1 0 "docs allowlist (jq): stderr contains 'allowing docs' (got: $STDERR2)" ;;
esac

# ---- Test 3: docs allowlist via python3 (jq removed from PATH) --------------
# Same payload as Test 2, but PATH scrubbed so jq is not discoverable. The
# python3 fallback must fire and yield the same exit 0 + warn.
REPO3=$(make_repo)
attach_remote "$REPO3" >/dev/null
mkdir -p "$REPO3/docs"
# Build a minimal bin dir by symlinking every real binary the hook uses EXCEPT
# jq, then use that dir alone as PATH. Filtering $PATH for "no jq" breaks on
# Ubuntu where bash and jq both live in /usr/bin — dropping /usr/bin also drops
# bash, making `#!/usr/bin/env bash` fail with "env: 'bash': No such file".
NOJQ_BIN=$(mktemp -d /tmp/alloy-branch-guard-nojq.XXXXXX)
for _tool in bash env python3 git grep cat printf sh sed awk tr mktemp rm ls cp mv chmod mkdir; do
    _real=$(command -v "$_tool" 2>/dev/null || true)
    if [ -n "$_real" ]; then
        ln -s "$_real" "$NOJQ_BIN/$_tool" 2>/dev/null || true
    fi
done
# Sanity: bash MUST be reachable via this PATH — otherwise the shebang fails.
if [ ! -x "$NOJQ_BIN/bash" ] || [ ! -x "$NOJQ_BIN/env" ]; then
    printf 'FATAL: could not build nojq PATH (bash or env missing)\n' >&2
    exit 1
fi
NOJQ_PATH=$NOJQ_BIN
STDERR3=$(capture_stderr "$REPO3" '{"tool_input":{"file_path":"'"$REPO3"'/docs/SETUP.md"}}' "PATH=$NOJQ_PATH")
( cd "$REPO3" && PATH="$NOJQ_PATH" bash "$HOOK" <<<'{"tool_input":{"file_path":"'"$REPO3"'/docs/SETUP.md"}}' >/dev/null 2>&1 )
assert_exit 0 "$?" "docs allowlist (python3 fallback, no jq): exit 0"
case "$STDERR3" in
    *"allowing docs"*) assert_eq 1 1 "docs allowlist (python3 fallback): stderr contains 'allowing docs'" ;;
    *)                 assert_eq 1 0 "docs allowlist (python3 fallback): stderr contains 'allowing docs' (got: $STDERR3)" ;;
esac

# ---- Test 4: camelCase filePath key via python3 extractor -------------------
# Confirms the `or ti.get("filePath")` branch in the python3 one-liner.
REPO4=$(make_repo)
attach_remote "$REPO4" >/dev/null
STDERR4=$(capture_stderr "$REPO4" '{"tool_input":{"filePath":"README.md"}}' "PATH=$NOJQ_PATH")
( cd "$REPO4" && PATH="$NOJQ_PATH" bash "$HOOK" <<<'{"tool_input":{"filePath":"README.md"}}' >/dev/null 2>&1 )
assert_exit 0 "$?" "camelCase filePath + python3: exit 0 (docs allowlist)"
case "$STDERR4" in
    *"allowing docs"*) assert_eq 1 1 "camelCase filePath: stderr contains 'allowing docs'" ;;
    *)                 assert_eq 1 0 "camelCase filePath: stderr contains 'allowing docs' (got: $STDERR4)" ;;
esac

# ---- Test 5: default block regression ---------------------------------------
# Main + remote + .py file + no env override + no marker → exit 2 + guidance.
REPO5=$(make_repo)
attach_remote "$REPO5" >/dev/null
STDERR5=$(capture_stderr "$REPO5" '{"tool_input":{"file_path":"'"$REPO5"'/src/app.py"}}')
( cd "$REPO5" && bash "$HOOK" <<<'{"tool_input":{"file_path":"'"$REPO5"'/src/app.py"}}' >/dev/null 2>&1 )
assert_exit 2 "$?" "default block: exit 2 on .py edit with remote"
case "$STDERR5" in
    *"git checkout -b"*) assert_eq 1 1 "default block: stderr contains 'git checkout -b'" ;;
    *)                   assert_eq 1 0 "default block: stderr contains 'git checkout -b' (got: $STDERR5)" ;;
esac

# ---- Test 6: extensionless root README (flint MEDIUM finding) ---------------
# Root-level README with no extension — the REL case-match must catch it.
REPO6=$(make_repo)
attach_remote "$REPO6" >/dev/null
STDERR6=$(capture_stderr "$REPO6" '{"tool_input":{"file_path":"'"$REPO6"'/README"}}')
( cd "$REPO6" && bash "$HOOK" <<<'{"tool_input":{"file_path":"'"$REPO6"'/README"}}' >/dev/null 2>&1 )
assert_exit 0 "$?" "extensionless root README: exit 0 (docs allowlist)"
case "$STDERR6" in
    *"allowing docs"*) assert_eq 1 1 "extensionless README: stderr contains 'allowing docs'" ;;
    *)                 assert_eq 1 0 "extensionless README: stderr contains 'allowing docs' (got: $STDERR6)" ;;
esac

# ---- Test 7: packed-refs path for remote detection --------------------------
# Collapse loose remote refs into .git/packed-refs and delete the loose dir.
# The elif branch in branch-guard.sh must still detect the remote → block
# applies for a .py file.
REPO7=$(make_repo)
attach_remote "$REPO7" >/dev/null
pack_remote_refs "$REPO7"
( cd "$REPO7" && bash "$HOOK" <<<'{"tool_input":{"file_path":"'"$REPO7"'/src/app.py"}}' >/dev/null 2>&1 )
assert_exit 2 "$?" "packed-refs remote detection: exit 2 on .py edit"

done_testing
