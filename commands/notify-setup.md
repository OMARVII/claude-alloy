---
description: "Configure notification settings for session completion alerts. Supports desktop, Slack, and Discord."
---

# Notification Setup

Configure how claude-alloy notifies you when sessions or tasks complete.

## Steps

1. Ensure the alloy state directory exists atomically: `install -d -m 700 ~/.claude/.alloy-state` — matches the convention used by `hooks/session-notify.sh` and other state-writing hooks. (`install -d -m` sets the mode in the same syscall, avoiding the `mkdir && chmod` TOCTOU window.)
2. Read current config from `~/.claude/.alloy-state/notify-config.json` (treat as empty object if the file doesn't exist yet)
3. Ask the user what they want to configure:
   - Desktop notifications (on/off, default: on)
   - Slack webhook URL
   - Discord webhook URL
4. Write updated config with restrictive mode — Slack and Discord webhook URLs are bearer credentials (anyone holding the URL can post to the channel), so the file MUST NOT be world-readable. Use:
   ```bash
   ( umask 077 && jq -n --argjson desktop "$DESKTOP" --arg slack "$SLACK_URL" --arg discord "$DISCORD_URL" \
       '{desktop: $desktop, slack_webhook: $slack, discord_webhook: $discord}' \
       > ~/.claude/.alloy-state/notify-config.json ) \
     && chmod 600 ~/.claude/.alloy-state/notify-config.json
   ```
   The `umask 077` subshell guarantees the file is created mode 600 even on systems where the user's default umask is 022; the explicit `chmod 600` is a belt-and-suspenders fix for the case where the file already existed with looser permissions.

## Config Format
```json
{
  "desktop": true,
  "slack_webhook": "",
  "discord_webhook": ""
}
```

## Validation
- Slack webhooks must match: `https://hooks.slack.com/services/...`
- Discord webhooks must match: `https://discord.com/api/webhooks/...`
- Test the webhook with a test message before saving
