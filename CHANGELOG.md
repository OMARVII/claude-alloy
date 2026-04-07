# claude-alloy — Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
