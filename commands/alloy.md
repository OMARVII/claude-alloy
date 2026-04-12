---
description: "Show all available claude-alloy agents, skills, commands, and hooks with usage examples."
---

# claude-alloy — Usage Guide

## Agents (14)

| Agent | Model | Invoke | Use For |
|---|---|---|---|
| **steel** | opus | Default (auto) | Main orchestrator. Plans, delegates, verifies. |
| **tungsten** | opus | @"tungsten (agent)" | Complex multi-step implementation. Won't stop until done. |
| **quartz** | opus | @"quartz (agent)" | Architecture advice, hard debugging. Read-only, can't edit. |
| **mercury** | haiku | @"mercury (agent)" | Fast codebase search. "Where is X?", "Find Y". |
| **graphene** | sonnet | @"graphene (agent)" | External docs, library research, OSS examples. |
| **carbon** | sonnet | @"carbon (agent)" | Strategic planning. Interviews you before any code. |
| **prism** | sonnet | @"prism (agent)" | Finds hidden ambiguities before planning begins. |
| **gauge** | sonnet | @"gauge (agent)" | Reviews plans/code. Approval bias — only flags blockers. |
| **spectrum** | sonnet | @"spectrum (agent)" | Analyzes images, PDFs, diagrams, screenshots. |
| **sentinel** | opus | @"sentinel (agent)" | Security review. CWE Top 25, secrets, injection, auth. Read-only. |
| **titanium** | sonnet | @"titanium (agent)" | Context recovery. Rebuilds state from previous sessions. |
| **iridium** | sonnet | @"iridium (agent)" | Performance review. Finds O(n²), memory leaks, N+1 queries. |
| **cobalt** | sonnet | @"cobalt (agent)" | Dependency expert. CVEs, outdated packages, supply chain risks. |
| **flint** | sonnet | @"flint (agent)" | Test engineer. Coverage gaps, flaky tests, missing edge cases. |

### Agent Tips
- Fire **mercury** + **graphene** in parallel for research (they're cheap)
- Use **quartz** after 2+ failed fix attempts (it's expensive but worth it)
- Use **carbon** for any task with 3+ steps before implementing
- **tungsten** is your heavy lifter — give it a goal, not a recipe
- Invoke **sentinel** after any code that touches auth, crypto, or user input
- Invoke **titanium** at session start when continuing interrupted work

## Skills (8)

| Skill | Invoke | Use For |
|---|---|---|
| **git-master** | `/git-master` | Atomic commits, rebase, squash, blame, bisect |
| **frontend-ui-ux** | `/frontend-ui-ux` | UI design, styling, animations, layout |
| **dev-browser** | `/dev-browser` | Browser automation, screenshots, web testing |
| **code-review** | `/code-review` | Confidence-scored code review (only reports issues >= 80) |
| **review-work** | `/review-work` | 5-agent parallel review (goal, QA, code, security, context) |
| **ai-slop-remover** | `/ai-slop-remover` | Remove AI-generated code smells (comments, nesting, naming) |
| **tdd-workflow** | `/tdd-workflow` | Test-driven development: red-green-refactor cycle enforcement |
| **verification-loop** | `/verification-loop` | Full verify cycle: build → typecheck → lint → test → E2E |

## Commands (14)

| Command | Invoke | What It Does |
|---|---|---|
| **ignite** | `/ignite` or `/ig` | Max-effort mode. All agents engaged. No stopping. |
| **loop** | `/loop <task>` | Autonomous loop until task is 100% done |
| **init-deep** | `/init-deep` | Generate CLAUDE.md files throughout project |
| **refactor** | `/refactor <target>` | Safe refactoring with diagnostics verification |
| **start-work** | `/start-work <plan>` | Execute a plan from carbon |
| **handoff** | `/handoff` | Create HANDOFF.md for session continuation |
| **halt** | `/halt` | Stop loop and autonomous continuation |
| **status** | `/status` | Show loop state, pending todos, branch, recent activity |
| **alloy** | `/alloy` | This guide |
| **unalloy** | `/unalloy` | Remove claude-alloy harness from current project |
| **wiki-update** | `/wiki-update` | Update project wiki with session learnings |
| **notify-setup** | `/notify-setup` | Configure desktop, Slack, and Discord notifications |
| **learn** | `/learn` | Extract reusable patterns from session into skills |

## Hooks (17, automatic)

| Hook | When | What |
|---|---|---|
| **write-guard** | Before Write tool | Blocks overwriting existing files (use Edit instead) |
| **branch-guard** | Before Write/Edit | Blocks edits on main/master branches |
| **comment-checker** | After Write/Edit | Warns about AI slop comments |
| **typecheck** | After Write/Edit on .ts/.tsx | Runs TypeScript type-check, reports errors |
| **lint** | After Write/Edit | Runs ESLint/Biome/Prettier, reports lint errors |
| **auto-install** | After editing package.json/requirements.txt | Auto-installs dependencies synchronously |
| **agent-reminder** | After 2 direct searches | Nudges you to use mercury/graphene agents |
| **skill-reminder** | After 8 direct tool calls | Nudges you to delegate or use skills |
| **todo-enforcer** | Before stopping | Blocks exit if todos are incomplete |
| **loop** | Before stopping | Keeps you working if loop is active |
| **session-notify** | On stop | macOS/Linux desktop notification when session ends |
| **pre-compact** | Before compaction | Saves critical context before memory compaction |
| **subagent-start** | On subagent start | Tracks agent activity and delegation |
| **subagent-stop** | On subagent stop | Verifies agent deliverables and results |
| **rate-limit-resume** | On stop failure | Auto-resumes on rate limit (up to 3x) |
| **session-start** | On session start | Injects wiki context into session |
| **session-end** | On session end | Nudges wiki update if session was productive |

## Quick Examples

**Research something:**
```
Find how authentication works in this codebase
```
(steel auto-detects search intent, mercury agents fire)

**Max effort mode:**
```
ig implement the new payment flow end to end
```
(steel detects ignite keyword + all agents activated)

**Autonomous completion:**
```
/loop refactor the entire auth module to use JWT
```
(won't stop until fully done)

**Get architecture advice:**
```
@"quartz (agent)" should we use microservices or a monolith for the notification system?
```

**Fast parallel research:**
```
@"mercury (agent)" find all API endpoints
@"graphene (agent)" find best practices for REST API versioning
```

## Global Activation (alloy / unalloy)

Instead of running `/alloy-init` in every project, you can activate claude-alloy **globally** with a single terminal command.

**One-time setup:**
```bash
bash setup-aliases.sh
```

**Usage:**
| Command | What It Does |
|---|---|
| `alloy` | Activate claude-alloy globally — all agents, skills, hooks available in every project |
| `unalloy` | Deactivate claude-alloy — restore vanilla Claude settings |

```bash
alloy       # Alloy active everywhere — open claude in any directory
unalloy     # Back to vanilla Claude
```

**How it works:**
- `alloy` installs the full harness into `~/.claude/` (agents, skills, commands, hooks, memory)
- Merges with your existing settings (your custom config is preserved)
- Backs up your original `settings.json` — `unalloy` restores it exactly
- Running `alloy` again updates to the latest version (original backup preserved)

## Model Cost Tiers

| Tier | Model | Cost | Used By |
|---|---|---|---|
| High | opus | $$$ | steel, tungsten, quartz, sentinel |
| Medium | sonnet | $$ | carbon, gauge, graphene, prism, spectrum, titanium, iridium, cobalt, flint |
| Low | haiku | $ | mercury |

**Tip:** mercury (haiku) is nearly free. Fire 3-5 in parallel without worry.
