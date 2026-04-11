# claude-alloy — Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
