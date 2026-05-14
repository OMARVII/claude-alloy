#!/usr/bin/env bash
# Tests for generated settings — prevents hook template drift.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/testlib.sh disable=SC1091
. "${SCRIPT_DIR}/lib/testlib.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed — settings generation requires jq\n'
    exit 0
fi

TMP_DIR=$(mktemp -d /tmp/alloy-settings-gen.XXXXXX)
PROJECT_DIR="${TMP_DIR}/project"
mkdir -p "$PROJECT_DIR"

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null
    return 0
}
trap cleanup EXIT

bash "${REPO_ROOT}/install.sh" --project "$PROJECT_DIR" >/dev/null 2>&1

SETTINGS="${PROJECT_DIR}/.claude/settings.json"
if jq empty "$SETTINGS" >/dev/null 2>&1; then
    _json_valid=1
else
    _json_valid=0
fi
assert_eq 1 "$_json_valid" "project install writes valid settings.json"

canonical_post=$(jq -r '.hooks.PostToolUse[].matcher' "${REPO_ROOT}/hooks/hooks.json" | tr '\n' '|')
generated_post=$(jq -r '.hooks.PostToolUse[].matcher' "$SETTINGS" | tr '\n' '|')
assert_eq "$canonical_post" "$generated_post" "project PostToolUse matchers mirror hooks.json"

has_agent_count=$(jq -e '.hooks.PostToolUse[] | select(.matcher == "Agent|Task") | .hooks[] | select(.command | endswith("/agent-count.sh"))' "$SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$has_agent_count" "generated settings include Agent|Task agent-count hook"

has_edit_ledger=$(jq -e '.hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit") | .hooks[] | select(.command | endswith("/edit-ledger.sh"))' "$SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$has_edit_ledger" "generated settings include edit-ledger hook"

# IGNITE-mode skills must be gated to user-invocable-only — auto-invoking them
# from inferred intent would flip the run posture without a deliberate opt-in.
project_ignite_override=$(jq -r '.skillOverrides.ignite // "missing"' "$SETTINGS")
assert_eq "user-invocable-only" "$project_ignite_override" \
    "project install writes skillOverrides.ignite = user-invocable-only"
project_ig_override=$(jq -r '.skillOverrides.ig // "missing"' "$SETTINGS")
assert_eq "user-invocable-only" "$project_ig_override" \
    "project install writes skillOverrides.ig = user-invocable-only"
project_loop_override=$(jq -r '.skillOverrides.loop // "missing"' "$SETTINGS")
assert_eq "user-invocable-only" "$project_loop_override" \
    "project install writes skillOverrides.loop = user-invocable-only"
project_halt_override=$(jq -r '.skillOverrides.halt // "missing"' "$SETTINGS")
assert_eq "user-invocable-only" "$project_halt_override" \
    "project install writes skillOverrides.halt = user-invocable-only"

# worktree.symlinkDirectories must include "node_modules" so parallel
# tungsten worktrees skip the multi-GB node_modules copy and inherit it via
# symlink instead — pairs with baseRef:fresh to keep spin-up cheap.
project_worktree_symlinks=$(jq -r '.worktree.symlinkDirectories // [] | index("node_modules") // "missing"' "$SETTINGS")
case "$project_worktree_symlinks" in
    ''|missing) _has_symlinks=0 ;;
    *) _has_symlinks=1 ;;
esac
assert_eq 1 "$_has_symlinks" \
    "project install writes worktree.symlinkDirectories with node_modules"

agent_reminder_matcher=$(jq -r '.hooks.PostToolUse[] | select((.hooks[]?.command // "") | endswith("/agent-reminder.sh")) | .matcher' "$SETTINGS")
assert_eq "Grep|Glob|WebFetch|WebSearch|Bash|mcp__.*" "$agent_reminder_matcher" \
    "generated settings include Bash in agent-reminder matcher"

if grep -q '"matcher": "Agent|Task"' "${REPO_ROOT}/activate.sh" && \
   grep -q 'edit-ledger.sh' "${REPO_ROOT}/activate.sh" && \
   grep -q 'ignite-stop-gate.sh' "${REPO_ROOT}/activate.sh" && \
   grep -q 'Grep|Glob|WebFetch|WebSearch|Bash|mcp__.*' "${REPO_ROOT}/activate.sh"; then
    _activate_static=1
else
    _activate_static=0
fi
assert_eq 1 "$_activate_static" "activate.sh template contains critical hook wiring"

GLOBAL_HOME="${TMP_DIR}/home"
mkdir -p "${GLOBAL_HOME}/.claude"
cat > "${GLOBAL_HOME}/.claude/settings.json" <<'JSON'
{
  "env": {
    "USER_SETTING": "preserved"
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "/tmp/custom-stop.sh"},
          {"type": "command", "command": "/tmp/alloy-hooks/stale-stop.sh"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {"type": "command", "command": "/tmp/custom-write.sh"}
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "/tmp/custom-statusline.sh"
  }
}
JSON

HOME="$GLOBAL_HOME" ALLOY_AUTO_UPDATE=0 bash "${REPO_ROOT}/activate.sh" >/dev/null 2>&1
GLOBAL_SETTINGS="${GLOBAL_HOME}/.claude/settings.json"

if jq empty "$GLOBAL_SETTINGS" >/dev/null 2>&1; then
    _global_json_valid=1
else
    _global_json_valid=0
