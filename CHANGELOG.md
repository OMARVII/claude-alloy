# claude-alloy — Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.6.0] — 2026-04-17

### Added
- **HUD statusline** (`hooks/statusline.sh`): Bash-native one-line status bar. Pure-config, no runtime. Reads Claude Code session JSON on stdin; reuses the existing `.alloy-state/tool-count-*` counter. Shellcheck clean, ~43ms median wall-clock. Segments:
  - `[alloy X.Y.Z]` version tag (reads from `.claude-plugin/plugin.json` via `CLAUDE_PLUGIN_ROOT`)
  - `[IGNITE]` badge when IGNITE mode is active
  - Model display name (e.g. `Opus 4.7`)
  - Git branch with dirty marker (`⎇ feature/foo*`) + worktree name when inside a worktree
  - Context percentage with 3-tier fallback: (1) `.context_window.used_percentage` from stdin, (2) `input_tokens + cache_read + cache_creation / context_window_size`, (3) tool-count heuristic. Model-aware via Claude-reported window size — no hardcoded 200k/1M limits
  - Session cost + hourly burn rate (`$0.47 ~$1.4/h`) computed from `.cost.total_cost_usd` and `.cost.total_duration_ms`. Burn rate hidden for sessions under 1 minute
  - Always-on 5-hour and 7-day rate-limit quotas (`5h:23% @14:30 7d:12%`) with wall-clock reset tag on 5h from `.rate_limits.five_hour.resets_at` (epoch → `date -r` on macOS / `date -d @` on Linux). Green/yellow/red color gradient at 70%/90% thresholds
  - Lines-changed delta (`+410/-89`) from `.cost.total_lines_added` / `_removed`
  - Session duration (`session:19h23m`) from `.cost.total_duration_ms`
  - Tool-call counter (`⚒N`) — the same counter `context-pressure.sh` maintains
  - `COMPACT SOON` warning at context ≥85%; `!200k` overflow warning when `.context_window.exceeds_200k_tokens` is true
  - CWD basename (colorized)
- **context-pressure hook** (`hooks/context-pressure.sh`): PostToolUse hook that counts tool calls per session and injects advisory warnings at 70% (~100 calls) and 85% (~140 calls) context thresholds. Non-blocking, state cleaned up after 24h. Derives `SESSION_ID` from stdin (not env var) so counter path matches what `statusline.sh` reads. Atomic write via `.tmp` + `mv` to prevent half-written counters if the hook is killed.
- **/assess command** (`commands/assess.md`): Project health scanner that rates Claude Code maturity 0–10 (Terminal Tourist → Swarm Architect) by auditing CLAUDE.md, MCP servers, skills, commands, hooks, tests, lint config, and agent memory. Prints scoring card + specific next-step recommendations.
- **pipeline skill** (`skills/pipeline/SKILL.md`): Guide for headless batch processing with `claude -p`. Covers fan-out patterns, tool scoping via `--allowedTools`, output formats, auto mode, and parallel processing. Generates ready-to-run bash scripts from user descriptions.
- **Background reviewer agents**: sentinel, cobalt, flint, and iridium now declare `background: true` frontmatter, so Claude Code runs them concurrently without blocking the main conversation. Matches alloy's parallel-review model without requiring orchestrator opt-in per call.

### Changed
- **Plugin-safe agent permissions**: Removed `permissionMode: plan` from all 12 reviewer/read-only agents (carbon, mercury, titanium, quartz, prism, iridium, sentinel, cobalt, flint, graphene, spectrum, gauge). Safety is now enforced purely via `tools:` + `disallowedTools:` frontmatter, which works identically across global, per-project, and plugin install paths. Previously `permissionMode` was silently ignored when installed via plugin marketplace (per Claude Code plugin restrictions); this was a real safety regression now eliminated.
- **Skill tool scoping**: All 7 alloy skills declare `allowed-tools:` frontmatter for explicit capability scoping. `dev-browser` and `pipeline` additionally use `disable-model-invocation: true` — invoked only on explicit user request, never autonomously.
- **Plugin metadata**: `plugin.json` description updated for new counts; expanded `keywords`. `marketplace.json` gains `$schema`, `category: productivity`, and `tags` for marketplace discoverability.
- **README positioning**: New tagline ("Claude Code with a team"), "How This Compares" table vs oh-my-openagent and oh-my-claudecode, model-tiering emphasis, star history chart, star CTA.
- **CLAUDE.md link**: The `alloy` one-liner now links to Anthropic's Claude Code docs.

