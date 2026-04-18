# Privacy Policy — claude-alloy

_Effective: 2026-04-18_

## Summary

claude-alloy is a configuration harness for Claude Code. As of 2026-04-18, it does not collect, transmit, or store personal data on any server operated by the project. Third parties you invoke through it (MCP servers, GitHub for self-update, optional webhooks) operate under their own privacy policies, listed below.

## What claude-alloy is

claude-alloy is a set of Markdown prompts and shell scripts installed into your `~/.claude/` directory. It runs no server, ships no binary, and has no background daemon. Every file is plain text and auditable in this repository.

## Information claude-alloy does not collect

- No telemetry, analytics, crash reports, or usage metrics.
- No device or user identifiers transmitted to any service operated by this project.
- No session transcripts, prompts, or file contents sent to this project.

## Information claude-alloy stores locally on your machine

These files live on your disk and are never transmitted by claude-alloy.

- `~/.claude/.alloy-state/tool-count-{SESSION_ID}` — tool-call counter for the HUD statusline. Session lifetime.
- `~/.claude/.alloy-state/ignite-active-{SESSION_ID}` — flag while IGNITE mode is active. Session lifetime.
- `~/.claude/.alloy-state/notify-config.json` — webhook URLs, only if you ran `/notify-setup`. Kept until deleted.
- `~/.claude/.alloy-state/todo-blocked-{KEY}` — in-session todo locks. Session lifetime.
- `~/.claude/.alloy-state/agent-log.jsonl` — JSONL log of subagent spawn/stop events including the agent's input payload. Written by `hooks/subagent-start.sh` and `hooks/subagent-stop.sh`. Auto-purged after 7 days by `hooks/session-end.sh`.
- `~/.claude/.alloy-state/agent-count-{SESSION_ID}` — integer counter of subagents spawned in the session.
- `~/.claude/.alloy-state/agents-spawned-{SESSION_ID}` — list of agent names spawned.
- `~/.claude/.alloy-state/pre-compact-snapshot.md` — local snapshot of the current git branch, list of uncommitted files, and last 5 commit subject lines. Written before context compaction so the next turn can rebuild context. Never transmitted.
- `~/.claude/.alloy-state/last-update-check` — timestamp file gating self-update to a 7-day cadence.
- `~/.claude/alloy-loop-active` — flag file created while `/loop` is running. Removed by `/halt`.
- `~/.claude/.alloy-meta`, `.alloy-manifest`, `.alloy-version` — install metadata for clean uninstall.
- `~/.claude/.alloy-no-update` — user-created opt-out file for self-update.
- `~/.claude/settings.json.alloy-backup` — copy of your original `settings.json` before alloy modified it. Used by `/unalloy` for clean uninstall.
- `~/.claude/.alloy-backup-YYYYMMDD_HHMMSS/` — timestamped backups of pre-existing `agents/`, `skills/`, and `commands/` directories, created by `install.sh` if those dirs already had content.
- `~/.claude/agent-memory/{agent}/*.md` — user-editable notes that agents may read or write.

Files under `~/.claude/.alloy-state/` older than 7 days are auto-deleted by the session-end hook; other state files persist until `/unalloy` or manual removal.

## Third parties that may receive your data

claude-alloy does not operate any of the services below. When one is invoked, your request goes directly from Claude Code to the operator. claude-alloy is not in the request path and receives no copy.

| Service | Operator | When data is sent | Their privacy policy |
| --- | --- | --- | --- |
| context7 MCP | Upstash | A tool invokes context7 (library docs) | https://upstash.com/trust/privacy |
| grep_app MCP | grep.app | A tool invokes grep_app (code search) | https://grep.app |
| Exa websearch MCP | Exa AI | A tool invokes the web search MCP | https://exa.ai/privacy-policy |
| Playwright MCP | Microsoft | Runs locally. `npx` may fetch `@playwright/mcp` from the npm registry on first run or when the npm cache is cleared. Any pages the agent navigates to receive standard HTTP requests from your machine. | https://privacy.microsoft.com/en-us/privacystatement |
| GitHub | GitHub, Inc. | `git fetch` during self-update from `github.com/OMARVII/claude-alloy` | https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement |
| Slack webhooks | Slack Technologies | You configured a Slack webhook via `/notify-setup` | https://slack.com/trust/privacy |
| Discord webhooks | Discord Inc. | You configured a Discord webhook via `/notify-setup` | https://discord.com/privacy |

When any third-party service is invoked, that operator receives standard request metadata (e.g., your IP address and user-agent string) along with the request payload, and handles it under its own terms.

If `EXA_API_KEY` is set, it is included as a query parameter in the Exa MCP URL to authenticate your requests.

## How data leaves your machine

- **Default self-update.** `self-update.sh` runs `git fetch origin main` against GitHub at most once every 7 days to check for updates; with `ALLOY_AUTO_UPDATE` unset, it only notifies. Setting `ALLOY_AUTO_UPDATE=1` auto-applies the update via `git pull --ff-only` on `main` without prompting. Opt out entirely with `ALLOY_AUTO_UPDATE=0`, the `--skip-update` flag, or by creating `~/.claude/.alloy-no-update`.
- **On user invocation.** When a tool call reaches an MCP server (context7, grep_app, Exa), the request goes directly from Claude Code to that operator.
- **Opt-in only (off by default).** `ALLOY_BROWSER=1` registers the Playwright MCP; `ALLOY_AUTO_LINT=1` lets the lint hook invoke `npx` tools after edits; `ALLOY_AUTO_INSTALL=1` lets the install hook run `npm install --ignore-scripts` or `pip install` on manifest changes. Each reaches its registry only when enabled.
- **User-configured.** If you ran `/notify-setup`, `hooks/session-notify.sh` POSTs the fixed string `"claude-alloy: Session complete. Check your results."` to allowlisted hostnames only (`hooks.slack.com/*`, `discord.com/api/webhooks/*`, `discordapp.com/api/webhooks/*`). No session data, metrics, or identifiers are included.

## Data usage and retention

claude-alloy does not collect data, so there is no data usage or retention on our end. Data that flows to third-party services listed above is retained according to each operator's own policy; see the links in the table above.

## Your choices

- Disable self-update: set `ALLOY_AUTO_UPDATE=0`, pass `--skip-update`, or run `touch ~/.claude/.alloy-no-update`.
- Remove any MCP server you do not want from your Claude Code configuration.
- Leave `ALLOY_BROWSER`, `ALLOY_AUTO_LINT`, and `ALLOY_AUTO_INSTALL` unset to keep those features off.
- Do not run `/notify-setup`, or remove `~/.claude/.alloy-state/notify-config.json`, to stop webhook notifications.

## Changes to this policy

Material changes will be reflected by an updated effective date in this file and a commit to the `main` branch. Users can watch the repository on GitHub for notifications.

## Jurisdiction and maintainer

claude-alloy is maintained by Omar Khaled, an individual. The project has no commercial entity, user accounts, or paid tiers. As an open-source project with no commercial activity, it operates outside the scope of GDPR, CCPA, and PIPEDA.

## Security issues

Report vulnerabilities privately per [SECURITY.md](./SECURITY.md). Do not file public issues for security concerns.

## Contact

General: `hello@omar-khaled.com`.
