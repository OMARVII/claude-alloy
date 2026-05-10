#!/usr/bin/env bash
# Shared helper — atomic, hardened state-directory creation.
#
# Sourced by every alloy hook that writes to ~/.claude/.alloy-state. Replaces
# the older `mkdir -p && chmod 700` two-syscall pattern, which has a TOCTOU
# window where another process can briefly observe (or create) the directory
# at the default umask before chmod tightens it.
#
# `install -d -m 700` sets the mode in the same syscall as the create, closing
# that window. The symlink check above defends against a pre-planted attacker
# symlink — a hook that follows it would be writing into an attacker-controlled
# location with the agent's privileges.
#
# Usage:
#   . "$(dirname "$0")/_state-dir.sh"
#   alloy_ensure_state_dir "${HOME}/.claude/.alloy-state" || exit 0
#
# Returns 0 on success, 1 on hard failure. Hooks should treat failure as
# advisory (exit 0) since they are non-blocking by design — the goal is "do
# not create state on a hostile filesystem", not "abort the user's session".

# shellcheck disable=SC2148  # sourced, not executed

alloy_ensure_state_dir() {
    _dir=$1
    [ -n "$_dir" ] || return 1
    # Refuse if the path is a symlink — could redirect writes to /etc, /tmp/X, etc.
    if [ -L "$_dir" ]; then
        echo "[alloy] refusing to use state dir: $_dir is a symlink" >&2
        return 1
    fi
    # Refuse if the path exists but isn't a directory (regular file, FIFO, etc).
    if [ -e "$_dir" ] && [ ! -d "$_dir" ]; then
        echo "[alloy] refusing to use state dir: $_dir exists but is not a directory" >&2
        return 1
    fi
    # `install -d -m 700` is atomic: mode is set during creation, no TOCTOU
    # window. Available on macOS (BSD install) and Linux (GNU coreutils).
    if ! install -d -m 700 "$_dir" 2>/dev/null; then
        # Fallback for the rare environment without `install`. Best-effort:
        # mkdir -p then tighten with chmod. The window is tiny but exists.
        mkdir -p "$_dir" 2>/dev/null || return 1
        chmod 700 "$_dir" 2>/dev/null || return 1
    fi
    return 0
}