### Fixed
- **`activate.sh` statusLine merge**: Merge logic now preserves `statusLine` when merging with pre-existing user settings, matching the pattern used for `hooks` and `env`.
- **`SESSION_ID` parity** (`hooks/context-pressure.sh`): Hook previously read `$CLAUDE_SESSION_ID` from env, which diverged from stdin `.session_id` in some Claude Code builds. Counter file path now derives from stdin, matching what `statusline.sh` reads. This was the root cause of `⚒0` showing even when the session had many tool calls.

### Security
- **`SESSION_ID` path-traversal gate** (`hooks/context-pressure.sh`): CWE-22 defense — rejects session IDs that aren't `[A-Za-z0-9_-]+` before using them in filesystem paths under `~/.claude/.alloy-state/`.
- **`resets_at` numeric gate** (`hooks/statusline.sh`): CWE-88 defense in depth — `rate_limits.*.resets_at` from stdin is gated through `^[0-9]+$` before being passed to `date -r` / `date -d`, preventing flag-injection (`--help`, `-d`) from malformed JSON. Not exploitable (bash variable expansion doesn't re-tokenize), but hardening is free.

---

## [1.5.0] — 2026-04-15

### Added
- **doctor.sh**: New health check command — validates agents, skills, commands, hooks, symlinks, settings, manifest, version, and MCP servers. Exit 0 = healthy, non-zero = problems. Run via `alloy --check` or `bash doctor.sh`
- **--version flag**: `alloy --version` shows installed version (short-circuits before self-update). Shows repo vs installed version when they differ
- **.alloy-meta**: JSON metadata file tracking install mode and version (`{"install_mode":"symlink","version":"1.5.0"}`)
- **README.md**: Added "Updating" section covering global update flow, per-project update, auto-update opt-out, and troubleshooting guide

### Changed
- **activate.sh**: Global installs use symlinks by default (macOS/Linux). WSL/Windows auto-detected and falls back to copy mode. Probe test verifies symlink support on the actual filesystem
- **activate.sh**: Atomic manifest write — writes to `.tmp` then `mv` on success, preventing corrupt manifests on failure
- **activate.sh**: `install_file()` detects customized files before converting copy to symlink — backs up as `.user-backup` and warns
- **activate.sh**: `--version` and `--check` flags short-circuit before self-update.sh and jq check
- **self-update.sh**: Mode-aware success messaging — symlink mode says "changes are live immediately", copy mode says "run alloy to apply"
- **self-update.sh**: Divergence warning now includes exact fix command (`git pull --rebase origin main`)
- **setup-global.sh**: Copies VERSION file to alloy-dist payload. Warns when dist payload is stale before refreshing

### Fixed
- **deactivate.sh**: Handles broken symlinks during cleanup (`[ -f ] || [ -L ]` instead of `[ -f ]` alone)
- **deactivate.sh**: Cleans up `.alloy-meta` and `.alloy-manifest` on deactivation
- **activate.sh**: Non-atomic `ln -sf` replaced with `ln -s .tmp && mv` — eliminates ENOENT window during symlink updates
- **activate.sh**: Version tracking switched from `git describe --tags` to `VERSION` file — consistent across branches and forks
- **install.sh**: Global path was missing `.alloy-meta` creation — metadata now written for both `--project` and global installs
- **install.sh**: Global path had no manifest tracking — all installed files now tracked for clean uninstall
- **install.sh --uninstall**: `.alloy-meta` was not cleaned up on uninstall
- **CI**: Backup test wrote through symlink instead of creating regular file — `rm -f` before `echo` fixes it
- **CI**: `.user-backup` file left behind caused deactivate emptiness assertion to fail

---

## [1.4.1] — 2026-04-14

### Fixed
- **ignite-stop-gate.sh**: Stop hook JSON output included invalid `hookSpecificOutput` field — caused "Hook JSON output validation failed" error on session exit. Removed wrapper; now outputs correct `{decision, reason}` schema.
- **todo-enforcer.sh**: Same invalid `hookSpecificOutput` field in Stop hook blocking output. Fixed to match Claude Code's Stop hook JSON schema.

### Added
- **install.sh + activate.sh**: `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1` env var added to settings — removes built-in git workflow instructions and git status snapshot from system prompt, saving tokens (alloy's own CLAUDE.md provides equivalent guidance)

### Changed
- **.claude-plugin/plugin.json + marketplace.json**: Bump stale version from 1.3.0 to 1.4.1

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