fi
assert_eq 1 "$_global_json_valid" "global activation writes valid merged settings.json"

has_global_stop_gate=$(jq -e '.hooks.Stop[0].hooks[] | select(.command | endswith("/ignite-stop-gate.sh"))' "$GLOBAL_SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$has_global_stop_gate" "global activation merge includes ignite-stop-gate hook"

has_custom_stop=$(jq -e '.hooks.Stop[0].hooks[] | select(.command == "/tmp/custom-stop.sh")' "$GLOBAL_SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$has_custom_stop" "global activation merge preserves user Stop hooks"

has_stale_alloy_stop=$(jq -e '.hooks.Stop[0].hooks[] | select(.command == "/tmp/alloy-hooks/stale-stop.sh")' "$GLOBAL_SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 4 "$has_stale_alloy_stop" "global activation merge drops stale Alloy Stop hooks"

has_global_agent_count=$(jq -e '.hooks.PostToolUse[] | select(.matcher == "Agent|Task") | .hooks[] | select(.command | endswith("/agent-count.sh"))' "$GLOBAL_SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$has_global_agent_count" "global activation merge includes Agent|Task agent-count hook"

has_global_edit_ledger=$(jq -e '.hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit") | .hooks[] | select(.command | endswith("/edit-ledger.sh"))' "$GLOBAL_SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$has_global_edit_ledger" "global activation merge includes edit-ledger hook"

global_agent_reminder_matcher=$(jq -r '.hooks.PostToolUse[] | select((.hooks[]?.command // "") | endswith("/agent-reminder.sh")) | .matcher' "$GLOBAL_SETTINGS")
assert_eq "Grep|Glob|WebFetch|WebSearch|Bash|mcp__.*" "$global_agent_reminder_matcher" \
    "global activation merge includes Bash in agent-reminder matcher"

preserved_env=$(jq -r '.env.USER_SETTING' "$GLOBAL_SETTINGS")
assert_eq "preserved" "$preserved_env" "global activation merge preserves user env"

global_ignite_override=$(jq -r '.skillOverrides.ignite // "missing"' "$GLOBAL_SETTINGS")
assert_eq "user-invocable-only" "$global_ignite_override" \
    "global activation writes skillOverrides.ignite = user-invocable-only"

# Claude Code v2.1.139+ schema includes a per-hook `args: []` field on the
# command exec form. Both hooks/hooks.json and the install.sh / activate.sh
# heredocs emit it on every entry. Assert it survives generation so future
# template drift (e.g. someone editing a single hook entry and forgetting to
# carry the field) is caught by the test suite rather than at runtime.
project_has_args=$(jq -e '[.. | objects | select(.type == "command" and has("args"))] | length > 0' "$SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$project_has_args" "project install emits args[] on command-form hook entries"

global_has_args=$(jq -e '[.. | objects | select(.type == "command" and has("args"))] | length > 0' "$GLOBAL_SETTINGS" >/dev/null 2>&1; printf '%s' "$?")
assert_exit 0 "$global_has_args" "global activation emits args[] on command-form hook entries"

# settings.json mcpServers is silently ignored by Claude Code (GH issue
# anthropics/claude-code#24477). alwaysLoad belongs in .mcp.json (project) or
# ~/.claude.json (user) — neither install.sh nor activate.sh should inject a
# dead block into generated settings. These assertions lock that fix in place
# so future template drift (someone re-adding the block) is caught here.
project_has_mcp=$(jq -r 'has("mcpServers")' "$SETTINGS")
assert_eq "false" "$project_has_mcp" "project install does NOT emit dead mcpServers in settings.json"

global_has_mcp=$(jq -r 'has("mcpServers")' "$GLOBAL_SETTINGS")
assert_eq "false" "$global_has_mcp" "global activation does NOT emit dead mcpServers in settings.json"

# doctor.sh maintains a canonical SKILLS list it iterates to verify install
# health. Hyperplan landed in v1.6.11 (10th skill) but the canonical list was
# never updated — doctor could pass a health check even if hyperplan were
# missing. Assert hyperplan is now a tokenized entry so future drift (someone
# removing the skill but forgetting to update doctor) is caught here.
doctor_skills=$(grep -E '^SKILLS=' "${REPO_ROOT}/doctor.sh" | sed 's/SKILLS=//; s/"//g')
_has_hyperplan=$(printf '%s' "$doctor_skills" | tr ' ' '\n' | grep -cx hyperplan)
assert_eq 1 "$_has_hyperplan" "doctor.sh SKILLS list includes hyperplan"

# Plugin metadata description must match the actual skill count. After
# hyperplan landed, plugin.json and marketplace.json description strings
# advertised "9 skills" while the codebase shipped 10. Lock the bump in.
plugin_desc=$(jq -r '.description' "${REPO_ROOT}/.claude-plugin/plugin.json")
case "$plugin_desc" in
    *"10 skills"*) _plugin_count_ok=1 ;;
    *) _plugin_count_ok=0 ;;
esac
assert_eq 1 "$_plugin_count_ok" "plugin.json description advertises 10 skills"

marketplace_desc=$(jq -r '.plugins[0].description' "${REPO_ROOT}/.claude-plugin/marketplace.json")
case "$marketplace_desc" in
    *"10 skills"*) _marketplace_count_ok=1 ;;
    *) _marketplace_count_ok=0 ;;
esac
assert_eq 1 "$_marketplace_count_ok" "marketplace.json description advertises 10 skills"

done_testing
