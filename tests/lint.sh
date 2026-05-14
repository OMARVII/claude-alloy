#!/usr/bin/env bash
# Tests for hooks/lint.sh — verifies updatedToolOutput summary emission.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — lint hook requires jq\n'
    exit 0
fi

HOOK="${REPO_ROOT}/hooks/lint.sh"
TMP_DIR=$(mktemp -d /tmp/alloy-lint.XXXXXX)

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null
    # Drop cooldown/lock files laid by the test runs (per-project SHA keys).
    # macOS uses TMPDIR; Linux uses /tmp — sweep both.
    for _base in "${XDG_RUNTIME_DIR:-}" "${TMPDIR:-/tmp}" "/tmp"; do
        [ -z "$_base" ] && continue
        find "$_base" -maxdepth 1 -name 'claude-alloy-lint-*' -newer "$REPO_ROOT/VERSION" \
            -exec rm -rf {} + 2>/dev/null || true
    done
    return 0
}
trap cleanup EXIT

# Build a project skeleton with eslint config so the hook takes the eslint
# branch. Stub `npx` on PATH so we never actually fetch the npm registry.
PROJ="${TMP_DIR}/proj"
mkdir -p "$PROJ"
printf '{"name":"x","version":"0.0.0"}\n' > "$PROJ/package.json"
printf 'export default [];\n' > "$PROJ/eslint.config.mjs"
TARGET="$PROJ/src.ts"
printf 'const x = 1;\n' > "$TARGET"

# Stub `npx` — emits a fake eslint "error" line then exits non-zero so the
# hook treats output like a real lint failure. Place stub dir FIRST in PATH.
STUB_DIR="${TMP_DIR}/bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/npx" <<'STUB'
#!/usr/bin/env bash
# Fake eslint output: one "<path>:<line>:<col> error" line + warning hint.
printf '%s:3:5  error  Unexpected console.log  no-console\n' "${4:-/tmp/x}"
printf '1 warning emitted\n'
exit 1
STUB
chmod +x "$STUB_DIR/npx"

INPUT=$(jq -nc --arg p "$TARGET" '{"tool_input":{"file_path":$p}}')

# 1. ERROR path: with stubbed npx producing path:line:col output, lint should
#    emit hookSpecificOutput.updatedToolOutput with "Lint: <N> error(s)..."
OUT_ERR=$(printf '%s' "$INPUT" | PATH="${STUB_DIR}:${PATH}" ALLOY_AUTO_LINT=1 CLAUDE_EFFORT=medium bash "$HOOK" 2>&1)

if printf '%s' "$OUT_ERR" | jq -e '.hookSpecificOutput.updatedToolOutput // empty | length > 0' >/dev/null 2>&1; then
    _has_summary=1
else
    _has_summary=0
fi
assert_eq 1 "$_has_summary" "error path: updatedToolOutput field is emitted"

UTO=$(printf '%s' "$OUT_ERR" | jq -r '.hookSpecificOutput.updatedToolOutput // empty')
case "$UTO" in
    "Lint: "*"error(s)"*) _err_shape=1 ;;
    *) _err_shape=0 ;;
esac
assert_eq 1 "$_err_shape" "error path: summary starts with 'Lint:' and mentions error(s)"

# additionalContext (detail) still present alongside the summary.
if printf '%s' "$OUT_ERR" | jq -e '.hookSpecificOutput.additionalContext // empty | length > 0' >/dev/null 2>&1; then
    _has_detail=1
else
    _has_detail=0
fi
assert_eq 1 "$_has_detail" "error path: additionalContext detail preserved"

# 2. CLEAN path: stub npx prints nothing matching path:line:col, exits 0.
# Use a SECOND project dir so the per-project cooldown file (laid by step 1)
# does not gate this invocation. Key is SHA-1 of project path → unique key.
cat > "$STUB_DIR/npx" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$STUB_DIR/npx"

PROJ2="${TMP_DIR}/proj2"
mkdir -p "$PROJ2"
printf '{"name":"x","version":"0.0.0"}\n' > "$PROJ2/package.json"
printf 'export default [];\n' > "$PROJ2/eslint.config.mjs"
TARGET2="$PROJ2/src.ts"
printf 'const x = 1;\n' > "$TARGET2"
INPUT2=$(jq -nc --arg p "$TARGET2" '{"tool_input":{"file_path":$p}}')

OUT_CLEAN=$(printf '%s' "$INPUT2" | PATH="${STUB_DIR}:${PATH}" ALLOY_AUTO_LINT=1 CLAUDE_EFFORT=medium bash "$HOOK" 2>&1)

UTO_CLEAN=$(printf '%s' "$OUT_CLEAN" | jq -r '.hookSpecificOutput.updatedToolOutput // empty' 2>/dev/null)
case "$UTO_CLEAN" in
    "Lint: clean"*) _clean_shape=1 ;;
    *) _clean_shape=0 ;;
esac
assert_eq 1 "$_clean_shape" "clean path: summary reads 'Lint: clean (...)'"

# 3. OPT-OUT: without ALLOY_AUTO_LINT=1, hook exits silently regardless.
# Use a third project dir to avoid cooldown interference.
PROJ3="${TMP_DIR}/proj3"
mkdir -p "$PROJ3"
printf '{"name":"x","version":"0.0.0"}\n' > "$PROJ3/package.json"
printf 'export default [];\n' > "$PROJ3/eslint.config.mjs"
TARGET3="$PROJ3/src.ts"
printf 'const x = 1;\n' > "$TARGET3"
INPUT3=$(jq -nc --arg p "$TARGET3" '{"tool_input":{"file_path":$p}}')

OUT_OFF=$(printf '%s' "$INPUT3" | PATH="${STUB_DIR}:${PATH}" CLAUDE_EFFORT=medium bash "$HOOK" 2>&1)
if [ -z "$OUT_OFF" ]; then
    _silent_default=1
else
    _silent_default=0
fi
assert_eq 1 "$_silent_default" "opt-out default: no ALLOY_AUTO_LINT → no output"

done_testing
