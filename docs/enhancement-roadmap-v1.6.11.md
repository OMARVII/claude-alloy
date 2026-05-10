# claude-alloy Enhancement Roadmap — v1.6.11+

Synthesized from competitive analysis (oh-my-openagent-dev) + internal audit (May 2026).

## Executive Summary

claude-alloy is **diverging** from oh-my-openagent — not lagging. We chose pure-config / Claude-only / precision-routing; they chose multi-model / TypeScript runtime / aggressive parallelism. Both are valid bets.

External research (graphene) found Claude Code shipped **10 platform features in the last 60 days** we don't yet exploit. These are FREE wins. Internal audit found **5 stale items** + **3 agent-prompt bloat issues**. oh-my-openagent has **6 hooks** that translate cleanly to bash.

---

## Tier 0 — Adopt new Claude Code platform features (May 2026) — FREE WINS

These exploit features Anthropic shipped in the last 60 days. All low-effort, high-impact.

| # | Feature | What we change | Why | Effort |
|---|---|---|---|---|
| P1 | `alwaysLoad: true` on critical MCPs | settings.json — pin context7/grep_app/websearch | Tool Search defers MCP schemas; deferred tools weren't available to forked subagents on first turn (May bug) | 5 min |
| P2 | `effort.level` / `$CLAUDE_EFFORT` in hooks | Wire into hooks.json — only fire heavy hooks (sentinel, iridium) on high-effort turns | Skip review chains on haiku micro-tasks. Saves cycles. | 30 min |
| P3 | `PostToolUse.updatedToolOutput` mutation | NEW hook: structured-output-injector — strips noise from subagent Bash output | Was MCP-only; now works for all tools. Cleaner subagent handoffs without prompt changes. | 1 hour |
| P4 | Outcomes-Rubric pattern (`rubric:` frontmatter) | Add `rubric:` field to agents; gauge evaluates against it post-tungsten | Anthropic benchmarks show +8-10% task success. Game-changer for verification. | 2 hours |
| P5 | Prompt-cache-friendly frontmatter ordering | Reorder agents: stable role/tools/principles BEFORE dynamic content | 3x cache_creation token cut on subagent calls (May release) | 1 hour |
| P6 | `worktree.baseRef: fresh` | settings.json | Parallel tungsten runs branch from `origin/main`, not contaminated local HEAD | 5 min |
| P7 | `hard_deny` in autoMode | settings.json — patterns from existing PreToolUse hooks (force-push, DROP TABLE, rm -rf) | Settings-layer guardrails are visible without tracing hook scripts | 15 min |
| P8 | `CLAUDE_CODE_SESSION_ID` in hook scripts | Update hooks/*.sh to log session_id | Correlate multi-agent activity across parallel runs. Debug-time gold. | 30 min |
| P9 | `claude ultrareview` in CI hook | Replace fragile `claude --print` workaround | Reproducible agent-driven CI review. One line. | 15 min |

**Aggregate effort:** ~5-6 hours. **Aggregate impact:** harness leapfrogs everyone using May 2026 platform features.

---

## Tier 1 — Hygiene (HIGH impact, LOW effort) — fix this PR

| # | Item | Defect | Fix | Effort |
|---|---|---|---|---|
| H1 | `/pipeline` skill | Claims `claude -p` headless mode that does NOT exist in current Claude Code | **DELETE** | 5 min |
| H2 | `/init-deep` command | References `.claude/skills/` and `.claude/commands/` (we use `/skills` and `/commands`) | Path fix | 5 min |
| H3 | `/ig` command | 7 lines that just redirect to `/ignite`. Keyword-detector hook handles `ig` already | **DELETE** + keep keyword | 2 min |
| H4 | `/notify-setup` | References `~/.claude/.alloy-state/` directory that no hook ever creates | Either remove or wire up state dir | 30 min |
| H5 | `/wiki-update` | Assumes `.claude/wiki/{architecture,conventions,decisions}.md` exists; no scaffolding creates them | Add graceful "skip if no wiki" or scaffolding | 30 min |
| H6 | CLAUDE.md (project) | Header says "deprecated, ~/.claude/CLAUDE.md is source of truth" then defines harness. Contradictory | Remove deprecation notice OR clarify role | 5 min |

**Aggregate effort:** ~1 hour. **Aggregate impact:** removes embarrassing bugs new users would hit immediately.

---

## Tier 2 — Agent prompt tightening (HIGH impact, MEDIUM effort)

| # | Agent | Defect | Fix |
|---|---|---|---|
| A1 | **steel** (286 lines, BLOATED) | Phase 0 intent reset + Step 0-2 + Phase 2A all restate the same delegation logic | Merge into one decision tree. Target ~180 lines. |
| A2 | **steel** | No structured-output mandate. Responses are freeform | Mandate `[Findings] / [Blockers] / [Next Steps]` for non-trivial reports |
| A3 | **carbon ↔ prism** | Carbon never references prism findings; prism never says how output flows to carbon | Add explicit prism→carbon handoff protocol; carbon: "if prism flagged risks, address each" |
| A4 | **carbon** | Interview gate fires for every plan, even trivial 3-line tweaks | Add "SKIP interview if scope < 30 min" rule |
| A5 | **tungsten** | "DO NOT ASK" too dogmatic — blocks legit "strategy A or B?" questions | Soften to "MUST justify the ask" |
| A6 | **sentinel** | 7-item checklist with no priority — checks all 7 even on a CSS change | Risk-priority ordering: auth > injection > secrets > crypto > validation > deps > infra |
| A7 | **quartz** | Templates suggest format but don't enforce; no fallback for simple Qs | Add 4th "clarification" template + depth-scaling rule |
| A8 | **ALL agents** | Inconsistent output structure — each defines its own format | Converge on shared `[Summary] / [Findings] / [Next Steps] / [Blockers]` template via `_review-template.md` |

**Aggregate effort:** ~3-4 hours. **Aggregate impact:** every IGNITE turn becomes ~15-20% more efficient (fewer reread cycles, less ambiguity).

---

## Tier 3 — New hooks ported from oh-my-openagent (HIGH impact, MEDIUM effort)

oh-my-openagent has 50+ hooks vs our 23. These six translate cleanly to bash and add real value:

| # | Hook | What it does | Why we need it | Effort |
|---|---|---|---|---|
| N1 | **webfetch-redirect-guard** | Blocks WebFetch following redirects to different hosts (open-redirect / SSRF risk) | Security improvement on already-allowed websearch/grep_app/context7 surface | 30 min |
| N2 | **read-image-resizer** | Auto-resizes oversized images before they hit the Read tool | Users routinely paste 4MB screenshots; we OOM context | 45 min |
| N3 | **json-error-recovery** | Catches malformed-JSON tool errors and prompts agent to retry with structured fallback | Saves a turn on every tool-call schema flake | 45 min |
| N4 | **preemptive-compaction-trigger** | Triggers `/compact` BEFORE hitting hard limit (we only WARN at 70/85% via context-pressure) | Avoid unrecoverable mid-task overflow | 60 min |
| N5 | **edit-error-recovery** | Catches Edit tool "old_string not found" failures and re-Reads the file | Common failure mode in long sessions | 30 min |
| N6 | **directory-readme-injector** | Auto-injects nearby README.md when agent reads files in a subdir | Cheap context win for monorepos | 30 min |

**Aggregate effort:** ~4 hours. **Aggregate impact:** measurably fewer wasted turns on flaky tool calls + context overflows.

---

## Tier 4 — New skills (HIGH impact, HIGH effort) — pick 1-2 to ship in v1.6.11

| # | Skill | What it does | Why it's valuable | Effort |
|---|---|---|---|---|
| S1 | **hyperplan** | 5-way adversarial planning team (skeptic / validator / researcher / architect / creative) → 3-round debate → distill → handoff to carbon | We have carbon for planning but no adversarial cross-critique. This is genuinely novel. | 4-6 hours |
| S2 | **github-triage** | Read-only GitHub issue/PR analyzer; 1 issue = 1 background agent; every claim requires permalink | Currently no GitHub triage; users do this manually | 3-4 hours |
| S3 | **work-with-pr** | Full PR lifecycle: worktree → implement → atomic commits → create PR → CI/review/lint gates → merge → cleanup | We have `/git-master` for commits but no end-to-end PR skill | 4-5 hours |
| S4 | **pre-publish-review** | Multi-agent release gate: detect unpublished changes → spawn ultrabrains per-change → holistic review → oracle synthesis | Useful for npm-publishing projects (ours, theirs) but niche | 4-6 hours |
| S5 | **remove-deadcode** | LSP-verified dead-code removal with orchestrator pattern (no removal without `LspFindReferences`) | Safer than ai-slop-remover for dead code specifically | 3-4 hours |

---

## Tier 5 — Speculative / architectural (HIGH impact, VERY HIGH effort)

| # | Idea | Why interesting | Why hard |
|---|---|---|---|
| X1 | **Hashline-style edit verification** — content hashes anchor every Edit (LINE#ID format) | Their docs claim 6.7% → 68.3% edit success on Grok Fast. The killer feature. | Requires patching the Edit tool flow via PreToolUse + state file. ~2-3 days. |
| X2 | **Modular agent prompt composition** — agents stitched from reusable sections at runtime | Their Sisyphus/Prometheus/Atlas all share section libraries; ours have copy-pasted boilerplate | Requires preprocessing build step. Conflicts with our "pure config, no runtime" promise. |
| X3 | **Extended thinking integration** — explicit `thinking: { type: "enabled", budgetTokens: 32000 }` for opus agents | Sisyphus does 32k thinking on hard problems. We don't expose this. | Need to research if Claude Code agent frontmatter supports thinking config in May 2026. |
| X4 | **Multi-model fallback** — when Opus quota hit, route to Sonnet automatically | Their model-fallback hook is mature | Conflicts with our "Claude-only, no API key juggling" thesis. Skip. |
| X5 | **Team mode (parallel mailbox)** — agents coordinate via shared filesystem mailbox | Their team-mailbox-injector hook | Heavy. Needs real-time coordination. Multi-day effort. Skip unless we want to compete head-on. |

---

## Anti-Roadmap (things we should NOT do)

- ❌ **Multi-model orchestration** (Kimi/GLM/GPT). Conflicts with our "Claude-only, deliberate tiering" thesis. Lock-in is the point.
- ❌ **TypeScript runtime / compiled binaries**. Our pitch is "pure config, audit every line of bash." Don't break it.
- ❌ **Telemetry**. They have it. We've explicitly said we won't.
- ❌ **More agents (15th, 16th)**. We're at 14 — curated. Adding without removing dilutes.
- ❌ **Agent-browser CDP / cloud / iOS / Rust**. Out of scope for a config harness.

---

## Our advantages oh-my-openagent does NOT have (don't lose these)

- ✅ `/ignite` keyword + enforcement hooks (ignite-detector, ignite-stop-gate)
- ✅ `/loop` autonomous-completion mode + `loop-stop` hook
- ✅ `branch-guard` (block edits on main/master)
- ✅ `/assess` project-health scoring
- ✅ `/learn` pattern extraction → skills
- ✅ `/handoff` ↔ `/start-work` session pairing
- ✅ Per-agent memory files (`agent-memory/<agent>/MEMORY.md`)
- ✅ HUD statusline
- ✅ `unalloy` reversibility — surgical, no residue

These are genuinely unique. Lean into them in the README.

---

## Recommended v1.6.11 Scope

**Ship:** all of Tier 1 (H1-H6), most of Tier 2 (A1-A5, A8), and 2-3 Tier 3 hooks (N1, N3, N4).

**Defer:** Tier 4 skills to v1.7. Pick 1 (hyperplan recommended — most novel).

**Reject:** Tier 5 speculative items unless we want to compete on multi-model.

Estimated total effort for v1.6.11: **~8-10 hours**, single tungsten dispatch.
