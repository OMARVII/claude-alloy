# claude-alloy — Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.4.0] — 2026-04-14

### Added
- **ignite-stop-gate hook**: Blocks session exit if IGNITE protocol wasn't followed — validates 6+ agents spawned, graphene included, review agents fired after code changes (Stop hook, block-once pattern)
- **ignite-detector hook**: Detects `ig`/`ignite` keywords in user prompts via UserPromptSubmit hook, sets session flag and injects IGNITE protocol requirements
- **UserPromptSubmit hook event**: New hook lifecycle event for pre-processing user input before it reaches the agent

### Changed
- **install.sh**: Replace 70+ per-file success lines with compact summary output (~15 lines on success). Dynamic counts from variables instead of hardcoded. Version banner in header. Silent success / loud failure pattern.
- **install.sh --project**: Same compact output treatment (was ~65 lines, now ~11)
- **install.sh --uninstall**: Suppress `claude mcp remove` stdout noise (`2>/dev/null` → `&>/dev/null`)
- **activate.sh**: Dynamic file counts instead of hardcoded "14 agents", "8 skills", etc. Version banner from VERSION file.
- **setup-global.sh**: Fix stale "17 hooks" → "19 hooks" in alloy-init.md heredoc
- **agents/steel.md**: Add IGNITE MODE DELEGATION RULE section — steel MUST NOT write code in IGNITE mode, 6+ agents required (including graphene), review agents mandatory
- **commands/ignite.md**: Expand protocol from 6 to 8 steps — graphene mandatory, steel never writes code, review agents non-negotiable, self-audit step
- **hooks/subagent-start.sh**: Track per-session agent count and agent types in state files for IGNITE enforcement
- **hooks/todo-enforcer.sh**: Fix JSON output schema for Stop hooks (was stderr text, now proper `decision`/`reason` JSON). Add `stop_hook_active` check to prevent infinite re-blocking.
- **CLAUDE.md**: Update IGNITE keyword triggers to match new 6+ agent / graphene / review agent requirements. Add enforcement hook documentation.
- **hooks/hooks.json**: Add ignite-stop-gate to Stop section, add UserPromptSubmit section with ignite-detector

### Fixed
- **todo-enforcer.sh**: Output was plain text to stderr — Claude Code expected JSON with `decision`/`reason` fields. Fixed all output paths to use `jq -nc` JSON construction.
- **todo-enforcer.sh**: Missing `stop_hook_active` check caused infinite re-blocking loops when multiple Stop hooks fired.
- **install.sh + activate.sh**: `claude mcp remove`/`add` printed "Removed/Added MCP server..." on every activation even when nothing changed. Added `ensure_mcp()` helper that checks before touching config.

---

## [1.3.0] — 2026-04-12

### Added
- **Playwright MCP**: Opt-in browser automation via `ALLOY_BROWSER=1` — installs `@playwright/mcp` with `--browser=chrome` (uses system Chrome, zero binary download) for the `/dev-browser` skill (in `install.sh` and `activate.sh`)
- **Websearch MCP**: Always-on via keyless Exa hosted endpoint — zero config required. `EXA_API_KEY` upgrades to higher rate limits instead of gating access

### Changed
- **install.sh + activate.sh**: Remove MCP skip guard (`grep -q` check) — `claude mcp add` is idempotent, guard was unnecessary. Refactor MCP section for consistency across both files
- **install.sh + activate.sh**: Add `--browser=chrome` flag to Playwright MCP — uses system Chrome instead of downloading bundled Chromium (~400MB)
- **install.sh + activate.sh**: `EXA_API_KEY` now upgrades websearch rate limits instead of gating access — single registration (no double-register race)
- **install.sh + activate.sh**: Pin `@playwright/mcp@0.0.70` instead of `@latest` — prevents supply-chain risk via floating tag
- **install.sh + activate.sh**: `ALLOY_BROWSER` check uses strict `= "1"` instead of `-n` (setting `ALLOY_BROWSER=0` no longer accidentally enables Playwright)
- **.mcp.json.example**: Use keyless Exa URL as default (was showing `${EXA_API_KEY}`-gated URL); fix grep_app URL
- **install.sh + activate.sh**: Fix grep_app MCP URL from `https://mcp.grep.app/search` (404) to `https://mcp.grep.app`
- **install.sh + activate.sh**: Add `claude mcp remove` before each `claude mcp add` to handle transport-type changes across versions (stale stdio entries blocked HTTP re-registration)
- **ig.md**: Replace 40-line duplicate with redirect to `/ignite` (protocol lives in one place now)
- **12 agents**: Remove dead Self-Evolving Memory sections from agents that have `Write` in `disallowedTools` (saves ~200 tokens per subagent invocation)
- **CLAUDE.md**: Remove steel-specific sections ("Key differences", "Background Agents", "Model Tiering") that duplicate `steel.md` content — reduces per-turn token overhead for all agents
- **Skill count**: 10 → 8 — removed duplicate `wiki` and `learn` skills that were byte-for-byte identical to their `/wiki-update` and `/learn` commands

### Fixed
- **activate.sh**: Write jq merge output to `.tmp` file then `mv`, preventing empty `settings.json` on jq failure (was truncating via `>` redirect before jq ran)
- **install.sh --uninstall**: Restore `settings.json` from backup instead of orphaning it with hooks pointing to deleted scripts (matches `deactivate.sh` behavior)
- **install.sh --project**: Add backup + jq merge for `settings.json` instead of clobbering existing project settings (matches `activate.sh` merge logic)
- **session-start.sh**: Skip wiki files that only contain template markers; truncate at last newline instead of mid-line at 4KB cap

