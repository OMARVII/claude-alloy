# claude-alloy — Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added

### Changed

### Fixed

---

## [1.7.0] — 2026-05-12

> **IGNITE stop-gate accuracy + platform-feature adoption.** Three platform alignments and one stop-gate fix close the IGNITE false-positive class, gate user-mode skills against auto-invocation, and protect tungsten runs from mid-task compaction. A follow-up polish pass tightens the subagent hook contract end-to-end (defense-in-depth sanitization, fewer jq forks across three hooks, a stronger traversal test, a load-bearing legacy-fallback assertion), adds four more platform features (`worktree.symlinkDirectories`, `/unalloy` integration with `claude project purge`, IGNITE `sessionTitle` injection, and `--plugin-url` ephemeral install docs), retires the dead `mcpServers` block in `settings.json`, aligns per-agent `effort` tiers to documented cost-discipline targets, auto-activates IGNITE on `--effort max` sessions, documents the native `/goal` vs alloy's `/loop` (with a README pointer), and surfaces three previously-undocumented TTL env vars, and adds a postinstall hint to both installers surfacing the `.mcp.json.example` template so users have an in-stream signal that MCP pinning is still supported (just relocated to `.mcp.json` scope after the dead `settings.json` block was retired). Tests grow to 239 across a new SubagentStart/SubagentStop suite that pins the documented-field contract, a positive-control traversal assertion, a load-bearing agent-count ledger check on legacy payloads, the new IGNITE `sessionTitle` first-fire contract, a positive-control assertion that the IGNITE `sessionTitle` strips ASCII control bytes, three effort-tier auto-IGNITE assertions covering max/high/medium gating, three paired stdout-validation assertions proving the effort-tier auto-IGNITE path emits the same `hookSpecificOutput.sessionTitle` protocol context as keyword-IGNITE (or correctly emits no protocol context at sub-max tiers), two `args[]` field assertions in `tests/settings-generation.sh` guarding the generated hook-entry schema across both install and activation paths, a new `tests/comment-checker.sh` suite proving the warn-only default plus the opt-in `ALLOY_BLOCK_AI_SLOP` recoverable-block path (decision/continueOnBlock/reason shape), a new `tests/lint.sh` suite that stubs `npx` on PATH to prove the lint hook emits `hookSpecificOutput.updatedToolOutput` (summary line) and `additionalContext` (detail) as siblings on every linter run while staying silent in the opt-out default, two pre-publish assertions in `tests/settings-generation.sh` that lock the dead `mcpServers` block out of both the project-install path and the global-activation merge path (catches future template drift that would re-emit it), three more pre-publish assertions in the same suite that pin the canonical skill-count metadata (`doctor.sh` `SKILLS` variable tokenizes to include `hyperplan`, and both plugin manifest descriptions advertise the correct count), and two paired postinstall-output assertions in `tests/settings-generation.sh` that capture stdout from both the project-install and global-activation paths and lock in the `.mcp.json.example` hint string so a future refactor that strips the closing `info()` block is caught by the suite rather than by users.

### Added
- **`hooks/pre-compact.sh` — blocks compaction during IGNITE+tungsten runs.** When both `ignite-active-${SESSION_ID}` (TTL 7200s, override `ALLOY_IGNITE_TTL`) and `tungsten-active-${SESSION_ID}` (TTL 1800s, override `ALLOY_TUNGSTEN_TTL`) are fresh, the hook emits the documented top-level `{"decision":"block","reason":...}` envelope so Claude Code defers compaction. Outside those conditions the hook stays advisory. Auto-compaction mid-tungsten would otherwise truncate the agent's planner state, file paths, and live todo set just as it's actively reasoning about them; outside IGNITE that's an acceptable trade-off (the user can `/resume`), inside IGNITE the user has opted into a high-context regime where mid-task compaction is far more damaging than postponing it. Docs: <https://code.claude.com/docs/en/hooks> (PreCompact decision control).
- **`settings.json` — `skillOverrides` for IGNITE-mode skills.** Gates `ignite`, `ig`, `loop`, and `halt` to `user-invocable-only` so Claude does not auto-invoke them from inferred intent. These are behavioral modes the user opts into deliberately — auto-invoking them from a loose intent match would change the entire run posture. Other skills (`git-master`, `code-review`, `frontend-ui-ux`, etc.) remain auto-discoverable. The new keys are emitted by both `install.sh --project` and `activate.sh` (global). Requires Claude Code v2.1.129+. Docs: <https://code.claude.com/docs/en/settings#skillOverrides>.
- **`settings.json` — `worktree.symlinkDirectories` for cheap parallel worktrees.** Pairs with the existing `worktree.baseRef: fresh` to keep parallel tungsten worktree spin-up cheap: instead of copying `node_modules`, `.venv`, and `.cache` (often multi-GB), the platform symlinks them into each new worktree. Default array is `["node_modules", ".venv", ".cache"]` — the three most common large directories across the Node, Python, and general ecosystems this harness sees. Emitted by `settings.json` template, `install.sh --project`, and `activate.sh` (global merge). Pinned in `tests/settings-generation.sh` so a generator regression flips the test. Docs: <https://code.claude.com/docs/en/settings> (worktree section).
- **`tests/subagent-hooks.sh` — focused suite for SubagentStart/SubagentStop schema.** Pins the documented-field contract: documented `agent_type` is read correctly, legacy `subagent_type` payloads still surface via the fallback chain in both `subagent-start.sh`'s global log AND `agent-count.sh`'s load-bearing per-session ledger, the tungsten-active marker is cleared only when `agent_type==tungsten`, sibling agent stops leave the marker untouched, and a paired traversal assertion proves the sanitizer collapses `../evil` → `evil` (an in-state-dir target is removed) while the outside-state-dir marker remains untouched. Additional cases pin embedded-slash sanitization (`a/b/c` → `abc`) and the agent_id defense-in-depth path. Twelve assertions total.
- **`commands/unalloy.md` — optional `claude project purge` cleanup step.** `/unalloy` already removes the alloy files inside the project; Claude Code itself caches per-project state (transcripts, task lists, debug logs, file-edit history, prompt history, the project entry in `~/.claude.json`) outside the project directory. Adds an optional step that surfaces `claude project purge "$PWD" --dry-run` then `claude project purge "$PWD"`, with rationale for when to run it (leaving a repo permanently) and when to skip it (swapping harnesses on the same repo). Cited the public docs URL for the `claude project purge` row.
- **`hooks/ignite-detector.sh` — UserPromptSubmit emits `hookSpecificOutput.sessionTitle` on the first IGNITE activation per session.** Claude Code's UserPromptSubmit hook contract permits a `sessionTitle` field that renames the session in the sidebar; the detector now sets it to a flame-prefixed 40-char prefix of the triggering prompt the first time IGNITE fires in a session. A per-session marker (`${STATE_DIR}/ignite-titled-${SESSION_ID}`) gates the field so follow-up IGNITE prompts in the same session continue to inject the protocol context without re-emitting the title — the resulting JSON stays lean and the marker doubles as a debugging signal. Two assertions in `tests/ignite-detector.sh` pin the contract: the first IGNITE prompt emits `sessionTitle`, and non-IGNITE prompts emit no `sessionTitle` at all (the detector exits before producing output). Docs: <https://code.claude.com/docs/en/hooks> (UserPromptSubmit hookSpecificOutput fields).
- **`README.md` — ephemeral install path via `--plugin-url`.** A fifth row joins the Install Modes table alongside the global toggle, plugin add, per-project, and global-command flows. Claude Code's `--plugin-url` flag fetches a plugin .zip archive for a single session without writing anything to disk; the new "Try it ephemerally (no install)" subsection documents the canonical release-asset URL pattern (`https://github.com/OMARVII/claude-alloy/releases/download/v1.7.0/claude-alloy.zip`) and the trade-off — useful for testing a release candidate or trying alloy on a one-off task without committing to a full install. The URL becomes valid once the v1.7.0 release ZIP is published. Docs: <https://code.claude.com/docs/en/cli-reference>.
- **Eight read-only review/planner agents adopt `isolation: worktree`.** `sentinel`, `iridium`, `flint`, `cobalt`, `gauge`, `quartz`, `carbon`, and `prism` now run in a temporary git worktree per the documented Claude Code sub-agents frontmatter field — the worktree is automatically cleaned up when the agent makes no changes, which is the expected case for read-only review and planning. Excluded: `steel` (main orchestrator), `tungsten` (writes code — must share the parent's working tree), `mercury` (search needs the parent's live tree state), `graphene`/`spectrum` (no codebase access — isolation is pure overhead), `titanium` (context recovery — needs parent transcripts). Docs: <https://code.claude.com/docs/en/sub-agents> (Supported frontmatter fields → `isolation`).
- **Per-agent `effort` field aligned to cost-tier discipline.** Claude Code's sub-agent frontmatter accepts an `effort` field (`low | medium | high | xhigh | max`) that overrides the session effort level. All 14 alloy agents already carry the field; this release tunes the values so review and planning agents no longer silently inherit a heavier tier than their workload needs. `tungsten` stays at `max` (autonomous multi-file builds), `steel`/`sentinel`/`quartz`/`carbon` at `high` (orchestration, security depth, architecture reasoning, strategic planning), the four review agents (`iridium`, `flint`, `cobalt`, `gauge`) plus `prism`/`titanium`/`graphene`/`spectrum` at `medium`, and `mercury` at `low` (haiku search — minimal token spend). Docs: <https://code.claude.com/docs/en/sub-agents> (Supported frontmatter fields → `effort`).
- **`hooks/ignite-detector.sh` — `--effort max` sessions auto-activate IGNITE protocol.** Claude Code v2.1.133+ exposes the session effort level to hooks via the `$CLAUDE_EFFORT` env var and (for tool-use events) the `effort.level` JSON field. When the user opts into the top tier, IGNITE's discipline (6+ background agents, mandatory graphene, post-implementation review fan-out, no partial delivery) is exactly the run posture they're asking for — requiring them to also type `ig`/`ignite` is friction without upside. The detector reads `$CLAUDE_EFFORT` first (always available to hooks) with a defensive fallback to `.effort.level` from JSON stdin. Three assertions in `tests/ignite-detector.sh` pin the contract: `max` activates on a plain non-keyword prompt, `high` and `medium` do not. Docs: <https://code.claude.com/docs/en/hooks> (common hook input fields → `effort`).
- **`hooks/comment-checker.sh` — opt-in recoverable AI-slop blocking via `ALLOY_BLOCK_AI_SLOP=1`.** Per Claude Code v2.1.139, PostToolUse hooks can pair `decision:"block"` with `hookSpecificOutput.continueOnBlock:true` to surface a rejection that feeds back into Claude as context in the SAME turn — block + reason + additionalContext arrive together, the rewrite happens immediately instead of in a follow-up exchange. When `ALLOY_BLOCK_AI_SLOP=1`, slop detection emits the recoverable-block shape; the file on disk is untouched, the rewrite simply gets immediate priority. Default behavior is unchanged (warn-only via `additionalContext`, exit 0) because forcible blocking on slop can derail unrelated work (e.g. urgent bug fix in a file with pre-existing slop comments). PreToolUse guards (`write-guard.sh`, `branch-guard.sh`) are NOT affected — they remain hard-block on rejection, since `continueOnBlock` would weaken their security semantics. A new `tests/comment-checker.sh` exercises four paths: warn-only default produces `additionalContext` with no `decision`, opt-in produces `decision:block` + `continueOnBlock:true` + descriptive `reason`, opt-in on a clean file is silent, and explicit `ALLOY_BLOCK_AI_SLOP=0` matches the default. Docs: <https://code.claude.com/docs/en/hooks> (Decision control → `continueOnBlock`).
- **`hooks/lint.sh` — emits `hookSpecificOutput.updatedToolOutput` summary alongside the existing detail context.** Claude Code v2.1.121+ documents `updatedToolOutput` as a STRING that replaces the tool's output in the conversation surface (file on disk unchanged). The lint hook now pairs the two fields as siblings on every linter run: `additionalContext` continues to carry the verbose first-10-issue detail (Claude sees the full diagnostics), while `updatedToolOutput` carries a single-line summary — `Lint: clean (1 file, <X>s)` on success and `Lint: <N> error(s), <M> warning(s) in <basename>. First: <line>` on failure. The summary keeps the conversation surface readable when many lint runs accumulate. No behavior change for the early-exit paths (low-effort tier, `ALLOY_AUTO_LINT` unset, no `package.json`, cooldown active, lock contention) — those return silently as before. A new `tests/lint.sh` stubs `npx` on PATH (no network, no real linter install) and asserts the error path emits both fields together, the clean path emits the `Lint: clean (...)` shape, and the opt-out default stays silent. Docs: <https://code.claude.com/docs/en/hooks> (hookSpecificOutput → `updatedToolOutput`).
- **`install.sh` + `activate.sh` — postinstall hint surfacing the `.mcp.json.example` template.** After this release retired the dead `mcpServers` block from `settings.json` (the schema silently drops it — see the Fixed entry below), users had no in-stream signal that MCP schema pinning is still supported, just relocated to the `.mcp.json` scope where the schema actually honors it. Both installers now close with a five-line `info()` block (matching the existing voice — blue `[ALLOY]` prefix, no emoji, paired with the existing `info "Start: claude"` / `info "Type /ignite"` lines) that names the three pinned MCPs (`context7`, `grep_app`, `websearch`), gives the `cp .mcp.json.example .mcp.json` command for project scope, mentions the `~/.claude.json` merge path for user scope, and points at `docs/mcp-config.md` for the full guide. The hint emits at the end of `install.sh --project`, the end of the global `install.sh` path, and the end of the `activate.sh` success path — three sites covering every fresh install surface. `README.md` gains a single-line breadcrumb in the Per-project install section pointing at the same doc. Two paired assertions in `tests/settings-generation.sh` capture stdout from both installer paths (project + global activation) and lock the `.mcp.json.example` hint string in place so a refactor that strips the closing `info()` block is caught by the suite rather than by users.

