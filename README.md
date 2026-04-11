<p align="center">
  <strong>Claude Alloy</strong>
</p>

<p align="center">
  <em>A mixture stronger than its parts.</em>
</p>

<p align="center">
  <a href="https://github.com/OMARVII/claude-alloy/actions/workflows/ci.yml"><img src="https://github.com/OMARVII/claude-alloy/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/OMARVII/claude-alloy/releases/tag/v1.1.0"><img src="https://img.shields.io/badge/version-1.1.0-green.svg" alt="Version 1.1.0"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#the-agents">Agents</a> &bull;
  <a href="#install-modes">Install</a> &bull;
  <a href="#development-guide">Dev Guide</a> &bull;
  <a href="#contributing">Contributing</a>
</p>

---

Fourteen agents. Named after what they're made of.

Steel holds the structure. Tungsten doesn't melt under pressure. Mercury moves fast. Graphene conducts everything.

This is what [Claude Code](https://docs.anthropic.com/en/docs/claude-code) looks like with a team.

```bash
alloy
```

That's it. 14 agents, 17 hooks, 10 skills, 14 commands. Globally active. Open Claude in any directory and go.

<!-- TODO: Add terminal demo GIF here before launch (e.g. asciinema or vhs recording of `alloy` → `ig implement auth` → agents firing) -->

```bash
unalloy
```

Back to vanilla Claude. Your original settings restored exactly.

---

## The Agents

| Agent | Model | Role | Why the name |
|---|---|---|---|
| **steel** | opus | Main orchestrator. Plans, delegates, verifies. | The alloy that holds everything together. |
| **tungsten** | opus | Autonomous execution. Won't stop until done. | Highest melting point of any metal. |
| **quartz** | opus | Architecture consultant. Read-only. | Crystal clear — sees through problems. |
| **carbon** | sonnet | Strategic planner. Interview-first. | Foundation element — basis of all structure. |
| **gauge** | sonnet | Code and plan reviewer. Pass/fail. | Measures precisely. No ambiguity. |
| **graphene** | sonnet | External docs and research. | One atom thick. Conducts everything. |
| **prism** | sonnet | Finds hidden ambiguities before planning. | Splits light to reveal all angles. |
| **spectrum** | sonnet | Image, PDF, diagram analysis. | Full range of vision. |
| **mercury** | haiku | Fast codebase search. Cheap to fire. | Quicksilver — everywhere at once. |
| **sentinel** | opus | Security reviewer. CWE Top 25, secrets, injection. Read-only. | The watchman. Never sleeps. |
| **titanium** | sonnet | Context recovery. Rebuilds state from previous sessions. | Highest strength-to-weight ratio. Lightweight but recovers everything. |
| **iridium** | sonnet | Performance reviewer. Finds O(n²), memory leaks, N+1 queries. | Densest natural element. Catches the heaviest problems. |
| **cobalt** | sonnet | Dependency expert. CVEs, outdated packages, supply chain risks. | Essential trace element. Small but critical to the whole. |
| **flint** | sonnet | Test engineer. Coverage gaps, flaky tests, missing edge cases. | Strikes sparks. Finds what breaks. |

**Model tiering is intentional.** Opus handles orchestration and judgment. Sonnet handles research and analysis. Haiku handles grep. You pay for thinking, not searching.

---

## Requirements

- [**Claude Code**](https://docs.anthropic.com/en/docs/claude-code) — Anthropic's CLI agent (`npm install -g @anthropic-ai/claude-code`)
- **Claude Pro/Max subscription** or **Anthropic API key** — Max recommended for multi-agent workloads
- `bash` (4.0+), `jq`, `git`

> **Token usage:** claude-alloy routes Opus for orchestration, Sonnet for implementation, and Haiku for search — so you pay for thinking, not searching. Multi-agent tasks (especially `ig` mode) use more tokens than single-agent Claude Code. Claude Max 5x/20x with higher rate limits is strongly recommended. API users can expect roughly 2-3x typical token usage on complex tasks.

---

## Quick Start

### Simple (recommended)

One-time alias setup:

```bash
git clone https://github.com/OMARVII/claude-alloy.git
cd claude-alloy
bash setup-aliases.sh
source ~/.zshrc  # or ~/.bashrc
```

Then, anywhere:

```bash
alloy     # 14 agents active globally
unalloy      # back to vanilla Claude
```

Then inside Claude, type **`ig`** (or `/ignite`) for maximum effort mode — all agents fire in parallel, nothing ships half-done.

### Plugin (Claude Code marketplace)

> **Status:** Coming soon — pending Claude Code marketplace availability. For now, use the global toggle or per-project install.

```bash
# Local plugin testing (clone first)
claude --plugin-dir /path/to/claude-alloy
```

### Per-project (teams)

```bash
# Install into a specific project only
bash install.sh --project /path/to/project

# Or set up the global /alloy-init command, then use it in any project
bash setup-global.sh
# In Claude Code:
/alloy-init
```

---

## What You Get

```
.claude/
├── agents/               14 agents (steel, tungsten, quartz, mercury, graphene, carbon, prism, gauge, spectrum, sentinel, titanium, iridium, cobalt, flint)
├── skills/               10 skills (git-master, frontend-ui-ux, dev-browser, code-review, review-work, ai-slop-remover, tdd-workflow, verification-loop, wiki, learn)
├── commands/             14 commands (/ignite, /ig, /loop, /halt, /alloy, /unalloy, /handoff, /refactor, /init-deep, /start-work, /status, /wiki-update, /notify-setup, /learn)
├── alloy-hooks/          17 hooks (all automatic, listed below)
├── wiki/                 project wiki (architecture, conventions, decisions)
├── agent-memory/         14 memory files (generated at install — agents learn across sessions)
├── settings.json         hook config + env vars
└── CLAUDE.md             injected context for all agents
```

### Hooks (all automatic)

| Hook | When | What it does |
|---|---|---|
| **write-guard** | Before Write | Blocks overwriting existing files — use Edit instead |
| **branch-guard** | Before Write/Edit | Blocks edits on main/master branches |
| **comment-checker** | After Write/Edit | Warns about AI slop comments |
| **typecheck** | After .ts/.tsx edits | Runs `tsc --noEmit`, reports errors |
| **auto-install** | After package.json/requirements.txt/pyproject.toml | Installs dependencies (lifecycle scripts disabled for safety) |
| **agent-reminder** | After 2 direct searches | Nudges toward mercury/graphene agents |
| **lint** | After Write/Edit | Runs ESLint/Biome/Prettier, reports errors |
| **skill-reminder** | After 8 direct tool calls | Nudges toward delegation |
| **todo-enforcer** | Before stopping | Reminds about incomplete todos (blocks once, then allows) |
| **loop-stop** | Before stopping | Keeps working if `/loop` is active |
| **session-notify** | On stop | Desktop notification when session ends |
| **pre-compact** | Before compaction | Saves critical context before memory compaction |
| **subagent-start** | On subagent start | Tracks agent activity and delegation |
| **subagent-stop** | On subagent stop | Verifies agent deliverables and results |
| **rate-limit-resume** | On stop failure | Auto-resumes on rate limit (up to 3x) |
| **session-start** | On session start | Injects wiki context into session |
| **session-end** | On session end | Nudges wiki update if session was productive |

### Commands

| Command | What it does |
|---|---|
| **`/ignite`** (or just **`ig`**) | Maximum effort mode. 4+ agents fire in parallel, todos tracked obsessively, manual QA before completion. The signature move. |
| `/loop` | Autonomous loop — agent works until task is 100% complete |
| `/halt` | Stop the loop |
| `/alloy` | Show all agents, skills, commands, hooks |
| `/unalloy` | Remove claude-alloy from current project |
| `/handoff` | Create context summary for session continuation |
| `/refactor` | Safe refactoring with LSP diagnostics |
| `/init-deep` | Generate hierarchical CLAUDE.md files |
| `/start-work` | Execute a plan from carbon |
| `/status` | Show loop state, pending todos, branch, recent activity |
| `/wiki-update` | Update project wiki with session learnings |
| `/notify-setup` | Configure desktop, Slack, and Discord notifications |
| `/learn` | Extract reusable patterns from the current session into skills |

---

## How It Works

Steel doesn't follow a fixed pipeline. It routes adaptively:

```
                ┌─ FAST: handle directly
                │
User → steel ──├─ RESEARCH: mercury ×N + graphene ×N (parallel)
   ↑            │     └─ prism checks INLINE as results arrive
   │ titanium   ├─ PLAN: carbon (only when 3+ files)
   │ (auto)     │     └─ gauge reviews only if carbon flags uncertainty
                ├─ BUILD: tungsten (autonomous, circuit breaker)
                │     └─ review gate (automatic, based on what changed):
                │           sentinel · iridium · cobalt · flint
                └─ CONSULT: quartz (on-demand, never in pipeline)
```

**What makes this different:** prism runs inline (not as a separate step), gauge is optional (not a required gate), and after every build a review gate auto-fires up to four reviewers — sentinel (security), iridium (performance), cobalt (dependencies), flint (tests) — based on what changed. quartz is never in a pipeline (only when stuck). No fixed sequence — steel adapts per task.

Type **`ig`** (or `/ignite`) for maximum effort: 4+ agents fired in parallel, todos tracked obsessively, manual QA before every completion claim. Two letters. Full team engaged.

---

## Install Modes

| Method | Command | Who it's for |
|---|---|---|
| **Global toggle** | `alloy` / `unalloy` | Most users — instant, reversible |
| **Plugin** | `claude plugin add claude-alloy` | Marketplace users (coming soon) |
| **Per-project** | `bash install.sh --project .` | Teams — committed to version control |
| **Global command** | `bash setup-global.sh` then `/alloy-init` | One command per project |

`alloy` merges with your existing Claude settings. Your custom permissions, model preferences, and plugins are preserved. `unalloy` restores them exactly.

### Uninstall

| What to remove | Command |
|---|---|
| Deactivate (keep files) | `unalloy` |
| Remove aliases | `bash setup-aliases.sh --uninstall` |
| Remove global command | `bash setup-global.sh --uninstall` |
| Remove per-project install | `bash install.sh --uninstall` |
| Remove everything | All of the above |

---

## Development Guide

### Adding a New Agent

1. Create `agents/my-agent.md`:
```yaml
---
name: my-agent
description: "What this agent does."
model: sonnet
tools:
  - Read
  - Grep
  - Bash
maxTurns: 20
memory: project
---

Your system prompt here.
```

2. Create `agent-memory/my-agent/MEMORY.md`
3. Add the name to `AGENTS` in `install.sh`
4. Add to the roster in `CLAUDE.md`
5. Add to `/alloy` reference card
6. Test: `bash install.sh --project ~/test-project`

### Adding a New Skill

1. Create `skills/my-skill/SKILL.md`:
```yaml
---
name: my-skill
description: "When to auto-load this skill."
---

Skill instructions here.
```

2. Add to `SKILLS` in `install.sh`
3. Add to `CLAUDE.md` skills table

### Adding a New Hook

1. Create `hooks/my-hook.sh`:
```bash
#!/usr/bin/env bash
set -u
INPUT=$(cat)

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

# Your logic here

# Output for PostToolUse hooks (non-blocking feedback):
# jq -n --arg msg "Your message" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'

# Exit codes: 0 = continue, 2 = block (with stderr message)
exit 0
```

2. `chmod +x hooks/my-hook.sh`
3. Add to `settings.json` under the appropriate event
4. Add to `HOOKS` in `install.sh`

### Hook Events

| Event | When | Can Block? |
|---|---|---|
| `PreToolUse` | Before tool execution | Yes |
| `PostToolUse` | After tool execution | No |
| `Stop` | Before session stops | Yes |
| `PreCompact` | Before memory compaction | No |
| `SubagentStart` | When a subagent is spawned | No |
| `SubagentStop` | When a subagent completes | No |
| `StopFailure` | When session stops due to error | No |
| `SessionStart` | When a session starts/resumes | No |
| `SessionEnd` | When a session ends | No |

---

## Environment Variables

Set in `settings.json`:

| Variable | Value | Why |
|---|---|---|
| `BASH_DEFAULT_TIMEOUT_MS` | `420000` (7 min) | Prevents timeout on long builds and test suites |
| `BASH_MAX_TIMEOUT_MS` | `420000` (7 min) | Same |

---

## Platform Support

| Platform | Status | Notes |
|---|---|---|
| **macOS** | Full support | Tested on macOS 14+ |
| **Linux** | Full support | Ubuntu, Debian, Fedora, Arch |
| **Windows** | Via WSL | Claude Code requires WSL on Windows — our scripts work inside WSL |

```bash
# Install jq (required for hooks):
brew install jq        # macOS
sudo apt install jq    # Ubuntu/Debian
sudo dnf install jq    # Fedora
```

## Architecture Decisions

| Decision | Rationale |
|---|---|
| Claude-only models | Opus/Sonnet/Haiku tiering. One provider, no API key juggling. |
| Per-project install | Each project opts in. Nothing polluted globally (unless you want it with `alloy`). |
| Shell hooks | Claude Code hooks are external processes. Shell is universal, zero dependencies except jq. |
| 14 agents, not 30+ | Curated over comprehensive. Every agent earns its slot. No bloat. |
| Block-once todo enforcer | Reminds the agent once, then lets you stop. Smart, not annoying. |
| Agent memory files | Agents learn across sessions. Preferences, patterns, edge cases persist. |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add agents, skills, hooks, and submit PRs.

Agents follow the material/metal naming convention — the name should reflect the agent's core property.

---

## Security

See [SECURITY.md](SECURITY.md) for the security policy, known considerations, and how to report vulnerabilities.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history. Current version: **1.1.0**.

---

## Inspiration

Built on Claude Code. Inspired by the agent orchestration patterns pioneered by [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent).

The alloy concept: individual agents are metals — each with specific properties. Together, they're stronger than any single element. The same principle applies to AI agents.

---

## License

[MIT](LICENSE)
