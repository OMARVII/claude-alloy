---
description: "claude-alloy reference — full delegation table, IGNITE protocol, core principles."
---

# /alloy

claude-alloy reference manual. The roster, adaptive-routing summary, skills/commands tables, and MCP servers live in `CLAUDE.md` (always loaded). The detail below is reference material — fetched on demand when you actually need it.

## Quick reference

- `@"mercury (agent)"` — codebase search (haiku, parallel)
- `@"graphene (agent)"` — external docs / library research
- `@"tungsten (agent)"` — autonomous build agent
- `@"quartz (agent)"` — read-only architecture consultant
- `/ignite` or `/ig` — max-effort mode
- `/loop <task>` — autonomous self-continuation
- `/git-master` — atomic commits, rebase, history search
- `/hyperplan` — 5-persona adversarial planning, hands off to carbon

Repo: https://github.com/OMARVII/claude-alloy

## Delegation Table (detailed)

| Routing Path | Agent | When to invoke |
|---|---|---|
| **RESEARCH** | @"mercury (agent)" ×N | Codebase questions with multiple search angles, unfamiliar structure, or cross-layer impact. Fire narrow scopes in parallel. |
| **RESEARCH** | @"graphene (agent)" ×N | External library, API, docs, or production security guidance that can change the decision. |
| **INLINE CHECK** | @"prism (agent)" | AS research results arrive, before planning. Not a separate sequential step. |
| **PLAN** | @"carbon (agent)" | When 3+ files will be modified. Skip for 1-2 file changes. |
| **REVIEW** | @"gauge (agent)" | Only when carbon flags "uncertain about approach" or for significant PRs. |
| **BUILD** | @"tungsten (agent)" | Complex multi-file implementation. Give it a goal, not a recipe. |
| **SECURITY** | @"sentinel (agent)" | Automatically on code touching auth, crypto, user input, APIs. |
| **CONSULT** | @"quartz (agent)" | After 2+ failed attempts, or before irreversible architecture decisions. |
| **VISUAL** | @"spectrum (agent)" | Image, PDF, diagram, screenshot analysis. |
| **RECOVER** | @"titanium (agent)" | Session start when continuing interrupted work. |
| **PERFORMANCE** | @"iridium (agent)" | After implementation, when code touches hot paths, data processing, or database queries. |
| **DEPENDENCY** | @"cobalt (agent)" | Before merging, or when adding/updating dependencies. Run periodically on full project. |
| **TESTING** | @"flint (agent)" | After implementation, to assess test coverage and quality. Before merging test-heavy PRs. |

### Key routing rules

- When mercury/graphene are both needed, fire them in parallel (never sequential)
- prism runs WHILE research results stream in (not as a separate step after)
- gauge is OPTIONAL — only invoked when carbon explicitly flags uncertainty
- sentinel is AUTOMATIC on security-relevant code (auth, crypto, input handling)
- quartz is NEVER in a pipeline — only invoked when steel hits an architectural wall
- titanium fires ONCE at session start if previous work exists

## IGNITE Protocol

IGNITE protocol: see CLAUDE.md "Keyword Triggers" section.

## Core Principles

1. **No AI slop** — Code should be indistinguishable from a senior engineer's
2. **Delegate, don't struggle** — Use the right agent for each task type
3. **Verify everything** — Run diagnostics, tests, and manual QA before declaring done
4. **Precision parallelism** — Fire agents when uncertainty, risk, or scale makes them valuable
5. **Complete the task** — Never stop at 80%. Finish 100% of what was asked.

## MCP Tool Search

Anthropic's tool search defers MCP tool schemas — instead of loading every tool definition every turn, the agent receives a summary and loads the 3-5 relevant tools on demand via `ToolSearch`. Per Anthropic's docs, 50 tools can consume 10-20K tokens of context; lazy-loading recovers a stated **over 85%** of that overhead (see [Anthropic's tool-search docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool)).

- **Activation:** Designed to auto-activate when MCP tools exceed 10% of context. Confirmed open issues ([#18397](https://github.com/anthropics/claude-code/issues/18397), [#41472](https://github.com/anthropics/claude-code/issues/41472)) report it does NOT reliably auto-activate. If you don't see it active in `/context`, set `ENABLE_TOOL_SEARCH=true` in your environment as a workaround until Anthropic resolves the bug.
- **Verify it's active:** look for `<system-reminder>` blocks in your transcript naming "deferred tools available via ToolSearch", or check the tool list in `/context`. With claude-alloy's three MCP servers (context7, grep_app, websearch) plus any user-added MCP, you'll see deferred entries the moment a server registers >10 tools.
- **Tune via `ENABLE_TOOL_SEARCH`** env var (set in your shell, not settings.json):
  - `true` — always on (recommended workaround for the auto-activation bug)
  - `auto:N` — activate only when tool defs exceed N% of context (e.g. `auto:5`)
  - `false` — disable; load every tool every turn
- **Caveat:** requires Sonnet 4+ or Opus 4+ models. Haiku does not support tool search; mercury runs without it.
