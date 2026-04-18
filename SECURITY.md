# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| 1.x (latest) | Yes |

## Reporting a Vulnerability

If you find a security vulnerability in claude-alloy, please report it responsibly.

**Do NOT open a public issue.**

Email: hello@omar-khaled.com

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You'll receive a response within 48 hours. We'll work with you to understand and fix the issue before any public disclosure.

## Scope

This policy covers:
- Hook scripts (shell injection, path traversal)
- Agent prompts (prompt injection, data exfiltration)
- Install scripts (file system access, permission escalation)
- Settings/config files (credential exposure)

This policy does NOT cover:
- Claude Code itself (report to Anthropic)
- MCP servers (report to respective maintainers)

## Known Security Considerations

### Opt-in hook gates (off by default since v1.6.1)

Two hooks can execute project-local code and are therefore disabled unless you explicitly opt in with an environment variable.

**`ALLOY_AUTO_LINT=1` — enables `hooks/lint.sh` + `hooks/typecheck.sh`**
These hooks run `npx --no-install tsc`, `npx --no-install eslint`, `npx --no-install @biomejs/biome`, and `npx --no-install prettier` from the project directory after file edits. `npx` resolves binaries from the project's `node_modules/.bin/` first — if you open Claude Code in a directory containing a malicious `package.json` with trojanized linter packages (or a malicious `eslint.config.js` / `prettier.config.js` that's loaded as code), those hooks will execute that code. Same trust model as running `npm test` in any project. `--no-install` prevents `npx` from fetching unknown packages, but does not protect against already-installed malicious binaries. Enable only in trusted repos.

**`ALLOY_AUTO_INSTALL=1` — enables `hooks/auto-install.sh`**
When enabled, this hook runs `npm install --ignore-scripts` on `package.json` edits, `pip install --no-deps --only-binary=:all: -r requirements.txt` on `requirements.txt` edits, and emits a reminder (does NOT execute) for `pyproject.toml` edits. Pip's `--only-binary=:all:` is intended to prevent build backends from executing arbitrary Python during install, but a typosquatted wheel can still contain malicious code that runs on import. Enable only when you trust every dependency name the agent might write into a manifest.

Both variables default to unset → hooks early-exit with no action. Set them in your shell rc (`~/.zshrc` or equivalent) if you want the behavior.

### Other notes

**Webhook URL allowlist:** `hooks/session-notify.sh` rejects Slack/Discord webhook URLs that don't match `https://hooks.slack.com/*` or `https://discord.com/api/webhooks/*`. Prevents SSRF via malicious `notify-config.json`.

**Self-update scope:** `self-update.sh` refuses to `git pull` unless the repo's `origin` remote is exactly `OMARVII/claude-alloy` (not a substring match). Prevents hostile forks from being auto-updated.