### Changed
- **`CLAUDE.md` — skills and commands split into separate tables.** The previous single table mixed 10 skills (in `skills/`, auto-discoverable triggers) with 15 commands (in `commands/`, user-invoked slash commands). Splitting them removes the ambiguity that motivated the inline "/ignite, /ig, etc. are commands not skills" footnote, and aligns the index with the directory layout users actually browse.
- **`hooks/subagent-start.sh` and `hooks/subagent-stop.sh` — schema preambles reference documented fields.** Both hooks already read `.agent_type` from the platform-provided input with a fallback chain to legacy payload shapes. The preambles now name the documented field list (`session_id`, `agent_id`, `agent_type`, `transcript_path`, `cwd`, `hook_event_name`) and the canonical docs URL so future maintainers don't have to retrace the schema from runtime samples. Docs: <https://code.claude.com/docs/en/hooks>.
- **`hooks/agent-count.sh` — writes the tungsten-active marker.** On `Agent`/`Task` PostToolUse where `subagent_type==tungsten`, the hook touches `${STATE_DIR}/tungsten-active-${SESSION_ID}` so `pre-compact.sh` has a freshness signal to read. The PostToolUse path is used (not `subagent-start.sh`) because SubagentStart empirically misses some long-running parent sessions; the PostToolUse counter is the stable source the IGNITE stop-gate already trusts. `subagent-stop.sh` clears the marker when `agent_type==tungsten`.
- **Subagent hooks pre-emptively sanitize `agent_id`.** `subagent-start.sh`, `subagent-stop.sh`, and `agent-count.sh` now read `agent_id` from hook input and apply the same `[A-Za-z0-9_-]` allowlist that `session_id` already gets, even though no current code path uses `agent_id` in a filesystem path. CWE-22 defense-in-depth: any future per-agent file path (per-agent ledger, transcript pointer, dispatch trace) inherits a safe shape without a separate audit pass.
- **Hook config migrates to the `args[]` exec form across all three sources of truth.** Every command-type hook entry in `hooks/hooks.json`, `install.sh` (project-template heredoc), and `activate.sh` (jq global-merge expression) now carries an empty `"args": []`. Per the Claude Code hooks docs "Command hook fields" table, when `args` is present the platform resolves `command` as an executable and spawns it directly with `args` as the argument vector — no shell involved — which eliminates the class of shell-quoting bugs that the previous shell-form invocation was theoretically exposed to (the hooks themselves take no arguments, but flipping to direct exec is the documented forward-compatible shape). `statusLine` is unaffected — it is not a command-type hook. `tests/settings-generation.sh` continues to pass unchanged. Docs: <https://code.claude.com/docs/en/hooks> (Command hook fields → `args`).

