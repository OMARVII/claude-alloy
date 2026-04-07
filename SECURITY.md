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
