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

**Project-local tool execution:** The `typecheck.sh` and `lint.sh` hooks run `npx tsc`, `npx eslint`, `npx biome`, and `npx prettier` from the project directory. These resolve binaries from `node_modules/.bin/` first. If you open Claude Code in a directory containing a malicious `package.json` with trojanized linter packages, the hooks will execute that code automatically after file edits. This is the same trust model as running `npm test` in any project — do not open untrusted repositories without reviewing their dependencies first.

**pip install:** The `auto-install.sh` hook runs `pip install -e .` for `pyproject.toml` changes, which may execute `setup.py` if present. This only runs inside a detected virtual environment.
