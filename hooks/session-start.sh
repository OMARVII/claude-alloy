#!/usr/bin/env bash
# Session Start Hook — Injects wiki context into session
# Runs as SessionStart hook
# Exit 0 = always allow

set -u

# Consume hook input from stdin (required by hook protocol)
cat > /dev/null

command -v jq &>/dev/null || exit 0

# Determine wiki directory based on project or global context
WIKI_DIR="${CLAUDE_PROJECT_DIR:+${CLAUDE_PROJECT_DIR}/.claude/wiki}"
WIKI_DIR="${WIKI_DIR:-${HOME}/.claude/wiki}"

# Opt-out marker: users can disable wiki injection entirely by creating
# ${PROJ_DIR}/.claude/wiki.no-inject (or ~/.claude/wiki.no-inject for global).
PROJ_DIR="${CLAUDE_PROJECT_DIR:-${HOME}}"
if [ -e "${PROJ_DIR}/.claude/wiki.no-inject" ] || [ -e "${HOME}/.claude/wiki.no-inject" ]; then
    exit 0
fi

# If no wiki directory exists, nothing to inject
if [ ! -d "$WIKI_DIR" ] || [ ! -f "$WIKI_DIR/index.md" ]; then
    exit 0
fi

# Concatenate non-stub .md files into one string
WIKI_CONTENT=""
for f in "$WIKI_DIR"/*.md; do
    [ -f "$f" ] || continue
    CONTENT=$(cat "$f" 2>/dev/null) || continue
    # Skip files that only contain template markers (no real content)
    STRIPPED=$(echo "$CONTENT" | grep -v '<!-- Updated automatically -->' | grep -v '^#' | grep -v '^_' | grep -v '^$' | grep -v '^---$' | grep -v '^\[' | grep -v '^|' | tr -d '[:space:]')
    if [ -z "$STRIPPED" ]; then
        continue
    fi
    WIKI_CONTENT="${WIKI_CONTENT}${CONTENT}
---
"
done

# Skip injection if no real content found
if [ -z "$WIKI_CONTENT" ]; then
    exit 0
fi

# Cap at 2KB (2048 chars), truncate at last newline.
# Wiki files are concatenated top-to-bottom — trimming from the bottom preserves
# the index.md header + earliest entries (which are assumed most-recent by wiki-update convention).
MAX_LEN=2048
if [ "${#WIKI_CONTENT}" -gt "$MAX_LEN" ]; then
    WIKI_CONTENT="${WIKI_CONTENT:0:$MAX_LEN}"
    # Truncate at last newline to avoid mid-line cut
    WIKI_CONTENT="${WIKI_CONTENT%$'\n'*}"
    WIKI_CONTENT="${WIKI_CONTENT}
[Wiki truncated — run /wiki-update to clean up]"
fi

# Output additionalContext via hookSpecificOutput
jq -n --arg ctx "PROJECT WIKI:
${WIKI_CONTENT}" \
    '{"hookSpecificOutput": {"additionalContext": $ctx}}'
