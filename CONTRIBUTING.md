# Contributing to claude-alloy

Thanks for your interest in improving claude-alloy.

## How to Contribute

### Bug Reports
Open an issue with:
- What you expected
- What happened
- Steps to reproduce
- Your Claude Code version (`claude --version`)

### Feature Requests
Open an issue describing:
- The problem you're trying to solve
- Your proposed solution
- Why existing agents/skills/hooks don't cover it

### Pull Requests

1. Fork the repo
2. Create a branch (`git checkout -b my-feature`)
3. Make your changes
4. Test with `bash install.sh --project ~/test-project`
5. Verify: `alloy` then `unalloy` cycle works
6. Submit a PR

### Adding an Agent

See the [Development Guide](README.md#development-guide) in the README.

Checklist:
- [ ] `agents/my-agent.md` with proper frontmatter
- [ ] `agent-memory/my-agent/MEMORY.md`
- [ ] Added to `AGENTS` in `install.sh`
- [ ] Added to roster in `CLAUDE.md`
- [ ] Added to `/alloy` reference card
- [ ] Agent name follows the material/metal naming theme

### Adding a Skill

- [ ] `skills/my-skill/SKILL.md` with proper frontmatter
- [ ] Added to `SKILLS` in `install.sh`
- [ ] Added to skills table in `commands/alloy.md`
- [ ] Keep it under 300 lines (context budget matters)

### Adding a Hook

- [ ] `hooks/my-hook.sh` with `#!/usr/bin/env bash` and `set -u`
- [ ] Includes jq dependency check
- [ ] Added to `settings.json`
- [ ] Added to `HOOKS` in `install.sh`
- [ ] Silent on success, verbose on failure

## Code Style

- **Hook scripts**: `set -u` only, no `set -e` (hooks need graceful failure — a failing hook shouldn't crash the session)
- **Installer scripts** (`install.sh`, `activate.sh`, etc.): `set -euo pipefail` (installers should fail fast on errors)
- Agent prompts: direct, actionable, no fluff
- Skills: under 300 lines, high value per token
- Hooks: exit 0 (allow) or exit 2 (block with stderr message)

## Naming Convention

Agents are named after materials and metals. The name should reflect the agent's core property:
- **steel** = holds everything together (orchestrator)
- **tungsten** = doesn't melt under pressure (autonomous executor)
- **mercury** = moves fast (search)

New agents should follow this pattern. Propose a name with your PR and explain the metaphor.
