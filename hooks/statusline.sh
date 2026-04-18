#!/usr/bin/env bash
# claude-alloy statusline — pure-bash, zero runtime config
# Reads Claude Code session JSON on stdin, emits one-line status to stdout.
# Fields sourced entirely from stdin + existing .alloy-state counters + git.
#
# Engineering constraints:
#   - max 2 jq forks (one bulk @tsv pass, one conditional CTX fallback pass)
#   - no external deps beyond jq, git, coreutils
#   - every stdin field null-safe via jq defaults
#   - fail-silent: always emit valid one-line output, never error to stdout
#   - target runtime: <150ms wall-clock (git ops add ~30ms, acceptable)

set -u

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# ---- Bulk stdin extraction (1 of 2 jq forks) --------------------------------
# One @tsv pass pulls every simple scalar field we need. Null-safe via // defaults.
# Fields (order matters — must match the read below):
#   1  MODEL             .model.display_name
#   2  DUR_MS            .cost.total_duration_ms
#   3  SESSION_ID        .session_id
#   4  CWD               .workspace.current_dir
#   5  COST              .cost.total_cost_usd          (ENH-1)
#   6  LINES_ADDED       .cost.total_lines_added       (ENH-4)
#   7  LINES_REMOVED     .cost.total_lines_removed     (ENH-4)
#   8  FIVE_HOUR_PCT     .rate_limits.five_hour.used_percentage  (ENH-3)
#   9  SEVEN_DAY_PCT     .rate_limits.seven_day.used_percentage  (ENH-3)
#  10  WORKTREE          .workspace.git_worktree       (ENH-7)
#  11  EXCEEDS_200K      .exceeds_200k_tokens          (ENH-8)
#  12  FIVE_HOUR_RESET   .rate_limits.five_hour.resets_at   (v2.1)
#  13  SEVEN_DAY_RESET   .rate_limits.seven_day.resets_at   (v2.1)
# Read one field per line via a portable while-loop (bash 3.2 on macOS has
# no `mapfile`). Using IFS=$'\t' + read collapses consecutive tabs, which
# mangles empty middle fields (e.g., rate limits absent + worktree present),
# so we emit newline-delimited fields from jq and index them ourselves.
# Newline is safe: none of these fields can legitimately contain '\n'.
_FIELDS=()
while IFS= read -r _line; do
    _FIELDS+=("$_line")
