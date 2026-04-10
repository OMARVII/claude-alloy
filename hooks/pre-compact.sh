#!/usr/bin/env bash
# Pre-Compact Hook — Snapshots working state before context compaction
# Runs as PreCompact hook
# Exit 0 = always allow compaction

set -u

INPUT=$(cat)

STATE_DIR="${HOME}/.claude/.alloy-state"
mkdir -p "$STATE_DIR"

SNAPSHOT_FILE="${STATE_DIR}/pre-compact-snapshot.md"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

SOURCE="unknown"
if command -v jq &>/dev/null; then
    SOURCE=$(echo "$INPUT" | jq -r '.compaction_source // "unknown"' 2>/dev/null) || SOURCE="unknown"
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "n/a")
UNCOMMITTED=$(git status --short 2>/dev/null || echo "n/a")
RECENT_LOG=$(git log --oneline -5 2>/dev/null || echo "n/a")

cat > "$SNAPSHOT_FILE" << EOF
# Pre-Compaction Snapshot

**Timestamp:** ${TIMESTAMP}
**Compaction source:** ${SOURCE}
**Git branch:** ${BRANCH}

## Uncommitted files
${UNCOMMITTED:-none}

## Recent commits
${RECENT_LOG:-none}
EOF

exit 0