### Fixed
- **`hooks/ignite-stop-gate.sh` — false positive from nested subagent tool_use blocks.** The previous transcript scan used `jq '.. | objects | select(.type? == "tool_use")'`, which deep-walked into `tool_result.content` blocks and surfaced nested subagent tool_use entries (echoed back into the parent transcript by Claude Code). Subagents have `Edit`/`Write` in their tool whitelist even when unused, so the gate fired "Code was edited but review agents missing" on sessions where the parent had performed zero implementation edits. Narrowed the scan to JSONL lines whose top-level `type == "assistant"` and walks only `.message.content[]` — no recursive descent. A real top-level Edit still trips the gate; nested tool_use blocks are correctly ignored. `hooks/session-end.sh` already cleans up the `code-edited-${SESSION_ID}` marker on session stop (added in v1.6.10), so the marker no longer carries over to a session id reused later.
- **`tests/subagent-hooks.sh` — traversal positive control was passing for the wrong reason.** The original `session_id="../evil"` assertion checked only that a marker outside the state dir survived. The hook sanitizes to `evil` and tries to `rm` an in-state-dir target the test never created, so the success criterion held even when the sanitizer was a no-op. Paired with a positive assertion that the sanitized in-state-dir target IS removed; added an embedded-slash case (`a/b/c` → `abc`) and an `agent_id` traversal case so all three sanitization paths are pinned.
- **`tests/pre-compact.sh` — stale-marker touch readability and portability.** The previous inline form nested the BSD/GNU `date -r` / `date -d` resolution and the BSD/GNU `touch -t` / `touch -d` fallback into one nested expression; extracting `STAMP` into a separate variable makes the cross-platform read order match the runtime order without changing behavior. Mitigates the same class of BSD-vs-GNU portability footgun that v1.6.9's `stat -c %Y` reordering fixed elsewhere.
- **`tests/thermal-runaway.sh` — reap-window guard against pgrep race, applied to all three timeout blocks.** The straggler check (`pgrep -f marker` after the supervisor's pgroup kill) had a 4s reap window; on loaded macOS runners that occasionally produced a 46/47 result followed by 47/47 within minutes with no code change. Bumped the reap wait to 6s — longer than SIGTERM → 2s sleep → SIGKILL plus a 2s margin for kernel reap. The initial fix landed in the lint block only even though its commit message claimed coverage of all three; the typecheck and auto-install blocks retained the 4s window and could still flake with the same `46/47 → 47/47` retry pattern. Extended the guard to both remaining blocks and updated the lint-block rationale comment to point at the analogous sites. Adds ~6s total across three timeout blocks against a ~110s suite. Multiple back-to-back local runs return 47/47 with the full fix in place.
- **`tests/subagent-hooks.sh` — legacy-fallback assertion now exercises the load-bearing ledger.** The original legacy-payload check tailed `agent-log.jsonl` for the raw `subagent_type` field — proves the payload was logged, NOT that the hook resolved the operative agent type for the IGNITE stop-gate's "N agents spawned" read. The load-bearing file for that read is `agents-spawned-${SESSION_ID}` (written by `agent-count.sh` on every PostToolUse Agent|Task), so a regression that flipped the agent-count fallback chain to write `unknown` would still pass the old check. Added a paired assertion that pipes the same legacy payload shape through `agent-count.sh` and verifies the ledger records the operative type. Kept the original log assertion as a complementary check.
- **`hooks/ignite-detector.sh` — IGNITE `sessionTitle` strips ALL C0 control bytes.** The previous title-sanitization pass replaced only `\n`/`\r`/`\t` with spaces, letting other ASCII control bytes (0x01-0x08, 0x0B, 0x0C, 0x0E-0x1F) pass through where `jq` escapes them as `\uXXXX` in the JSON output — not exploitable but visibly ugly in the Claude Code sidebar when a prompt accidentally embeds them (terminal-capture paste, copy from a tool-output buffer). `tr -d '\000-\037'` now deletes the entire NUL-through-US range; TAB/LF/CR are included because the title field has no need for preserved whitespace structure. A positive-control assertion in `tests/ignite-detector.sh` feeds a prompt containing 0x01/0x02/0x03 through the hook and verifies the emitted `sessionTitle` contains zero bytes in the 0x01-0x1F range. Flagged LOW by `sentinel`.
- **`settings.json` — dead `mcpServers` block removed across template, both installers, and the global merge; misleading doc Option B retired.** Claude Code's `settings.json` schema does not recognize a top-level `mcpServers` key. Only the allow/deny/enable management settings (`allowedMcpServers`, `deniedMcpServers`, `enabledMcpjsonServers`, `disabledMcpjsonServers`, `allowManagedMcpServersOnly`, `enableAllProjectMcpServers`) are honored — any server definitions placed there are silently dropped. The previous `mcpServers` block in `settings.json` (which carried per-server `alwaysLoad: true` flags) was therefore dead config; it has been removed from the template, from `install.sh` (project-install heredoc and backup-merge fallback heredoc), and from `activate.sh` (settings emit + the `jq` merge expression that folded alloy's `mcpServers` into the user's existing settings). Pre-fix, the template was clean but every fresh install still injected the dead block — the CHANGELOG bullet contradicted what the installers actually did. `_comment_mcpServers` rewritten to redirect users to `.mcp.json` (project scope) or `~/.claude.json` (user scope) for the canonical declaration. `docs/mcp-config.md` had a parallel mistake — its "Option B (settings.json override)" section claimed the override worked declaratively; that section is replaced with a user-scope `~/.claude.json` walkthrough and a clear up-front note that `mcpServers` in `settings.json` is silently ignored. Two assertions added to `tests/settings-generation.sh` lock the absence in for both the project-install and global-activation merge paths so a regression that re-emits the dead block flips the suite. Reference: anthropics/claude-code#24477.
- **Skill count metadata corrected `9 → 10`; canonical lists now include `hyperplan`.** Hyperplan (5-persona adversarial planning that hands off to carbon) landed as the 10th skill in v1.6.11 but several canonical lists were never updated. Pre-fix: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` description strings advertised "9 skills"; `setup-global.sh`'s `/alloy-init` heredoc described "9 skills" and listed the nine skill names without `hyperplan`; `doctor.sh` iterated a 9-entry `SKILLS` variable and reported "All 9 skills present" on success — meaning a health check would pass an install where `hyperplan` was missing entirely. All four files now reflect the 10-skill state. Three assertions added to `tests/settings-generation.sh` lock the canonical lists in place: `doctor.sh`'s `SKILLS` variable must include `hyperplan` (tokenized check, not substring), and both plugin manifest descriptions must advertise the correct count. Historical CHANGELOG snapshots that mention "9 skills" are preserved verbatim — those describe past releases accurately.
- **`tests/ignite-detector.sh` — effort-tier assertions now exercise the protocol-emit branch.** The original three effort-tier checks (max activates, high/medium do not) only verified the `ignite-active-${SESSION_ID}` flag file — they didn't prove the hook actually emitted `hookSpecificOutput.sessionTitle` on the auto-activation path. A regression that flipped the marker file but skipped the protocol-emit branch (or wrote the title but never set the flag) would have passed silently, giving false-confidence coverage on the load-bearing field the Claude Code sidebar actually reads. Restructured `call_hook_with_effort` to capture stdout (`STDOUT_OUT`) alongside the existing flag-file presence check, then added three paired stdout assertions: `effort=max` emits `sessionTitle` (matching keyword-IGNITE's protocol context), `effort=high` and `effort=medium` emit none (hook exits early on the no-keyword + sub-max path). Uses raw `grep -c "sessionTitle"` on the captured string rather than `jq` because `jq` on empty stdin returns empty (not the `//` default), making the negative-case shape match the existing non-IGNITE `sessionTitle` block. Flagged MEDIUM by `flint`.
- **`install.sh` — heredoc-emitted hook entries now include `statusMessage` on every applicable hook.** Two near-identical heredocs in `install.sh` (project install path and the backup-merge fallback path) emit settings.json with a complete `args[]` field on every hook entry, but they omitted the `statusMessage` field that `hooks/hooks.json` and `activate.sh` (global) carry on every applicable entry. Without `statusMessage` the Claude Code status surface shows the raw script name (`agent-count.sh`) instead of the documented human-readable phase (`Counting agent dispatch...`). Users freshly installed via `install.sh` saw a different status surface than users updated via `activate.sh` — UX drift that the snapshot tests didn't catch because they assert on the matcher list, not per-entry metadata. Each entry now copies its canonical `statusMessage` from `hooks/hooks.json` verbatim; `context-pressure.sh` remains without one because the canonical sources also leave it blank (preserving the deliberate omission instead of fabricating a string).
- **`tests/settings-generation.sh` — asserts `args[]` field is present on generated command-form hook entries.** Per Claude Code v2.1.139, the `args` field is part of the command-form hook-entry schema. `hooks/hooks.json`, `install.sh`, and `activate.sh` all already emit `"args": []` on every entry, but no test previously guarded against drift — someone editing a single entry and forgetting to carry the field would silently produce a schema-incomplete `settings.json` that only fails at hook-validation time. Two new assertions walk the generated settings via `jq -e '.. | objects | select(.type == "command" and has("args"))'` for both the project-install path and the global-activation merge path; the traversal works for both flat and nested matcher structures so it catches drift anywhere in the tree.

### Performance
- **`hooks/subagent-stop.sh` — single jq pass for four fields.** Previously forked `jq` four times against the same `INPUT` (`session_id`, `agent_id`, `agent_type`, `last_assistant_message`). Each fork is ~2-5ms on macOS and adds up on a hot path that fires on every subagent exit. Merged into one `jq` call that emits the four fields newline-delimited; `sed` splits them back out. Newline-delimited (not tab-separated) avoids the `IFS=$'\t' read` collapse on empty trailing fields — `last_assistant_message` is the most likely field to be empty.
- **`hooks/subagent-start.sh` — single jq pass for three fields.** Previously forked `jq` three times to read `session_id`, `agent_id`, and `agent_type` from the same `INPUT`. Mirrors the pattern subagent-stop.sh uses: one `jq` call emits the three fields newline-delimited, `sed` splits them back out. The fallback chain for `agent_type` (`agent_type` → `subagent_type` → `tool_input.subagent_type` → `tool_use.input.subagent_type`) is preserved verbatim inside the merged filter. Saves ~2 forks per SubagentStart event.
- **`hooks/agent-count.sh` — single jq pass for four fields.** This hook fires PostToolUse on every Agent|Task dispatch — the busiest hook in an IGNITE run — and previously forked `jq` four times to read `tool_name`, `session_id`, `agent_id`, and `agent_type`. Folded into one call emitting all four fields newline-delimited. The full `agent_type` fallback chain (`tool_input.subagent_type` → `tool_input.agent_type` → `tool_input.type` → `tool_use.input.subagent_type` → `subagent_type`) is preserved verbatim. Saves ~3 forks per Agent|Task dispatch.
- **`hooks/agent-count.sh` — dropped redundant `chmod 600` on the tungsten marker.** `STATE_DIR` is created by `alloy_ensure_state_dir` with mode 0700 (atomic `install -d -m 700`); a file created inside a 0700 directory is already process-private. The `chmod 600` was a no-op for security and added one fork per `Agent`/`Task` dispatch on a hot PostToolUse path.
- **`hooks/pre-compact.sh` — cache stat flavor and current epoch once per invocation.** `is_fresh()` is called twice per event (ignite + tungsten markers) and the previous form forked three commands each call: `date +%s`, GNU `stat -c %Y`, and the BSD fallback `stat -f %m`. Detect the stat flavor and resolve `NOW_EPOCH` once at script start, then have `is_fresh()` use the cached values plus the per-file `stat` itself. Net: 1 fork per call instead of 3, saving 4 forks per PreCompact event.
- **`hooks/pre-compact.sh` — single jq pass for three fields + reuses cached `NOW_EPOCH` for the backup-dir suffix.** Two micro-perf wins that mirror the pattern already applied to `subagent-start.sh`, `subagent-stop.sh`, and `agent-count.sh`. (a) Three separate `echo "$INPUT" | jq` calls for `compaction_source`, `session_id`, and `transcript_path` collapse to one jq invocation that streams all three fields newline-delimited, sliced apart with `sed -n` — saves 2 forks and 2 jq startup costs per PreCompact event. (b) `TS=$(date +%s)` for the backup-dir suffix becomes `TS=$NOW_EPOCH`, reusing the timestamp already cached at script start for the `is_fresh()` TTL math — saves one more fork and gives a more consistent timestamp across both code paths.
- **`hooks/ignite-detector.sh` — single jq pass for three fields on the busiest UserPromptSubmit path.** Mirrors the pattern already applied to `subagent-start.sh`, `subagent-stop.sh`, `agent-count.sh`, and `pre-compact.sh`. The previous form forked `jq` three times against the same `INPUT` for `session_id`, `prompt`/`user_message`/`message`, and `transcript_path`. UserPromptSubmit fires on every user message — the fork cost adds up. Folded to one jq invocation that emits the three fields newline-delimited via `gsub("\\n";"\\\\n")` (flatten embedded newlines so `sed -n '<line>p'` extraction stays deterministic). The prompt-body field has newlines restored after extraction so the multi-line code-fence stripper still sees real `\n` boundaries; `session_id` and `transcript_path` don't contain newlines and need no restoration. Existing 26 `tests/ignite-detector.sh` assertions still pass; no behavioral change beyond the fork-count reduction.

### Documentation
- **`commands/loop.md` — `/loop` vs `/goal` distinction.** Claude Code's native `/goal <condition>` keeps the model working across turns until a condition is met with platform-side tracking; alloy's `/loop` is a hook-enforced re-entry mechanism that supports scheduled re-entry, interval pacing (`/loop 5m /foo`), and the tungsten/quartz failure routing alloy already wraps around long-running work. The two cover different needs and can be combined. Cited the docs URL for the `/goal` row.
- **`README.md` — pointer to the `/loop` vs `/goal` distinction.** The commands table row for `/loop` now links into `commands/loop.md` so users encountering `/loop` for the first time see the `/goal` alternative without needing to open the command file. The detailed comparison stays in `commands/loop.md` — the README change is a one-line breadcrumb.
- **`README.md` — three previously-undocumented TTL env vars and plugin inspection commands.** Adds `ALLOY_IGNITE_TTL` (default 7200s, freshness window for the IGNITE-active marker the stop-gate and pre-compact both read), `ALLOY_TUNGSTEN_TTL` (default 1800s, freshness for the tungsten-active marker pre-compact uses), and `ALLOY_DEBUG=1` (per-hook `[alloy]` stderr traces). New subsection at the bottom of the MCP/Tool-Search block surfaces the documented `claude plugin list` and `claude plugin validate` subcommands plus the `/plugin` slash-command UI; `claude plugin details` is not a documented subcommand and was deliberately not surfaced.

---

## [1.6.11] — 2026-05-10

> **Platform alignment + agent prompt tightening.** Adopts five verified Claude Code platform features, fixes two stale slash-command paths, and slims/standardizes 8 agent prompts. No behavior change for users who don't opt into the new settings keys; existing tests all still pass (165/165).

### Added
- **hyperplan skill — 5-persona adversarial planning that hands off to carbon.** Runs three parallel rounds (independent analysis, cross-critique, defend/refine/concede) across skeptic/validator/researcher/architect/creative personas dispatched as mercury (haiku) and graphene sub-agents, then mandatorily hands the surviving insight bundle to `@"carbon (agent)"` for executable plan formalization. Triggers on "hyperplan", "hpp", "/hyperplan", "adversarial plan", "hostile planning", "cross-critique". Steel announces `HYPERPLAN MODE ENABLED!` on activation. Brings total skill count to 10.
- **`settings.json` — `worktree.baseRef: fresh` (P6).** Parallel `tungsten` worktrees now branch from `origin/<default>` rather than local HEAD, so concurrent runs cannot inherit dirty local state from each other. Requires Claude Code v2.1.121+.
- **`settings.json` — `autoMode.hard_deny` (P7).** Settings-layer hard-deny patterns (`git push --force`, `rm -rf`, `DROP TABLE/DATABASE`, `~/.ssh|~/.aws|~/.netrc` modification) are now visible without tracing hook scripts. `$defaults` inherits Claude Code built-ins; the explicit list mirrors the destructive-action guards already in `hooks/branch-guard.sh` and `hooks/write-guard.sh`.
- **`settings.json` — `mcpServers.*.alwaysLoad: true` (P1).** Pins `context7`, `grep_app`, and `websearch` so deferred Tool Search does not strip their schemas from forked subagents on first turn. Project MCP definitions in `.mcp.json` should also set `alwaysLoad: true`; see new `docs/mcp-config.md` for the full pattern, trade-offs, and verification steps.
- **Generators (`install.sh` --project + `activate.sh` global) emit the new top-level keys.** Every fresh install now writes `worktree.baseRef`, `autoMode.hard_deny`, and `mcpServers.*.alwaysLoad` into the user's `~/.claude/settings.json` (or `<project>/.claude/settings.json`) — the project-root `settings.json` is the template, the generators are how users actually receive it. Verified end-to-end against `tests/settings-generation.sh` and the install/activate smoke flows.
- **`docs/mcp-config.md`** — explains why `alwaysLoad: true` matters, which MCPs to pin, how to declare it in either `.mcp.json` or `settings.json`, and how to verify the flag was applied.
- **`docs/ci-ultrareview.md`** — documents how to wire `claude ultrareview <pr-number> --json --timeout 30` into CI as a replacement for the older `claude --print "review"` workaround. Includes a complete GitHub Actions snippet, failure-mode handling, and rationale for why claude-alloy's own CI does NOT ship with this enabled.
- **Carbon ↔ Prism handoff protocol (A3).** `agents/prism.md` now defines an **Output Handoff** section listing the contract carbon depends on (Intent Classification, Risks table, Directives, Questions for User). `agents/carbon.md` adds an **If prism flagged risks/ambiguities** section requiring carbon to address every prism-flagged item explicitly — silent omission is now a defect.
- **Carbon — skip-interview rule (A4).** Carbon now writes a 3-line plan (Goal / Approach / Test) for trivial scope (single file, ≤2 functions, ≤50 lines added) instead of forcing the full interview. The interview gate only fires for non-trivial work.
- **Quartz — clarification template + depth-scaling rule (A7).** Adds a fourth one-paragraph response template for clarifications, sanity checks, and "is X right?" questions where the heavy Architecture/Debug/Review templates are overkill. Pairs with a depth-scaling table that ties response length to severity (CRITICAL → full template; LOW → 2-3 sentences).
- **Sentinel — explicit test-path skip (A6).** Findings inside `*test*`, `*spec*`, `*.test.*`, `__tests__/`, and `fixtures/` paths are now skipped UNLESS auth/secret-related, eliminating the noise of "SQL string concatenation in a test fixture" reports.
- **Steel — mandatory `[Findings] / [Blockers] / [Next Steps]` response template (A2).** Non-trivial reports (delegation responses, audits, IGNITE turn outputs) now wrap in this exact three-section envelope so downstream agents and the user can consume steel's output uniformly. Trivial replies stay short.
- **`_review-template.md` — shared `[Findings] / [Blockers] / [Next Steps]` wrapper (A8).** Sentinel, iridium, cobalt, flint, and gauge now reference and follow this wrapper, replacing per-agent ad-hoc shapes. Gauge's `[OKAY]`/`[REJECT]` verdict is preserved as a trailing line and mapped onto the wrapper.

### Changed
- **`agents/steel.md` slimmed 286 → 190 lines (A1).** Phase 0 intent reset + Step 0 verbalization + Phase 2A research were three different sections all restating the same delegation logic. Merged into one **Decision Tree — Run this on EVERY message** section at the top, preserving every IGNITE rule, the implementation gate, the Precision Delegation Gate, and the structured output table. Removed redundant prose and collapsed the codebase-assessment + completion tables into one-paragraph forms.
- **`agents/tungsten.md` — softened `DO NOT ASK` (A5).** Renamed to **DEFAULT TO CONTINUING**. The forbidden permission-asking patterns are still listed verbatim, but the rule now explicitly carves out two legitimate ask-cases: (a) two equally-valid paths with meaningfully different scope, (b) verified blockers requiring human authorization (credentials, destructive action). When tungsten asks, it must justify why it's not a default-decision. Two worked examples included.
- **`agents/sentinel.md` checklist reordered by risk priority (A6).** Old order (Injection → Auth → Secrets → Validation → Crypto → Deps → Infra) replaced with risk-priority order: 1. Auth & Session, 2. Injection, 3. Secrets, 4. Crypto, 5. Input Validation, 6. Dependencies (defer to cobalt), 7. Infra/Config. Sentinel can now stop walking the list once relevant categories are covered — a CSS-only change exits at category 3.
- **Agent frontmatter ordering normalized for prompt-cache reuse (P5).** Stable fields (`name`, `description`, `model`, `tools`, `disallowedTools`, `maxTurns`, `effort`) come first in every agent file; dynamic fields (`memory`, `background`, `color`, `skills`) follow. Affects: tungsten, mercury, cobalt, flint, iridium, sentinel, graphene, titanium, steel. Carbon, prism, quartz, gauge, spectrum already conformed.
- **Heavy hooks honor `$CLAUDE_EFFORT=low` (P2).** `lint.sh`, `typecheck.sh`, `agent-reminder.sh`, and `skill-reminder.sh` now exit early on low-effort turns to save cycles on haiku micro-tasks. Safety hooks (`write-guard`, `branch-guard`, `ignite-stop-gate`, `todo-enforcer`) and the IGNITE-supporting `edit-ledger.sh` are deliberately exempt — they always fire. `comment-checker.sh` is also exempt because its job is content-policy enforcement (blocks AI-slop comments) regardless of effort tier.

### Fixed
- **`/notify-setup` — missing state-dir creation (H4).** The command referenced `~/.claude/.alloy-state/notify-config.json` (the canonical path used by `hooks/session-notify.sh`) but never created the parent directory, so the very first invocation failed silently. Added an explicit `mkdir -p ~/.claude/.alloy-state && chmod 700 ~/.claude/.alloy-state` step at the top, matching the convention used by every state-writing hook.
- **`/wiki-update` — wrong wiki path (H5).** The command referenced `.claude/wiki/` but the actual wiki lives at `wiki/` at project root (and always has — `wiki/architecture.md`, `wiki/conventions.md`, `wiki/decisions.md`, `wiki/index.md` are all present). Path corrected throughout.

### Security
- **`/notify-setup` writes `notify-config.json` mode 0600 (S1, CWE-732).** Slack and Discord webhook URLs are bearer credentials — anyone holding the URL can post to the channel. The previous step wrote the file at the user's default umask (typically 0644), making credentials world-readable on shared hosts. Fixed by wrapping the write in a `umask 077` subshell and following with an explicit `chmod 600`. State-dir creation upgraded from `mkdir -p && chmod 700` to atomic `install -d -m 700` to close the TOCTOU window.
- **`autoMode.hard_deny` expanded to cover the autonomous-mode threat surface (S2).** The original five patterns (`git push --force`, `rm -rf`, `DROP TABLE/DATABASE`, `~/.ssh|~/.aws|~/.netrc`) left several high-impact destructive actions unconstrained when running in agent-only auto mode. Added eight categories: pipe-to-shell from the network (`curl | sh`, `wget | bash`), privilege escalation (`sudo`, `doas`), credential reads (`~/.gnupg/`, `~/.docker/config.json`, `~/.kube/config`, `~/.npmrc`, `~/.pypirc`, `~/.config/gh/`, browser cookie stores, password-manager databases), block-device writes (`dd of=/dev/`, `mkfs`, `shred`), history rewrites (`git filter-branch`, `git filter-repo`, `git update-ref -d`, `git reflog expire`, `git push --mirror` on shared branches), unguarded SQL deletes (`TRUNCATE TABLE`, `DELETE` without `WHERE`), recursive permission changes (`chmod -R 777`, `chown` to other user), and system-file modification (`/etc/hosts`, `/etc/resolv.conf`, `/etc/sudoers`, `crontab`). The same expanded list is mirrored exactly in `settings.json` (template), `install.sh` (per-project generator), and `activate.sh` (global-install generator) so every install path emits the hardened ruleset.
- **`EXA_API_KEY` moves from URL query string to `Authorization: Bearer` header (S3, CWE-598).** `install.sh` and `activate.sh` previously appended `?exaApiKey=${EXA_API_KEY}` to the websearch MCP URL, so the key surfaced in shell history, process listings (`ps`), proxy/CDN logs, and Claude Code transcripts. Switched to `claude mcp add websearch --transport http --header "Authorization: Bearer ${EXA_API_KEY}" ...`, which the Claude Code CLI forwards on each request without persisting the key in any URL. Verified with `claude mcp add --help`; the `--header` flag is documented in the official examples.
- **Shared `_state-dir.sh` helper for atomic state-dir creation (S4).** Extracted `alloy_ensure_state_dir <path>` into `hooks/_state-dir.sh`. The helper rejects pre-planted symlinks and non-directory paths, then calls `install -d -m 700` (atomic mode-on-create — closes the `mkdir -p && chmod 700` TOCTOU window). Sourced by `agent-count.sh`, `agent-reminder.sh`, `context-pressure.sh`, `edit-ledger.sh`, `ignite-detector.sh`, `ignite-stop-gate.sh`, `pre-compact.sh`, `rate-limit-resume.sh`, `skill-reminder.sh`, `subagent-start.sh`, `subagent-stop.sh`, and `todo-enforcer.sh`. Of those, `pre-compact.sh`, `context-pressure.sh`, `subagent-stop.sh`, and `rate-limit-resume.sh` previously created the state dir without any chmod follow-up at all — they would have inherited the user's default umask (typically 0755) on first install. `commands/notify-setup.md` documentation updated to use `install -d -m 700` for the same reason.

### Performance
- **`hooks/lint.sh` and `hooks/typecheck.sh` drain stdin before low-effort early-exit (I1).** A bare `exit 0` left Claude Code's producer-side pipe write blocked until the hook timeout reaped it (~30s for lint, ~60s for typecheck). Adding `cat > /dev/null` before exit signals EOF immediately, matching the pattern already established in `agent-reminder.sh` and `skill-reminder.sh`.
- **`hooks/context-pressure.sh` honors `CLAUDE_EFFORT=low` (I2).** The advisory ~70%/85% tool-call counter previously fired on every PostToolUse regardless of effort tier, adding a `jq` invocation per haiku micro-task. Now skipped on low-effort turns (with stdin drained) — bringing it in line with the rest of the P2 effort-tier batch.

---

## [1.6.10] — 2026-05-08

> **Hardened IGNITE enforcement + edit-ledger instrumentation.** Real-time edit tracking and generated-settings parity tests replace transcript-tail IGNITE validation.

### Added
- **`hooks/edit-ledger.sh`** — records real implementation edits in `~/.claude/.alloy-state/code-edited-${SESSION_ID}` so IGNITE review enforcement no longer depends primarily on transcript-tail scanning. State bookkeeping writes for Alloy's own `agent-count-*`, `agents-spawned-*`, `ignite-active-*`, and `ignite-blocked-*` files are ignored.
- **Generated-settings regression tests** — `tests/settings-generation.sh` installs into a temp project and asserts `PostToolUse` matcher parity with `hooks/hooks.json`, including `Agent|Task`, `edit-ledger.sh`, `context-pressure.sh`, and the Bash-aware agent reminder matcher.
- **Edit-ledger regression tests** — `tests/edit-ledger.sh` covers real edits, `.alloy-state` bookkeeping skips, traversal-looking state paths, and `NotebookEdit`.

### Fixed
- **Installer/settings drift around hook wiring.** Project/global install templates now include `edit-ledger.sh`, `agent-count.sh`, `context-pressure.sh`, and the `Bash` agent-reminder matcher consistently with `hooks/hooks.json`.
- **`doctor.sh` hook inventory.** Doctor now checks `agent-count.sh` and `edit-ledger.sh`, reports 23 hooks, and warns on unknown agent frontmatter model values before runtime.
- **Stale `/alloy-init` and README counts.** Global command docs and README now reflect 14 agents, 9 skills, 15 commands, and 23 hooks.

### Changed
- **`/ignite` command wording** now uses the compressed `─── 🔥 IGNITE · Intent: [TYPE] → [agents] ───` header and explicitly avoids the legacy duplicate `IGNITE MODE ACTIVATED!` banner.

---

## [1.6.9] — 2026-05-02

> **Precision-routing pivot + dev-browser hygiene.** This release reframes Alloy from "always parallelize" to "delegate when uncertainty, scale, or specialist risk warrants it." Routine work biases toward direct tools; IGNITE remains the explicit lever for full parallelism. Also bumps the optional Playwright MCP pin and adds the `--headless` flag for CI/server environments.

### Added
- **Env-var override for hook reminders.** `ALLOY_AGENT_REMINDER_SEARCH_THRESHOLD` (default `5`) and `ALLOY_SKILL_REMINDER_WORK_THRESHOLD` (default `12`) override the built-in thresholds for hooks/agent-reminder.sh and hooks/skill-reminder.sh respectively. Non-numeric values fall back to the default.
- **`tests/skill-reminder.sh`** — new regression suite (17 assertions) for skill-reminder threshold behavior, env-var override, marker-file write, and delegation-suppression path. Picked up automatically by the new CI glob loop.
- **README "Default vs IGNITE" contrast sentence** in How It Works section. Makes the precision posture explicit and teaches `ig` as the opt-in lever for full parallelism.

### Changed
- **Precision-parallelism routing pivot.** Steel and tungsten now delegate to specialist agents when uncertainty, specialist domain, scale, or verification warrant it — not on default. The Precision Delegation Gate enumerates explicit conditions for spawning agents. Review agents (sentinel/iridium/cobalt/flint) still fire automatically when their risk domain is touched. IGNITE protocol is unchanged: 6+ agents minimum, graphene required, review gate has no exceptions. Files: `agents/steel.md`, `agents/tungsten.md`, `CLAUDE.md`, `README.md`, `commands/alloy.md`.
- **agent-reminder threshold raised 1 → 5.** A single direct search is rarely "broad research" — the new floor only nudges toward mercury/graphene after sustained direct searching, matching the right-size posture. Override via `ALLOY_AGENT_REMINDER_SEARCH_THRESHOLD`.
- **skill-reminder threshold raised 8 → 12.** Same reasoning: routine moderate work shouldn't be nagged. Override via `ALLOY_SKILL_REMINDER_WORK_THRESHOLD`.
- **`@playwright/mcp` pin bump 0.0.70 → 0.0.73.** Picks up the v0.0.73 fix for `--browser=chrome` channel propagation on the extension path. v0.0.72's `browser_run_code` → `browser_run_code_unsafe` rename is a no-op for Alloy (skills/dev-browser/SKILL.md teaches native Playwright API, not MCP tool surface).
- **Playwright MCP install adds `--headless`.** Headed-by-default broke silently on CI runners, headless servers, and SSH dev sessions. `install.sh:542` and `activate.sh:422` now both pass `--browser=chrome --headless` to `npx @playwright/mcp@0.0.73`.
- **`claude mcp` syntax standardized on long form `--scope user`** across `install.sh` and `activate.sh` (covers `add`, `list`, and `remove` invocations). Self-documenting in scripts; both forms remain CLI-supported.
- **Plugin manifest hook count corrected 20 → 22** in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. Was stale since `agent-count.sh` and `context-pressure.sh` shipped without a manifest update.
- **CI test runner switched to glob loop.** `.github/workflows/ci.yml:34–35` now iterates `for test_script in tests/*.sh; do bash "$test_script" || exit 1; done`, so new test files are picked up without editing the workflow.
- **`tests/agent-reminder.sh` rewritten** for the new threshold (5 instead of 1). 22 assertions: threshold boundary at exactly call 5, env-var override path, post-marker suppression, traversal sanitization, bash-as-search detection.

### Fixed
- **Default-vs-IGNITE posture was implicit.** Users upgrading from prior alloy versions perceived new defaults as agent-shy without realizing `ig` was the contrast. README now teaches the lever explicitly.
- **Linux compat: GNU `stat -c %Y` ordered first in mtime checks.** Three hooks (`hooks/ignite-stop-gate.sh`, `hooks/ignite-detector.sh`, `hooks/statusline.sh`) were still using BSD-first `stat -f %m` ordering. On Linux GNU coreutils, `stat -f %m FILE` does not error — it interprets `-f` as `--file-system` and returns the mount point with exit 0. The `||` fallback to GNU `stat -c %Y` therefore never fired, `FLAG_EPOCH` became `/`, and `$(( NOW_EPOCH - / ))` aborted the hook with `set -u`. Mirrors the v1.6.4 fix already applied to `lint.sh`, `typecheck.sh`, and `auto-install.sh`. Adds a numeric-validation guard (`case "$X" in ''|*[!0-9]*) X=0 ;; esac`) for defense-in-depth. Verified: 157/157 macOS + 6/6 Linux container assertions pass.

---

## [1.6.8] — 2026-04-26

> **Patch release on top of v1.6.7.** v1.6.7 contained the bulk of the optimization work (token-cost, hook hardening, install UX, IGNITE protocol, agent counter rewrite). v1.6.8 only fixes one rendering bug and four CI shellcheck warnings introduced during v1.6.7. **See the v1.6.7 entry below for the full feature list** — most users upgrading should think of this as "v1.6.7 with the statusline render fix."

### Fixed
- **`hooks/statusline.sh` 5h rate-limit segment never rendered correctly.** v1.6.7 removed the 7d segment but left the surrounding `for pair in "5h:..."` loop, which iterated exactly once over a single double-quoted element. shellcheck SC2066 caught this in CI: a one-element double-quoted "loop" is a code smell that hid a real rendering bug — `RATE_PARTS` accumulated correctly but the loop structure suggested multi-segment support that no longer existed. Replaced with direct rendering. Behavior is identical when a 5h reset is present, but the code now matches its intent (single segment, not a list).
- **CI shellcheck failures (4 warnings/info):** v1.6.7 introduced a few shellcheck noise items that the CI's strict-no-warnings mode treats as errors:
  - `install.sh:22` HOOKS variable — only used in `--project` mode block; added inline `# shellcheck disable=SC2034` with explanation.
  - `hooks/statusline.sh:75` SEVEN_DAY_PCT — extracted but unused since v1.6.7 7d removal; explicit `# shellcheck disable=SC2034` with rationale (kept for parity, future render).
  - `hooks/ignite-detector.sh:64` and `tests/ignite-detector.sh:95` — sed regex patterns and printf escape sequences in single quotes (intentional — backticks are literal pattern characters, not bash expansions); added inline `# shellcheck disable=SC2016`.

No functional changes beyond the statusline 5h render fix. v1.6.7 binary is still safe — the bug is rendering-only, not security or data integrity.

---

## [1.6.7] — 2026-04-25

### Documentation
- **README "MCP Tool Search opt-in" tip** under env-var section. Surfaces Anthropic's deferred-tool-loading feature (claimed over 85% MCP schema reduction) as a power-user opt-in via `export ENABLE_TOOL_SEARCH=true`. Explicit caveats: known auto-activation bugs ([#18397](https://github.com/anthropics/claude-code/issues/18397)), silent failure on Windows Desktop ([#41472](https://github.com/anthropics/claude-code/issues/41472)), only worth it for 10+ MCP server setups, requires Sonnet 4+/Opus 4+/Haiku 4.5+. **Not auto-set by install.sh** — the platform reliability issues make it unsafe to inject without user consent.

### Fixed (verification-pass; pre-merge)
- **`hooks/session-start.sh` and `hooks/context-pressure.sh` JSON validation error.** Both hooks emitted `hookSpecificOutput` without the required `hookEventName` field, causing Claude Code to fail validation: "Hook JSON output validation failed — hookSpecificOutput is missing required field 'hookEventName'". The error appeared at session start (session-start.sh) and silently dropped context-pressure warnings. Added `hookEventName: "SessionStart"` and `"PostToolUse"` respectively to align with the schema other hooks (ignite-detector, agent-reminder, skill-reminder) already use. Caught when user opened a fresh `claude` session and saw the error in the TUI footer.
- **`hooks/ignite-detector.sh` clears stale agent counts on fresh IGNITE activation.** A session that IGNITEd, fired N agents, idled past the 2h TTL, and re-IGNITEd inherited the prior phase's counter — the new phase's 6-agent gate could be satisfied without spawning anything fresh (gate failed open). Now: when activating either fresh (no flag) or after the flag's TTL expired, the detector removes `agent-count-${SESSION_ID}` and `agents-spawned-${SESSION_ID}` so the new phase starts at zero. Within-phase re-activation (flag still fresh) preserves counters. New regression tests in `tests/ignite-detector.sh` cover both cases.
- **`hooks/agent-count.sh` uses append-only ledger as source of truth (race-resistant counter).** Pre-fix: separate `agent-count-${SID}` file maintained via read-modify-write. Concurrent PostToolUse invocations could both read N, both write N+1, undercounting. Fix: append agent name to `agents-spawned-${SID}` ledger (atomic on POSIX for sub-PIPE_BUF writes), then derive count via `wc -l`. The `agent-count-${SID}` file is still mirrored for stop-gate read-path compatibility, but the ledger is now authoritative. Eliminates the race entirely.
- **New `hooks/agent-count.sh` — parent-session-keyed agent counter (replaces broken SubagentStart-based counting).** Pre-fix: the IGNITE stop-gate's "N/6 agents spawned" check relied on `hooks/subagent-start.sh`, which fires on Claude Code's `SubagentStart` event. Empirically, that event does NOT fire reliably in some long-running parent sessions — observed sessions with 30+ Agent tool dispatches that produced zero `SubagentStart` invocations, leaving the gate convinced "0/6 agents spawned" and forcing false-positive blocks. Fix: new `agent-count.sh` runs as `PostToolUse` with matcher `Agent|Task`, which fires reliably for every parent-session tool call. Counts written under the parent's session_id (via the canonical PostToolUse `session_id` field), giving the stop-gate accurate counts. `subagent-start.sh` retained for the global agent log but no longer load-bearing for IGNITE counting. New `tests/agent-count.sh` (12 cases) — increment, accumulation, non-Agent skip, empty subagent_type fallback, path-traversal sanitization, corrupted-counter recovery.
- **`hooks/subagent-start.sh` agent counter wired against current Claude Code event schema.** Previous extraction read `.agent_type` only — broken when payload wraps the identifier as `.subagent_type`, `.tool_input.subagent_type`, or `.tool_use.input.subagent_type`. Now tries all four in fallback chain. Counter always increments and the spawned-agents ledger always appends a row, keeping the IGNITE stop-gate's "N/6 spawned" check accurate across schema variants. `ALLOY_DEBUG=1` surfaces raw input for future schema regressions.
- **`hooks/agent-reminder.sh` threshold lowered from 2 to 1, plus bash-as-search fallback.** Two coupled fixes:
  - **Threshold**: with threshold=2 the reminder rarely fired in real sessions because users delegated before hitting two direct search calls. The hook is one-shot per session anyway, so waiting for a second search defeated the purpose. Now fires immediately on first search call.
  - **Bash fallback**: when a Claude Code project's tool registry doesn't expose the native Grep tool, users fall back to `bash grep`/`rg`/`ag`/`ack`/`find`/`fd`/`git grep`/`git log -S`. The reminder now also fires on those (first-token disambiguation prevents `echo 'rg ...'`-style false positives, and `git status` correctly doesn't fire). Caught during user verification — Grep wasn't loadable in their test project, so the v1.6.6/early-v1.6.7 reminder never fired even though the user was clearly searching.
- **`hooks/ignite-detector.sh` skips quoted, descriptive, and test-context mentions.** A prompt like "verify the IGNITE protocol works" tripped the detector even though the user never invoked it. Two-stage detection: (1) strip code fences, backtick spans, and double/single-quoted strings before matching; (2) skip matches preceded by descriptive modifier words (the/an/this/that/our/about/regarding/describes/describing/protocol/mode/test/testing/verify/verification). New `tests/ignite-detector.sh` with 10 cases covering positive invocations and every false-positive class caught in v1.6.7 verification.
- **`hooks/ignite-stop-gate.sh` honors a 2h TTL on the IGNITE flag** AND **trusts the detector flag as single source of truth.** Two coupled fixes caught during user verification:
  - **TTL**: a flag set early in a long session was keeping the gate fully armed hours later, demanding 6+ agents on every subsequent stop even when the IGNITE phase was long over. Now: if the flag's mtime is older than `ALLOY_IGNITE_TTL` seconds (default 7200 = 2h), the flag is treated as stale. Override via `ALLOY_IGNITE_TTL=<seconds>`.
  - **Single source of truth**: the gate previously scanned the transcript for `IGNITE MODE ACTIVATED` or `🔥 IGNITE` as a fallback. That re-introduced the exact false-positive class the detector was just fixed for: a test prompt, documentation, or this very CHANGELOG that QUOTES the IGNITE banner would trip the gate even when the user never invoked it. Removed the transcript fallback. The detector flag is now the only path that activates the gate. New regression test in `tests/ignite-stop-gate.sh` locks this in (6/6 passing).

### Added
- **MCP Tool Search lazy-loading documentation.** Anthropic's deferred MCP tool loading reduces tool schema overhead per turn (Anthropic-stated over 85% in their docs). Documented in `commands/alloy.md` under MCP Servers; verifiable via Claude Code's built-in context view.
- **CLAUDE.md compact instructions** — tells Claude what to preserve (modified files, todos, test results, open questions, branch state) and what to discard (intermediate reasoning, full file blobs, resolved sub-questions) when auto-compact fires.
- **`hooks/pre-compact.sh` now backs up plan/todo state** to `~/.claude/.alloy-state/compact-backup-${SESSION_ID}-${ts}/` before context wipe. Forensic snapshot of plan/todo state immediately before context compaction. Inspect manually at `~/.claude/.alloy-state/compact-backup-*` if you need to reconstruct context post-compact. Automatic recovery (titanium loading the latest backup on session resume) is planned for v1.7.0. Stale backups (>7d) reaped by `session-end.sh` janitor.
- **First-run env-var discovery tips** — `activate.sh` prints `EXA_API_KEY` / `ALLOY_AUTO_UPDATE` / `ALLOY_BROWSER` toggle hints once per machine (gated by `~/.claude/.alloy-tips-shown` marker). Surfaces hidden config without adding gates.

### Changed
- **`activate.sh` cache-aware Playwright auto-detect** — auto-installs only when `@playwright/mcp` is already in npm/npx cache (fast 5s probe). Cold-cache install requires explicit `ALLOY_BROWSER=1` opt-in (avoids surprise ~20MB downloads during activation; cold install is allotted up to 30s with a status message). Set `ALLOY_BROWSER=0` to hard-disable. Wins for Node users who've used Playwright before; safe for everyone else.
- **Statusline `7d:P%` segment removed.** Week-away reset timestamps were useless as wall-clock percentages and cluttered the line. The 5-hour rate-limit segment with its `@HH:MM` reset clock stays — that one's actionable.
- **`commands/ig.md` trimmed from 13 lines to a 5-line redirect stub** pointing at `/ignite`. ig is an alias, not an independent command — its body was duplicating ignite.md.
- **`.mcp.json.example` updated** with optional Playwright entry (commented) for discoverability.

### Performance
- Documentation surfaces the upstream MCP Tool Search token win (Anthropic-stated over 85% MCP schema reduction WHEN active). claude-alloy itself shipped no MCP-related code — this is documentation only.

---

## [1.6.6] — 2026-04-25

### Fixed
- **`hooks/ignite-stop-gate.sh` Edit/Write false positive.** Bare-word `grep -E 'Edit|Write'` on the last 500 transcript lines matched ordinary mentions in tool schemas, agent prompts, plan tables, and system reminders — every research-only IGNITE turn falsely tripped Check 3 and forced sentinel/iridium/flint to spawn unnecessarily (~30K tokens wasted per false positive). Replaced with a JSONL-aware pattern that requires `Edit`/`Write`/`MultiEdit`/`NotebookEdit` to appear as a `tool_use` `name` field value. Adds `tests/ignite-stop-gate.sh` (4 cases). Also: IGNITE detection (line 36) now matches both legacy `IGNITE MODE ACTIVATED` and the new compressed `🔥 IGNITE` header.
- **`hooks/agent-reminder.sh` repeat-fire bug.** Counter reset to 0 after firing, so the `[Agent Usage Reminder]` block was injected into context every two grep/glob/web tool calls. Added one-shot `${STATE_DIR}/agent-reminded-${SESSION_ID}` marker matching the `skill-reminder.sh` pattern — fires at most once per session.

### Changed
- **`agents/steel.md` verbalize-intent ritual compressed.** The paragraph-form opener (`"I detect [X] intent — [reason]. My approach: [routing]."`) is retired. Steel now emits a one-line header in the closing footer's style — `─── Intent: [TYPE] → [agent list] ───`, or `─── 🔥 IGNITE · Intent: [TYPE] → [agents] ───` for IGNITE turns — and only when delegating to 1+ subagents, in IGNITE mode, or when 3+ tool calls are planned. Trivial single-tool turns and plain Q&A skip the header entirely. Closing footer untouched.
- **`CLAUDE.md` trimmed from ~210 to 91 lines.** It is now an INDEX of the agent roster, adaptive routing summary, skills, commands, and MCP servers. The detailed delegation table, full IGNITE protocol step-by-step, and core principles moved to `commands/alloy.md` (lazy-loaded on `/alloy`). Loaded-every-session content cut by ~60%.
- **9 skill descriptions trimmed to ≤80 chars** (was avg ~220 chars). `ai-slop-remover`, `code-review`, `dev-browser`, `frontend-ui-ux`, `git-master`, `pipeline`, `review-work`, `tdd-workflow`, `verification-loop`. Skill descriptions are loaded into context every turn — this saves ~130 tokens per turn.

### Added
- **`disallowedTools: [Write, Edit, MultiEdit, NotebookEdit]`** frontmatter on 10 read-only agents: `mercury`, `graphene`, `sentinel`, `iridium`, `prism`, `gauge`, `cobalt`, `flint`, `quartz`, `spectrum`. Provides explicit write-tool restriction at frontmatter level (in addition to existing prompt-level instruction) for agents that previously had no `tools:` allowlist. Agents with a `tools:` allowlist already excluded write tools — `disallowedTools` is harmless redundancy on those, no schema-size impact. (Removed in v1.6.7 — see that release.)
- **`tests/ignite-stop-gate.sh`** — 4 cases covering the false-positive fix above. False positive (bare prose mention exits 0), true positives for `Edit`/`Write`/`MultiEdit` tool_use blocks (each exits 2 / blocks).

### Performance
- Estimated **15-25% token reduction on normal sessions** and proportionally larger on IGNITE sessions, based on byte-count analysis of always-loaded context (CLAUDE.md, steel.md, skill descriptions). NOT measured via ccusage; v1.6.7+ includes a benchmark scenario in `tests/benchmarks/` for users to verify in their own environment.

---

## [1.6.5] — 2026-04-24

### Fixed
- **`install.sh` now globs `agents/*.md`** instead of an enumerated list. `_review-template.md` (added earlier in this version) was silently missing from fresh installs — `sentinel`, `iridium`, `cobalt`, and `flint` reference it, so those 4 review agents were broken for any new user. Same glob pattern applied to uninstall. Memory-init loops now skip underscore-prefixed templates (they're includes, not agents). `activate.sh` already globbed agents, but its memory-init loop is likewise hardened against the same footgun.

### Changed
- **steel agent prompt slimmed** from 18.7KB to ~12KB (262 lines). Routing table extracted to `CLAUDE.md` (steel references it by link). "DELEGATE BY DEFAULT" behavior, all MUST / MUST NOT directives, IGNITE protocol, and Post-Implementation Review Gate preserved verbatim. Routing-regression check run against three scenarios (mercury on search, carbon on 3+ files, IGNITE activation).
- **Deduplicated CLAUDE.md**. Global `~/.claude/CLAUDE.md` is now the canonical source. Project-root `CLAUDE.md` is marked deprecated via a leading HTML comment and will be removed in v1.8.0. `install.sh --project` now prints a deprecation notice; `activate.sh` comment updated to "CLAUDE.md: source of truth. Always copied to ~/.claude/."
- **`/alloy` command shrunk** from 7.7KB to 428 bytes — it is now a reference stub pointing at `CLAUDE.md` for the full roster.
- **Review-agent template extraction**: shared severity scale, scope-boundary statement, output format, and rules moved to `agents/_review-template.md`. `sentinel`, `iridium`, `cobalt`, `flint` now reference the template and keep only their domain-specific checklist, severity tier definitions, and specializations. Each review agent shed ~700–900 chars; ~2.9KB of duplication removed.
- **`hooks/session-start.sh` wiki injection cap reduced** from 4096 to 2048 bytes. New opt-out: create `${CLAUDE_PROJECT_DIR}/.claude/wiki.no-inject` (or `~/.claude/wiki.no-inject`) to skip wiki injection entirely. Truncation still happens from the bottom, preserving the earliest (most-recent by convention) entries.
- **`hooks/skill-reminder.sh` session-gating hardened**: reminder was already session-gated via the `REMINDER_FILE` check before threshold-counter increment (fires at most once per session), but the `SESSION_ID` extraction now follows the `context-pressure.sh` pattern — default `"unknown"`, regex-sanitized via `[[ =~ ^[A-Za-z0-9_-]+$ ]]` against CWE-22 path traversal before use in a filesystem path.

### Hook transcript audit
Audited all 21 hooks for redundant transcript emissions. Finding: the communicative hooks in the preserve list (comment-checker, ignite-detector, session-start, agent-reminder, skill-reminder, subagent-stop, ignite-stop-gate, session-end, context-pressure, auto-install/lint/typecheck guard outputs, rate-limit-resume) all emit only on real conditions with user-actionable content. `todo-enforcer.sh` emits two different outputs — a `{decision: "block", reason: ...}` first-attempt block (critical signal) and a `{systemMessage: ...}` second-attempt handoff nudge (informational); both are communicative and stay. No empty-string emissions were found. No hooks required conversion; the hook surface was already well-disciplined.

### Upstream bugs tracked
We tested three Anthropic env vars users have been sharing (`ENABLE_PROMPT_CACHING_1H`, `CLAUDE_CODE_FORK_SUBAGENT`, `ENABLE_TOOL_SEARCH`) and found active bugs on all three (issues #49139, #52833, #52121 respectively, all filed in the last 8 days). We don't recommend setting them yet. We'll ship efficiency guidance when the upstream fixes land.

### Measured
Benchmark scenario committed at `tests/benchmarks/v1.6.5-scenario.md`. Static resident-prompt analysis across the 8 touched files (steel.md, alloy.md, sentinel/iridium/cobalt/flint.md, CLAUDE.md, new `_review-template.md`):
- v1.6.4 sum: **54,487 bytes** (~13,600 tokens estimate)
- v1.6.5 sum: **42,163 bytes** (~10,500 tokens estimate)
- Reduction: **-12,324 bytes (-22.6%)** across these 8 files.

Caveats: this is the static resident-prompt contribution only. The committed 12-turn scenario is the vehicle for live `npx ccusage --json` comparison — full results in `tests/benchmarks/v1.6.5-results.json`. Steel + CLAUDE.md + alloy.md load every turn; `_review-template.md` loads only when a review agent fires, so per-turn savings for steel-only sessions are higher than the 22.6% average above. No marketing rounding — run `npx ccusage --json` against the committed scenario on v1.6.4 and v1.6.5 to verify for yourself.

---

## [1.6.4] — 2026-04-24

### Fixed
- **Thermal-runaway guard in `hooks/lint.sh`, `hooks/typecheck.sh`, `hooks/auto-install.sh`**: PostToolUse hooks invoking `npx`/`npm`/`pip` orphaned their descendants when Claude Code's hook-level timeout fired. On rapid edits, orphans stacked — 26+ concurrent stuck hook processes observed in the wild, load average 36 on a 10-core machine, inducing CPU thermal stress. Fix adds three layers of in-hook defense identical across all three hooks:
  - **Layer 1 — cooldown (30s)**: keyed on project dir (or manifest path for auto-install). Skips the second invocation inside the cooldown window and prints a stderr notice so users with `ALLOY_AUTO_LINT=1` / `ALLOY_AUTO_INSTALL=1` still see signal. Portable `stat -f %m || stat -c %Y` for BSD/GNU mtime read.
  - **Layer 2 — concurrency lock** via `mkdir` (atomic on all POSIX filesystems, per BashFAQ/045) + pidfile + `kill -0` liveness check. Stale-lock recovery: if the recorded PID is dead, take over rather than blocking forever. Rejects pre-created lock/cooldown symlinks to harden against shared-/tmp redirection.
  - **Layer 3 — process-group timeout**: prefers GNU `timeout --kill-after=5s` when available (POSIX — kills the full descendant tree); falls back to a perl `setpgid` supervisor with negative-PID signal delivery (`kill "-TERM", $pid`) on stock macOS. Signals SIGTERM, sleeps 2s, then SIGKILL — captures daemonized descendants (`npx` → `node` → `tsc`) that escape direct-child kill.
- **Portability**: all three hooks now derive their state-file key via `shasum || sha1sum` so they work identically on macOS (ships `shasum`) and Ubuntu CI (ships `sha1sum`). State files prefer `$XDG_RUNTIME_DIR` (per-user, 0700 on systemd systems) and fall back to `$TMPDIR`/`/tmp`. Files are named `claude-alloy-<hook>-<sha1>.{cooldown,d}` for cross-project collision safety.

### Added
- **`tests/thermal-runaway.sh`** — 41 assertions covering cooldown, live-pid lock rejection, stale-pid lock recovery, pgroup-aware timeout (including descendant-kill verification via unique argv markers), `shasum`/`sha1sum` fallback, `$XDG_RUNTIME_DIR` preference, and lock/cooldown symlink rejection. Runs on macOS bash 3.2 and Ubuntu CI. Uses `pgrep -f` and `exec -a` for portable descendant detection.
- **CI now runs `tests/branch-guard.sh` and `tests/thermal-runaway.sh`** (previously missing branch-guard coverage is now exercised on every push).

---

## [1.6.3] — 2026-04-20

### Changed
- **`hooks/branch-guard.sh`** — configurable without weakening the default. Zero-config for scratch repos and docs; default still blocks `main`/`master` edits.
  - **No-remote skip**: repos with no `git remote` (scratch, pre-push local repos) pass silently.
  - **Docs allowlist (warn, not silent)**: edits to `*.md`, `*.txt`, and root-level `README*`/`CHANGELOG*`/`LICENSE*` emit a one-line stderr notice and proceed.
  - **`ALLOY_BRANCH_GUARD` env var**: tri-state `off` (silent bypass) / `warn` (stderr notice, proceed) / `block` (default, enforces).
  - **Marker file opt-out**: `.claude/branch-guard.off` in the repo root permanently opts a repo out (replaces previous `.claude/allow-main-edits` marker).
  - **Refined error message**: concrete bypass commands (`git checkout -b`, `ALLOY_BRANCH_GUARD=warn`, marker file) listed on block.
  - Reads `tool_input.file_path` from stdin (jq with sed fallback) to classify docs vs code. Still exits 2 on block, 0 on pass, matching Claude Code PreToolUse hook protocol.

---

## [1.6.2] - 2026-04-18

### Fixed
- **CI shellcheck failures** (SC2015, SC2221, SC2222) introduced in v1.6.1:
  - `hooks/session-end.sh`: replaced `[ -d ] && ... || true` with explicit `if`-block (SC2015). Script is `set -u` not `set -e`, so `|| true` wasn't needed anyway.
  - `hooks/write-guard.sh`: collapsed overlapping case patterns `*../*|*/..*|*..|../*` into non-overlapping segment-safe set `..|../*|*/..|*/../*`. More precise — no longer false-positives on weird-but-legitimate filenames like `my..file` or `..hidden`. Still catches every real traversal variant (bare `..`, leading, mid-path, trailing).
- **Stale `[alloy X.Y.Z]` version in HUD statusline**: `hooks/statusline.sh` previously read only from `~/.claude/.alloy-version`, which is written ONCE by `activate.sh` and never updated on `git pull`. Users who upgraded via git saw the old version forever. Fix: self-locating fallback chain reading `$CLAUDE_PLUGIN_ROOT/VERSION` → `<script-dir>/VERSION` → `<script-dir>/../VERSION` → legacy `~/.claude/.alloy-version`.

### Changed
- **Hide `$0.00` cost segment at session start**: statusline no longer renders the cost field until cost > 0. The zeroed field looked like a stuck widget to users starting fresh sessions. Cost still shows correctly once the first API call lands (and colors yellow/red at the existing thresholds).
- **Install scripts now copy `VERSION` alongside hooks** (`install.sh`, `activate.sh`). The VERSION file ships to `${CLAUDE_DIR}/alloy-hooks/VERSION` so the statusline self-locating fallback works for install.sh-installed users (not just marketplace plugin users who receive `$CLAUDE_PLUGIN_ROOT`). `deactivate.sh` removes it on uninstall.

---

## [1.6.1] — 2026-04-18

### Security
- Gate `hooks/auto-install.sh` behind `ALLOY_AUTO_INSTALL=1` opt-in. Auto-installing `package.json`/`requirements.txt`/`pyproject.toml` is a supply-chain RCE surface (typosquats, pip build backends). Pip install path now uses `--no-deps --only-binary=:all:`.
- Gate `hooks/lint.sh` and `hooks/typecheck.sh` behind `ALLOY_AUTO_LINT=1` opt-in. All `npx` invocations now use `--no-install` to prevent fetching untrusted packages from malicious repos.
- Fix path-traversal case pattern in `hooks/write-guard.sh` to catch bare leading `../file` (previously only caught `/../`, `../` mid-path, and exact `..`).
- Validate Slack and Discord webhook URLs in `hooks/session-notify.sh` — allowlist `hooks.slack.com` and `discord.com/api/webhooks`. Prevents SSRF.
- Tighten `self-update.sh` remote match from substring to exact normalized comparison.
- Untrack `.claude/settings.local.json` (user-specific, never ship committed).

### Performance
- Remove redundant `find -mtime +7 -delete` from 5 hot-path hooks (agent-reminder, ignite-detector, ignite-stop-gate, skill-reminder, subagent-start). Centralized in `session-end.sh` (async, fires once per session). Saves ~150-450ms per session.
- Use `tail -500` before transcript grep in `ignite-stop-gate.sh` and `todo-enforcer.sh`. Saves ~100ms per session Stop on long transcripts.
- Skip untracked-file scan in `hooks/statusline.sh` (`git status --porcelain -uno`). 2-5× faster on large repos.

### Reliability
- Fix `doctor.sh` skill count (add `pipeline`) and hook count (add `statusline.sh`, `context-pressure.sh`). Health check now matches `install.sh` and CI assertion (9 skills, 21 hooks).

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
- **README positioning**: New tagline ("Claude Code with a team"), model-tiering emphasis, star history chart, star CTA.
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
