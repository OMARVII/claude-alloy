#!/usr/bin/env bash
set -u

# Precedence: git-repo-exists -> branch-is-main/master -> env ALLOY_BRANCH_GUARD=off (A)
#   -> no-remote-skip (D) -> marker .claude/branch-guard.off (B)
#   -> docs allowlist warn (E) -> env ALLOY_BRANCH_GUARD=warn (A) -> block (C)

INPUT=$(cat)

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$REPO_ROOT" ] && exit 0

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
[ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ] && exit 0

# Trust boundary: env vars are set by the user's own shell; this is a
# self-protection hook, not a security control.
GUARD="${ALLOY_BRANCH_GUARD:-block}"

# Piece A (off): silent bypass — checked before git/FS work for fastest exit
[ "$GUARD" = "off" ] && exit 0

# Piece D: scratch repo with no remote — silent pass (filesystem check, no subprocess)
HAS_REMOTE=0
if [ -d "$REPO_ROOT/.git/refs/remotes" ] && [ -n "$(ls -A "$REPO_ROOT/.git/refs/remotes" 2>/dev/null)" ]; then
    HAS_REMOTE=1
elif grep -q 'refs/remotes/' "$REPO_ROOT/.git/packed-refs" 2>/dev/null; then
    HAS_REMOTE=1
fi
[ "$HAS_REMOTE" = "0" ] && exit 0

# Piece B: repo-level marker file opt-out — silent pass
[ -f "$REPO_ROOT/.claude/branch-guard.off" ] && exit 0

# Extract file_path from hook stdin for Piece E (docs allowlist)
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")
elif command -v python3 >/dev/null 2>&1; then
    FILE_PATH=$(python3 -c 'import json,sys;d=json.load(sys.stdin);ti=d.get("tool_input",{});print(ti.get("file_path") or ti.get("filePath") or "")' <<< "$INPUT" 2>/dev/null)
fi

# Piece E: docs allowlist — warn and exit 0
if [ -n "$FILE_PATH" ]; then
    BASENAME="${FILE_PATH##*/}"
    IS_DOC=0
    case "$BASENAME" in
        *.md|*.txt) IS_DOC=1 ;;
    esac
    # Root-level README*, CHANGELOG*, LICENSE* (with or without extension)
    if [ "$IS_DOC" = "0" ]; then
        REL="${FILE_PATH#"$REPO_ROOT"/}"
        case "$REL" in
            README|README.*|CHANGELOG|CHANGELOG.*|LICENSE|LICENSE.*) IS_DOC=1 ;;
        esac
    fi
    if [ "$IS_DOC" = "1" ]; then
        echo "branch-guard: allowing docs edit on '$BRANCH' — see .claude/branch-guard.off to silence" >&2
        exit 0
    fi
fi

# Piece A (warn): emit notice, exit 0
if [ "$GUARD" = "warn" ]; then
    echo "branch-guard: warning — editing '$BRANCH'. Set ALLOY_BRANCH_GUARD=block to re-enforce." >&2
    exit 0
fi

# Piece C: default block
cat >&2 <<EOF
Cannot edit files on '$BRANCH' branch. To proceed:
  → git checkout -b feature/my-change       (recommended)
  → ALLOY_BRANCH_GUARD=warn                 (one-session bypass)

Permanent opt-out for this repo: touch .claude/branch-guard.off
EOF
exit 2
