#!/usr/bin/env bash
set -u

# Consume hook input from stdin (required by hook protocol)
cat > /dev/null

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    echo "Cannot edit files on '$BRANCH' branch. Create a feature branch first: git checkout -b feature/my-change" >&2
    exit 2
fi

exit 0