done < <(
    echo "$INPUT" | jq -r '
        [
            (.model.display_name // "?"),
            ((.cost.total_duration_ms // 0) | tostring),
            (.session_id // "unknown"),
            (.workspace.current_dir // "?"),
            ((.cost.total_cost_usd // 0) | tostring),
            ((.cost.total_lines_added // 0) | tostring),
            ((.cost.total_lines_removed // 0) | tostring),
            (if (.rate_limits.five_hour.used_percentage // null) != null
                then (.rate_limits.five_hour.used_percentage | tostring) else "" end),
            (if (.rate_limits.seven_day.used_percentage // null) != null
                then (.rate_limits.seven_day.used_percentage | tostring) else "" end),
            (.workspace.git_worktree // ""),
            ((.exceeds_200k_tokens // false) | tostring),
            (if (.rate_limits.five_hour.resets_at // null) != null
                then (.rate_limits.five_hour.resets_at | tostring) else "" end),
            (if (.rate_limits.seven_day.resets_at // null) != null
                then (.rate_limits.seven_day.resets_at | tostring) else "" end)
        ] | .[]
    ' 2>/dev/null
)
MODEL=${_FIELDS[0]-}
DUR_MS=${_FIELDS[1]-}
SESSION_ID=${_FIELDS[2]-}
CWD=${_FIELDS[3]-}
COST=${_FIELDS[4]-}
LINES_ADDED=${_FIELDS[5]-}
LINES_REMOVED=${_FIELDS[6]-}
FIVE_HOUR_PCT=${_FIELDS[7]-}
SEVEN_DAY_PCT=${_FIELDS[8]-}
WORKTREE=${_FIELDS[9]-}
EXCEEDS_200K=${_FIELDS[10]-}
FIVE_HOUR_RESET=${_FIELDS[11]-}
# shellcheck disable=SC2034  # extracted for parity; 7d reset isn't rendered (week-away timestamp not useful as HH:MM)
SEVEN_DAY_RESET=${_FIELDS[12]-}
MODEL=${MODEL:-?}
DUR_MS=${DUR_MS:-0}
SESSION_ID=${SESSION_ID:-unknown}
CWD=${CWD:-?}
COST=${COST:-0}
LINES_ADDED=${LINES_ADDED:-0}
LINES_REMOVED=${LINES_REMOVED:-0}
EXCEEDS_200K=${EXCEEDS_200K:-false}

# Sanitize session_id against path traversal (CWE-22). The counter file path
# is built from SESSION_ID below — reject anything outside [A-Za-z0-9_-].
[[ "$SESSION_ID" =~ ^[A-Za-z0-9_-]+$ ]] || SESSION_ID="unknown"

# ---- Context usage (2 of 2 jq forks) ----------------------------------------
# 3-tier fallback because the field varies across Claude Code builds.
# Tier 1: official used_percentage. Tier 2: manual calc from token counts.
# Tier 3: tool-count heuristic (100 calls ~= 70%, 140 ~= capped 99).
CTX=$(echo "$INPUT" | jq -r '
    if (.context_window.used_percentage // null) != null then
        (.context_window.used_percentage | floor)
    elif (.current_usage // null) != null and (.context_window.context_window_size // null) != null then
        (((((.current_usage.input_tokens // 0)
            + (.current_usage.output_tokens // 0)
            + (.current_usage.cache_read_input_tokens // 0)
            + (.current_usage.cache_creation_input_tokens // 0))
            * 100) / .context_window.context_window_size) | floor)
    else
        empty
    end
' 2>/dev/null)

if [ -z "$CTX" ]; then
    # Tier 3 — derive from the tool-count counter kept by context-pressure.sh.
    TOOLS_FALLBACK=0
    FALLBACK_COUNTER="$HOME/.claude/.alloy-state/tool-count-${SESSION_ID}"
    [ -f "$FALLBACK_COUNTER" ] && TOOLS_FALLBACK=$(cat "$FALLBACK_COUNTER" 2>/dev/null || echo 0)
    CTX=$(( TOOLS_FALLBACK * 100 / 140 ))
    [ "$CTX" -gt 99 ] && CTX=99
fi
[ -z "$CTX" ] && CTX=0

# ---- Alloy version ----------------------------------------------------------
# Self-locating fallback chain. In preference order:
#   1. $CLAUDE_PLUGIN_ROOT/VERSION — set by Claude Code for plugin-marketplace installs.
#   2. <script-dir>/VERSION        — install.sh/activate.sh ship VERSION alongside hooks.
#   3. <script-dir>/../VERSION     — repo-root checkout (development use).
#   4. ~/.claude/.alloy-version    — legacy pin written by activate.sh (last-resort fallback).
# Fallback #4 is stale on `git pull` upgrades; #2 is the canonical source for installed users.
ALLOY_VERSION="?"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
for _candidate in \
    "${CLAUDE_PLUGIN_ROOT:-}/VERSION" \
    "${SCRIPT_DIR}/VERSION" \
    "${SCRIPT_DIR}/../VERSION" \
    "$HOME/.claude/.alloy-version"
do
    [ -z "$_candidate" ] && continue
    [ -f "$_candidate" ] || continue
    # Sanitize to a strict semver-ish allowlist and cap length.
    # Blocks ANSI escape injection (ESC[...m) and any other control bytes
    # that a malicious VERSION file could try to smuggle into the statusline.
    _v=$(LC_ALL=C tr -cd 'A-Za-z0-9.+-' < "$_candidate" 2>/dev/null | head -c 32)
    if [ -n "$_v" ]; then
        ALLOY_VERSION="$_v"
        break
    fi
done
unset _candidate _v

# ---- Session duration (ms → human) ------------------------------------------
DUR_S=$((DUR_MS / 1000))
if   [ "$DUR_S" -ge 3600 ]; then SESSION=$(printf '%dh%dm' "$((DUR_S/3600))" "$(((DUR_S%3600)/60))")
elif [ "$DUR_S" -ge 60 ];   then SESSION="$((DUR_S/60))m"
else                             SESSION="${DUR_S}s"
fi

# ---- Tool count — counter maintained by hooks/context-pressure.sh -----------
TOOLS=0
COUNTER="$HOME/.claude/.alloy-state/tool-count-${SESSION_ID}"
[ -f "$COUNTER" ] && TOOLS=$(cat "$COUNTER" 2>/dev/null || echo 0)

# ---- ANSI styles ------------------------------------------------------------
DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'
MAGENTA=$'\033[35m'; BLUE=$'\033[34m'

# Segment separator — " | " with the pipe dimmed. Defined up here so every
# conditional segment below can prepend it cleanly (and vanish when empty).
SEP=" ${DIM}|${RESET} "

# ---- ENH-6: IGNITE active badge --------------------------------------------
# Flag file written by hooks/ignite-detector.sh. Only render if file exists
# AND mtime is within the last 6 hours (prevents stale flags haunting sessions).
IGNITE_SEG=""
IGNITE_FLAG="$HOME/.claude/.alloy-state/ignite-active-${SESSION_ID}"
if [ -f "$IGNITE_FLAG" ]; then
    NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)
    # macOS `stat -f %m`, GNU `stat -c %Y` — try both, fall back to 0.
    FLAG_EPOCH=$(stat -f %m "$IGNITE_FLAG" 2>/dev/null || stat -c %Y "$IGNITE_FLAG" 2>/dev/null || echo 0)
    AGE=$(( NOW_EPOCH - FLAG_EPOCH ))
    if [ "$AGE" -ge 0 ] && [ "$AGE" -le 21600 ]; then
        IGNITE_SEG="${BOLD}${RED}[IGNITE]${RESET} "
    fi
fi
# IGNITE_SEG keeps its trailing space because it sits between ALLOY_SEG
# (trailing space) and MODEL_SEG (no leading space).

# ---- ENH-2: Git branch (+ dirty marker) ------------------------------------
# Skip the segment entirely if git is missing, cwd isn't a repo, or either
# command fails. Both git calls 2>/dev/null + exit-code guarded = fail-silent.
GIT_SEG=""
if command -v git &>/dev/null && [ -d "$CWD" ]; then
    if GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null) && [ -n "$GIT_BRANCH" ]; then
        # If working tree has uncommitted changes, append "*" dirty indicator.
        GIT_DIRTY=""
        if GIT_STATUS=$(git -C "$CWD" status --porcelain -uno 2>/dev/null) && [ -n "$GIT_STATUS" ]; then
            GIT_DIRTY="*"
        fi
        GIT_SEG="${SEP}${BLUE}⎇ ${GIT_BRANCH}${GIT_DIRTY}${RESET}"
    fi
fi

# ---- ENH-7: Worktree badge --------------------------------------------------
WORKTREE_SEG=""
if [ -n "${WORKTREE:-}" ]; then
    WORKTREE_SEG="${SEP}${MAGENTA}wt:${WORKTREE}${RESET}"
fi

# ---- CTX color + ENH-5: COMPACT SOON warning + ENH-8: 200k overflow --------
# Context window color by threshold. At >=85% flip to red bold + append the
# COMPACT SOON label so the user can't miss it.
CTX_COLOR=$GREEN
[ "$CTX" -ge 70 ] && CTX_COLOR=$YELLOW
[ "$CTX" -ge 85 ] && CTX_COLOR="${BOLD}${RED}"

CTX_SEG="${CTX_COLOR}ctx:${CTX}%${RESET}"
if [ "$CTX" -ge 85 ]; then
    CTX_SEG="${BOLD}${RED}ctx:${CTX}% COMPACT SOON${RESET}"
fi
if [ "$EXCEEDS_200K" = "true" ]; then
    CTX_SEG="${CTX_SEG} ${BOLD}${RED}!200k${RESET}"
fi

# ---- ENH-1: Session cost ----------------------------------------------------
# Render only when cost > 0. The $0.00 at session start was confusing (user
# feedback v1.6.2 — looks like a stuck field instead of an idle session).
# Color: dim <$0.10, yellow $0.10–$1.00, red >$1.00.
# COST is a string from jq's tostring; compare numerically via awk (no bc dep).
COST_SEG=""
if awk -v c="$COST" 'BEGIN{exit !(c+0 > 0)}' 2>/dev/null; then
    COST_COLOR=$DIM
    if awk -v c="$COST" 'BEGIN{exit !(c+0 > 1.0)}' 2>/dev/null; then
        COST_COLOR=$RED
    elif awk -v c="$COST" 'BEGIN{exit !(c+0 >= 0.10)}' 2>/dev/null; then
        COST_COLOR=$YELLOW
    fi
    COST_FMT=$(awk -v c="$COST" 'BEGIN{printf "%.2f", c+0}' 2>/dev/null)
    [ -z "$COST_FMT" ] && COST_FMT="0.00"
    COST_SEG="${SEP}${COST_COLOR}\$${COST_FMT}${RESET}"
    # Hourly burn rate once we have >1min of data.
    if [ "$DUR_MS" -gt 60000 ] 2>/dev/null; then
        RATE=$(awk -v c="$COST" -v m="$DUR_MS" 'BEGIN{printf "%.1f", c/(m/3600000)}' 2>/dev/null)
        [ -n "$RATE" ] && COST_SEG="${COST_SEG} ${DIM}~\$${RATE}/h${RESET}"
    fi
fi

# ---- ENH-3: Rate limits (5h + 7d), always-on (v2.1) -------------------------
# v2.1 adds @HH:MM reset tag to 5h only (7d reset is a week away — useless as wall-clock).
RATE_SEG=""
RATE_PARTS=""
for pair in "5h:${FIVE_HOUR_PCT:-}:${FIVE_HOUR_RESET:-}" "7d:${SEVEN_DAY_PCT:-}:"; do
    label=${pair%%:*}
    rest=${pair#*:}
    val=${rest%%:*}
    reset_at=${rest#*:}
    [ -z "$val" ] && continue
    # Strip any decimal portion so bash integer arithmetic works.
    val_int=${val%%.*}
    [[ "$val_int" =~ ^[0-9]+$ ]] || continue
    clr=$GREEN
    [ "$val_int" -ge 70 ] && clr=$YELLOW
    [ "$val_int" -ge 90 ] && clr=$RED
    reset_tag=""
    # Gate reset_at to digits-only before passing to date (defense in depth:
    # prevents flag-injection via e.g. "-r" or "--help" from malformed stdin).
    if [[ "$reset_at" =~ ^[0-9]+$ ]] && [ "$reset_at" != "0" ]; then
        # macOS: date -r EPOCH; GNU: date -d @EPOCH.
        reset_time=$(date -r "$reset_at" '+%H:%M' 2>/dev/null || date -d "@$reset_at" '+%H:%M' 2>/dev/null)
        [ -n "$reset_time" ] && reset_tag=" ${DIM}@${reset_time}${RESET}"
    fi
    RATE_PARTS="${RATE_PARTS}${clr}${label}:${val_int}%${RESET}${reset_tag} "
done
if [ -n "$RATE_PARTS" ]; then
    RATE_SEG="${SEP}${RATE_PARTS% }"
fi

# ---- ENH-4: Lines-changed delta ---------------------------------------------
LINES_SEG=""
LA_INT=${LINES_ADDED%%.*}; LR_INT=${LINES_REMOVED%%.*}
[[ "$LA_INT" =~ ^[0-9]+$ ]] || LA_INT=0
[[ "$LR_INT" =~ ^[0-9]+$ ]] || LR_INT=0
if [ $(( LA_INT + LR_INT )) -gt 0 ]; then
    LINES_SEG="${SEP}${GREEN}+${LA_INT}${RESET}${DIM}/${RESET}${RED}-${LR_INT}${RESET}"
fi

# ---- CWD basename -----------------------------------------------------------
CWD_BASE=$(basename "$CWD")

# ---- Compose final line -----------------------------------------------------
# Layout (conditional segments drop out cleanly when empty):
#   [alloy VER] [IGNITE] MODEL | ⎇ branch* | wt:NAME | ctx:N% !200k | $X.XX | 5h:P% 7d:P% | +A/-R | session:DUR | ⚒N | cwd
#
# Pre-compose fixed segments here to keep the final printf format string
# short and unambiguous (no counting mistakes between specifiers and args).
ALLOY_SEG="${DIM}[alloy ${ALLOY_VERSION}]${RESET} "
MODEL_SEG="${BOLD}${MODEL}${RESET}"
SESSION_SEG="${SEP}session:${SESSION}"
TOOLS_SEG="${SEP}⚒${TOOLS}"
CWD_SEG="${SEP}${CYAN}${CWD_BASE}${RESET}"

# CTX_SEG is always-present but self-coloring.
# IGNITE_SEG, GIT_SEG, WORKTREE_SEG, COST_SEG, RATE_SEG, LINES_SEG are conditional:
# each is either empty or pre-wrapped with its leading separator + trailing
# space, so they vanish cleanly when not applicable.
printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
    "$ALLOY_SEG" \
    "$IGNITE_SEG" \
    "$MODEL_SEG" \
    "$GIT_SEG" \
    "$WORKTREE_SEG" \
    "$SEP" \
    "$CTX_SEG" \
    "$COST_SEG" \
    "$RATE_SEG" \
    "$LINES_SEG" \
    "$SESSION_SEG" \
    "$TOOLS_SEG" \
    "$CWD_SEG"
