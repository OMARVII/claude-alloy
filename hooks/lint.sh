#!/usr/bin/env bash
set -u

# Opt-in only: runs project-local npx binaries — see SECURITY.md
[ "${ALLOY_AUTO_LINT:-}" = "1" ] || exit 0

INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Reject path traversal — skip analysis (PostToolUse cannot block)
case "$FILE_PATH" in
    *../*|*/..*|*..)
        exit 0
        ;;
esac

# Only lint file types that linters typically handle
case "$FILE_PATH" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.html|*.vue|*.svelte)
        ;;
    *)
        exit 0
        ;;
esac

# Walk up to find the project root
PROJ_DIR="$FILE_PATH"
while [ "$PROJ_DIR" != "/" ]; do
    PROJ_DIR=$(dirname "$PROJ_DIR")
    [ -f "$PROJ_DIR/package.json" ] && break
done

if [ ! -f "$PROJ_DIR/package.json" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Thermal-runaway guard (v1.6.4): cooldown -> concurrency lock -> pgroup timeout.
# Prevents accumulation of orphaned `npx` descendants on rapid edits.
# See THERMAL_RUNAWAY_FIX.md and CHANGELOG [1.6.4].
# ---------------------------------------------------------------------------
MAX_SEC=20
COOLDOWN_SEC=30

# Portable sha1 — macOS ships `shasum`, Ubuntu ships `sha1sum`. Try both.
_sha1() { (command -v shasum >/dev/null 2>&1 && shasum) || sha1sum; }
KEY=$(printf '%s' "$PROJ_DIR" | _sha1 | awk '{print $1}')
# Never share state across projects if hashing failed.
[ -z "$KEY" ] && exit 0

STATE_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
COOLDOWN_FILE="$STATE_BASE/claude-alloy-lint-$KEY.cooldown"
LOCK_DIR="$STATE_BASE/claude-alloy-lint-$KEY.d"

# Reject symlink pre-creation (shared-/tmp hardening).
[ -L "$COOLDOWN_FILE" ] && exit 0
[ -L "$LOCK_DIR" ] && exit 0

# Layer 1 — cooldown
if [ -f "$COOLDOWN_FILE" ]; then
    # GNU stat -c is more common (Linux/CI); BSD stat -f fallback for macOS.
    # BSD `stat -f %m` on Linux exits 0 with garbage output — always try GNU first.
    LAST=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || stat -f %m "$COOLDOWN_FILE" 2>/dev/null || echo 0)
    # Defensive: if LAST isn't a plain integer (e.g. stat returned unexpected format),
    # treat as "very old" so cooldown doesn't trigger. Safe default: run the tool.
    case "$LAST" in
        ''|*[!0-9]*) LAST=0 ;;
    esac
    NOW=$(date +%s)
    if [ $((NOW - LAST)) -lt "$COOLDOWN_SEC" ]; then
        echo "[alloy] lint: cooldown active (${COOLDOWN_SEC}s), skipping" >&2
        exit 0
    fi
fi

# Layer 2 — concurrency lock with stale-pid recovery
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[alloy] lint: another run active (pid=$OLD_PID), skipping" >&2
        exit 0
    fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK_DIR/pid"

CHILD_PGID=""
# shellcheck disable=SC2329,SC2317  # invoked indirectly via trap EXIT INT TERM
cleanup() {
    # Kill the child's process group if we spawned one (captures descendants
    # like npx -> node -> eslint that escape direct-child kill).
    if [ -n "$CHILD_PGID" ]; then
        kill -- "-$CHILD_PGID" 2>/dev/null
        sleep 1
        kill -9 -- "-$CHILD_PGID" 2>/dev/null
    fi
    rm -rf "$LOCK_DIR"
    touch "$COOLDOWN_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Layer 3 — pgroup-aware timeout
# Prefer POSIX `timeout --kill-after` (GNU coreutils). Falls back to perl
# setpgid supervisor on stock macOS where `timeout` is absent.
run_with_timeout() {
    _sec=$1; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout --kill-after=5s "${_sec}s" "$@"
        return $?
    fi
    _pidfile=$(mktemp "${TMPDIR:-/tmp}/alloy-pgid.XXXXXX")
    perl -e '
        use POSIX qw(setpgid);
        my $sec = shift @ARGV;
        my $pidfile = shift @ARGV;
        my $pid = fork();
        die "fork failed: $!" unless defined $pid;
        if ($pid == 0) { setpgid(0, 0); exec { $ARGV[0] } @ARGV or exit 127; }
        setpgid($pid, $pid);
        if (open(my $fh, ">", $pidfile)) { print $fh $pid; close($fh); }
        $SIG{ALRM} = sub { kill "-TERM", $pid; sleep 2; kill "-KILL", $pid; exit 124; };
        alarm $sec;
        waitpid $pid, 0;
        exit($? >> 8);
    ' "$_sec" "$_pidfile" "$@"
    _rc=$?
    CHILD_PGID=$(cat "$_pidfile" 2>/dev/null || echo "")
    rm -f "$_pidfile"
    return $_rc
}

ERRORS=""

# Detect and run Biome
if [ -f "$PROJ_DIR/biome.json" ] || [ -f "$PROJ_DIR/biome.jsonc" ]; then
    OUTPUT=$(cd "$PROJ_DIR" && run_with_timeout "$MAX_SEC" npx --no-install @biomejs/biome check "$FILE_PATH" 2>&1) || true
    ERRORS=$(echo "$OUTPUT" | grep -E "^.+:[0-9]+:[0-9]+" | head -10)

# Detect and run ESLint
elif [ -f "$PROJ_DIR/.eslintrc" ] || [ -f "$PROJ_DIR/.eslintrc.js" ] || [ -f "$PROJ_DIR/.eslintrc.cjs" ] || [ -f "$PROJ_DIR/.eslintrc.json" ] || [ -f "$PROJ_DIR/.eslintrc.yml" ] || [ -f "$PROJ_DIR/eslint.config.js" ] || [ -f "$PROJ_DIR/eslint.config.mjs" ] || [ -f "$PROJ_DIR/eslint.config.cjs" ]; then
    OUTPUT=$(cd "$PROJ_DIR" && run_with_timeout "$MAX_SEC" npx --no-install eslint --no-warn-ignored "$FILE_PATH" 2>&1) || true
    ERRORS=$(echo "$OUTPUT" | grep -E "^.+:[0-9]+:[0-9]+" | head -10)

# Detect and run Prettier (check mode only)
elif [ -f "$PROJ_DIR/.prettierrc" ] || [ -f "$PROJ_DIR/.prettierrc.js" ] || [ -f "$PROJ_DIR/.prettierrc.json" ] || [ -f "$PROJ_DIR/.prettierrc.yml" ] || [ -f "$PROJ_DIR/.prettierrc.cjs" ] || [ -f "$PROJ_DIR/prettier.config.js" ] || [ -f "$PROJ_DIR/prettier.config.cjs" ]; then
    OUTPUT=$(cd "$PROJ_DIR" && run_with_timeout "$MAX_SEC" npx --no-install prettier --check "$FILE_PATH" 2>&1) || true
    if echo "$OUTPUT" | grep -q "Code style issues"; then
        ERRORS="Formatting issues detected in $FILE_PATH"
    fi
fi

if [ -n "$ERRORS" ]; then
    jq -n --arg msg "[Lint] Issues found: $ERRORS" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
fi

exit 0
