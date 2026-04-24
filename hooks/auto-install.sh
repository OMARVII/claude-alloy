#!/usr/bin/env bash
# Auto-install hook — opt-in only.
# Auto-installing package manifests is a supply-chain RCE surface (typosquats,
# malicious lifecycle scripts, arbitrary code execution via pip build backends).
# Set ALLOY_AUTO_INSTALL=1 in your environment to enable. See SECURITY.md.
set -u

# Opt-in only: auto-install is a supply-chain RCE surface (typosquats, pip build backends).
# Set ALLOY_AUTO_INSTALL=1 in your environment to enable.
[ "${ALLOY_AUTO_INSTALL:-}" = "1" ] || exit 0

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

# Only install-relevant manifests should reach the guard + run path.
case "$FILE_PATH" in
    */package.json|*/requirements.txt|*/pyproject.toml) ;;
    *) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Thermal-runaway guard (v1.6.4): cooldown -> concurrency lock -> pgroup timeout.
# Prevents accumulation of orphaned `npm`/`pip` descendants on rapid edits.
# Keyed on $FILE_PATH (manifest) so package.json and requirements.txt in the
# same repo don't block each other.
# See THERMAL_RUNAWAY_FIX.md and CHANGELOG [1.6.4].
# ---------------------------------------------------------------------------
MAX_SEC=45
COOLDOWN_SEC=30

# Portable sha1 — macOS ships `shasum`, Ubuntu ships `sha1sum`. Try both.
_sha1() { (command -v shasum >/dev/null 2>&1 && shasum) || sha1sum; }
KEY=$(printf '%s' "$FILE_PATH" | _sha1 | awk '{print $1}')
# Never share state across manifests if hashing failed.
[ -z "$KEY" ] && exit 0

STATE_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
COOLDOWN_FILE="$STATE_BASE/claude-alloy-auto-install-$KEY.cooldown"
LOCK_DIR="$STATE_BASE/claude-alloy-auto-install-$KEY.d"

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
        echo "[alloy] auto-install: cooldown active (${COOLDOWN_SEC}s), skipping" >&2
        exit 0
    fi
fi

# Layer 2 — concurrency lock with stale-pid recovery
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[alloy] auto-install: another run active (pid=$OLD_PID), skipping" >&2
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
    # like npm/pip subprocesses that escape direct-child kill).
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

case "$FILE_PATH" in
    */package.json)
        if command -v npm &>/dev/null && [ -f "$FILE_PATH" ]; then
            DIR=$(dirname "$FILE_PATH")
            if (cd "$DIR" && run_with_timeout "$MAX_SEC" npm install --no-audit --no-fund --ignore-scripts >/dev/null 2>&1); then
                jq -n --arg msg "Dependencies installed from ${FILE_PATH} (lifecycle scripts skipped for safety — run 'npm rebuild' if needed)." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            else
                jq -n --arg msg "[ALLOY] npm install failed for ${FILE_PATH}. Check package.json." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            fi
        fi
        ;;
    */requirements.txt)
        if command -v pip &>/dev/null && [ -f "$FILE_PATH" ]; then
            DIR=$(dirname "$FILE_PATH")
            # Only auto-install if inside a virtual environment
            if [ -z "${VIRTUAL_ENV:-}" ] && [ ! -d "$DIR/.venv" ] && [ ! -d "$DIR/venv" ]; then
                jq -n --arg msg "Skipping pip install — no virtual environment detected. Activate a venv first or create one with: python -m venv .venv" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            elif (cd "$DIR" && run_with_timeout "$MAX_SEC" pip install -q --no-deps --only-binary=:all: -r "$(basename "$FILE_PATH")" >/dev/null 2>&1); then
                jq -n --arg msg "Python dependencies installed from ${FILE_PATH}." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            else
                jq -n --arg msg "[ALLOY] pip install failed for ${FILE_PATH}." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
            fi
        fi
        ;;
    */pyproject.toml)
        # Editable installs (pip install -e .) execute arbitrary Python via the
        # project's build backend (setup.py, hatchling hooks, etc). We refuse to
        # run them silently — surface a message and let the user decide.
        jq -n --arg msg "pip editable install skipped — run 'pip install -e .' manually if intended. Editable installs execute build-backend code." '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
        ;;
esac

exit 0
