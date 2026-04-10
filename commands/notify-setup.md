---
description: "Configure notification settings for session completion alerts. Supports desktop, Slack, and Discord."
---

# Notification Setup

Configure how claude-alloy notifies you when sessions or tasks complete.

## Steps

1. Read current config from `~/.claude/.alloy-state/notify-config.json` (create if missing)
2. Ask the user what they want to configure:
   - Desktop notifications (on/off, default: on)
   - Slack webhook URL
   - Discord webhook URL
3. Write updated config to `~/.claude/.alloy-state/notify-config.json`

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