---

## [1.2.0] — 2026-04-12

### Fixed
- **agent-reminder.sh**: Replace overly broad `mcp__` pattern with specific search MCP prefixes (`mcp__context7`, `mcp__grep_app`) — was triggering false agent-reminder warnings on every MCP tool call (Linear, Slack, Notion, etc.)
- **agent-reminder.sh**: Remove dead single-underscore entries (`mcp_websearch`, `mcp_context7`, `mcp_grep_app`) that never matched real MCP tool names
- **setup-global.sh**: Add `${:?}` empty-variable guards to `rm` operations, matching `install.sh` defensive pattern
- **sentinel**: Replace Dependency Security checklist with deferral to cobalt, eliminating duplicate findings in post-implementation review gate
- **carbon**: Change Final Verification Wave F1 from `@quartz` to `@gauge` — planner shouldn't spawn opus for plan compliance checks

### Changed
- **8 read-only agents**: Add `Skill` to `disallowedTools` (sentinel, prism, gauge, spectrum, iridium, cobalt, flint, carbon) — prevents accidental invocation of write-capable skills
- **titanium**: Add missing `permissionMode: plan` and `memory: project`
- **spectrum**: Add Self-Evolving Memory section (had `memory: project` in frontmatter but no prompt instructions)
- **gauge**: Reduce `effort: max` → `effort: high` — approval-biased reviewer doesn't need max compute
- **carbon/gauge**: Fix descriptions — remove agent name used as noun ("strategic carbon" → "strategic planner", "code gauge" → "code reviewer")
- **tungsten**: Standardize agent references to `@"mercury (agent)"` / `@"graphene (agent)"` matching steel syntax
- **14 agents**: Assign unique colors (was: 5 agents shared red, 3 more collisions)
- **setup-global.sh**: Copy full installer payload to `~/.claude/alloy-dist/` so `/alloy-init` works after source repo is moved
- **install.sh**: Add `"agent": "steel"` to project settings for parity with global install
- **self-update.sh**: Remove unused `VERSION_FILE` variable
- **steel**: Add post-implementation review gate (automatic sentinel/iridium/cobalt/flint on relevant changes)

---

## [1.1.0] — 2026-04-10

### Added
- **3 new agents**: iridium (performance reviewer), cobalt (dependency expert), flint (test engineer)
- **6 new hooks**: pre-compact (PreCompact), subagent-start (SubagentStart), subagent-stop (SubagentStop), rate-limit-resume (StopFailure), session-start (SessionStart), session-end (SessionEnd)
- **2 new skills**: wiki (project knowledge base), learn (pattern extraction)
- **3 new commands**: /wiki-update, /notify-setup, /learn
- **Wiki system**: auto-maintained project knowledge base (architecture, conventions, decisions)
- **Rate limit auto-resume**: auto-resumes up to 3 times on rate limit, then stops
- **Notification system**: desktop, Slack, and Discord webhook support via /notify-setup
- **Learn/skillify**: extract reusable patterns from sessions into skill files
- **API contract review** section added to gauge agent
- Hook coverage expanded from 3 to 9 event types (added StopFailure, SessionStart, SessionEnd)

### Changed
- Agent count: 11 → 14
- Hook count: 11 → 17
- Skill count: 8 → 10
- Command count: 10 → 13
- Memory files: 11 → 14
- session-notify.sh now supports Slack and Discord webhooks

---

## [1.0.0] — 2026-04-04

### Initial Release

**11 agents** named after materials — each with properties that match their role:
- **steel** (opus) — orchestrator
- **tungsten** (opus) — autonomous executor
- **quartz** (opus) — architecture consultant (read-only)
- **carbon** (sonnet) — strategic planner
- **gauge** (sonnet) — code/plan reviewer
- **mercury** (haiku) — fast codebase search
- **graphene** (sonnet) — external docs research
- **prism** (sonnet) — ambiguity detector
- **spectrum** (sonnet) — image/PDF analysis
- **sentinel** (opus) — security reviewer (read-only)
- **titanium** (sonnet) — context recovery

**8 skills:**
- git-master, frontend-ui-ux, dev-browser, code-review, review-work, ai-slop-remover, tdd-workflow, verification-loop

**10 commands:**
- `/ignite`, `/loop`, `/halt`, `/alloy`, `/unalloy`, `/handoff`, `/refactor`, `/init-deep`, `/start-work`, `/status`

**11 hooks** (all automatic):
- write-guard, branch-guard, comment-checker, typecheck, lint, auto-install, agent-reminder, skill-reminder, todo-enforcer, loop-stop, session-notify

**4 install modes:**
- `alloy` / `unalloy` — global toggle (recommended)
- `/plugin install` — Claude Code marketplace
- `bash install.sh --project .` — per-project
- `bash setup-global.sh` → `/alloy-init` — global command

**Key features:**
- One-command global activation (`alloy` / `unalloy`)
- Settings merge preserves existing Claude config
- Block-once todo enforcer (reminds once, then allows stop)
- Per-agent persistent memory (cross-session learning)
- jq dependency check on all hooks (no silent failures)
- Safe JSON construction via `jq -n --arg`
- Cross-platform (macOS + Linux)
- Agent usage footer on every response

---

## License

MIT
