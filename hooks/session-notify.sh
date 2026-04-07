#!/usr/bin/env bash
set -u

# Consume hook input from stdin (required by hook protocol)
cat > /dev/null

PLATFORM=$(uname -s)

case "$PLATFORM" in
    Darwin)
        osascript -e 'display notification "Session complete. Check your results." with title "claude-alloy" sound name "Glass"' 2>/dev/null || true
        ;;
    Linux)
        if command -v notify-send &>/dev/null; then
            notify-send "claude-alloy" "Session complete. Check your results." 2>/dev/null || true
        fi
        ;;
esac

exit 0
