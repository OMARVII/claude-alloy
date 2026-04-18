#!/usr/bin/env bash
# Session Notify Hook — Desktop, Slack, and Discord notifications
# Runs as Stop hook (async)
# Exit 0 = always allow

set -u

# Consume hook input from stdin (required by hook protocol)
cat > /dev/null

CONFIG_FILE="${HOME}/.claude/.alloy-state/notify-config.json"

# Defaults: desktop on, webhooks off
DESKTOP=true
SLACK_WEBHOOK=""
DISCORD_WEBHOOK=""

# Read config if it exists
if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    DESKTOP=$(jq -r '.desktop // true' "$CONFIG_FILE" 2>/dev/null) || DESKTOP=true
    SLACK_WEBHOOK=$(jq -r '.slack_webhook // ""' "$CONFIG_FILE" 2>/dev/null) || SLACK_WEBHOOK=""
    DISCORD_WEBHOOK=$(jq -r '.discord_webhook // ""' "$CONFIG_FILE" 2>/dev/null) || DISCORD_WEBHOOK=""
fi

# Validate webhook URLs to prevent SSRF (e.g. 169.254.169.254 metadata endpoint).
case "$SLACK_WEBHOOK" in
    ""|https://hooks.slack.com/*) ;;
    *) echo "session-notify: rejecting non-Slack webhook URL: $SLACK_WEBHOOK" >&2; SLACK_WEBHOOK="" ;;
esac
case "$DISCORD_WEBHOOK" in
    ""|https://discord.com/api/webhooks/*|https://discordapp.com/api/webhooks/*) ;;
    *) echo "session-notify: rejecting non-Discord webhook URL: $DISCORD_WEBHOOK" >&2; DISCORD_WEBHOOK="" ;;
esac

# Desktop notification
if [ "$DESKTOP" = "true" ]; then
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
fi

# Slack notification
if [ -n "$SLACK_WEBHOOK" ]; then
    curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"text":"claude-alloy: Session complete. Check your results."}' \
        "$SLACK_WEBHOOK" 2>/dev/null || true
fi

# Discord notification
if [ -n "$DISCORD_WEBHOOK" ]; then
    curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"content":"claude-alloy: Session complete. Check your results."}' \
        "$DISCORD_WEBHOOK" 2>/dev/null || true
fi

exit 0
