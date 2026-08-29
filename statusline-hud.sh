#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#                              Author: Paul Newell
#                          Copyright (c) 2026 Paul Newell
# ════════════════════════════════════════════════════════════════════════════
# statusline-hud.sh — Claude Code statusline.
# Reads one JSON payload from stdin, prints one ANSI-coloured status line.
# Sections include: cwd, git, model + effort/fast badges, ctx/5h/7d power
# bars, prompt-cache hit ratio, GitLab MR / GitHub PR badge, and a 🔥 cumulative session
# spend (or input-token) gauge. Reorder or disable sections by editing SEGMENTS in the CONFIG
# block below.
set -u
command -v jq >/dev/null || { printf "\033[38;5;196m⚠ jq missing\033[0m"; exit 1; }

# ─── CONFIG ─────────────────────────────────────────────────────────────────
# All colours are xterm-256 indices (0–255). Preview palette at
# https://www.ditig.com/256-colors. To retheme: edit ONLY this block.

# Bar color tiers, applied to the WHOLE bar as p crosses each threshold:
# (green, yellow, orange, red). The bar flips to the next colour at each
# boundary rather than painting a gradient across cells.
TIER_COLOR=(46 226 214 196)

# Per-bar tier thresholds — three boundaries between the four TIER_COLOR
# values. Below the first threshold → green; at/above the last → red.
# ctx warns earlier than rate-limit counters because context degrades
# Claude's coherence well before the window fills.
BAR_LINEAR=(60 80 95)
BAR_CTX=(30 50 60)

# Bar chrome
C_BAR_BG=236            # dark grey trough behind each bar
C_BAR_EMPTY=240         # mid grey for empty (░) cells
C_SEP=240               # colour of the section separator
SEP_CHAR=" · "          # glyph between sections (try " | ", " • ", " ▏ ")

# Labels and text
C_DIR=36                # cwd (cyan)
C_MODEL=34              # model name (blue) — fallback for unrecognised models
C_MODEL_OPUS=208        # Opus → orange: premium, burns rate limit faster
C_MODEL_SONNET=39       # Sonnet → bright blue: balanced workhorse
C_MODEL_HAIKU=46        # Haiku → green: cheap & fast, conserve mode
C_GIT_WRAP=34           # "git:(" and ")" (blue)
C_GIT_BRANCH=31         # branch name (red)
C_GIT_AHEAD=39          # ↑N↓N indicator (bright blue)
C_GIT_DIRTY=196         # ✗ dirty marker (red)
C_RESET_TXT=245         # "↺Xh Ym" countdown text

# Effort badges (claude reasoning level)
C_EFFORT_LOW=240
C_EFFORT_MED=250
C_EFFORT_HIGH=220
C_EFFORT_XHIGH=208
C_EFFORT_MAX=196
C_FAST=226              # 🚀 fast-mode indicator

# Cumulative session totals (🔥). Read straight from the JSON — no state
# files. Answers "how heavy is this session overall?".
#
# TURN_UNIT picks what the segment measures:
#   usd    — running USD total (cumulative session spend at API list prices).
#            Monotonic, survives /compact, and rewards using cheaper models.
#            On Pro/Max this is an estimate, not your bill.
#   tokens — current context-window input tokens. Not strictly cumulative
#            (drops after /compact or cache turnover as of Claude Code
#            v2.1.132), but reflects what burns rate limits in the moment.
TURN_UNIT=usd      # usd | tokens
case "$TURN_UNIT" in usd|tokens) ;; *) TURN_UNIT=usd ;; esac

# Thresholds for TURN_UNIT=usd (dollars). Tuned for a Max-plan user where
# a heavy Opus session can run $20+ in API-equivalent estimated spend.
# PAYG users may want to dial these down (e.g. 0.50 / 2.00).
TURN_HI_USD=20.00
TURN_MED_USD=5.00
# Thresholds for TURN_UNIT=tokens (raw input tokens). As of Claude Code
# v2.1.132 total_input_tokens is the LIVE context window, not a cumulative
# session total, so these are tuned as fractions of a 200k context: red ≈
# "context filling up, consider /compact or /clear". Raise for a 1M model.
TURN_HI_TOK=160000
TURN_MED_TOK=120000
# Colours are 16-colour SGR codes (NOT 256-colour indices) because awk emits
# them into a `\033[%dm` format. Shared by both units.
C_TURN_HI=31            # red    >= high threshold
C_TURN_MED=33           # yellow >= med threshold
C_TURN_LO=92            # bright green, otherwise

# Cache-hit ratio — thresholds in percent, colours are 16-colour SGR codes
CACHE_HI_PCT=60
CACHE_MED_PCT=30
C_CACHE_HI=92
C_CACHE_MED=33
C_CACHE_LO=31

C_CACHE_COLD=36         # ❄ when prompt_cache.warm=false (cyan, informational)

# Minimums before a derived metric is meaningful enough to display
CACHE_MIN_TOKENS=5000       # below this, cache hit% is statistically meaningless
RESET_COUNTDOWN_PCT=60      # show "resets in ↺Xh Ym" once a limit crosses this

# MR/PR badge (mr segment). The `origin` remote picks the CLI: github.com →
# `gh pr view`, anything else → `glab mr view` (gitlab.com or self-hosted).
# Both take ~1s and the statusline renders on every keystroke, so lookups run
# in the background and are cached per repo+branch. A render never waits on
# the CLI: stale entries are shown as-is while a refresh runs. Silently
# absent when the matching CLI isn't on PATH or there's no origin.
MR_TTL=60                        # seconds before a cached lookup is refreshed
MR_CACHE_DIR=/tmp/statusline-hud-$UID
C_MR_OK=46              # opened + mergeable → green  "!23 ✓"
C_MR_BAD=196            # conflicts / unmergeable → red "!23 ✗"
C_MR_PENDING=226        # pipeline / mergeability still checking → yellow "!23"
C_MR_DRAFT=245          # draft → grey "✎ !23"
C_MR_MERGED=99          # merged → purple "⇄ !23"
C_MR_CLOSED=240         # closed → dim "!23"
MR_PREFIX_GITLAB="🦊 !"  # before a GitLab MR number; try "!", "MR ", or Nerd Font " " if it renders
MR_PREFIX_GITHUB="🐙 #"  # before a GitHub PR number; try "#", "PR "
# Pipeline dot (ci segment): latest pipeline/run for the branch, linked to it.
CI_PASS="🟢"; CI_FAIL="🔴"; CI_RUN="🟡"; CI_WAIT="⚪"; CI_CANCEL="⚫"; CI_SKIP="⏭"; CI_MANUAL="✋"
# CI_WAIT also stands in when the newest pipeline is for an older commit than
# your local HEAD — its result isn't about the code you're looking at.
C_MR_LINK=39            # "!23" text when the badge is a clickable link;
                        # "" = keep the state colour (underline only)
MR_LINK_STYLE=0         # SGR applied to a linked ref: 4 underline, 1 bold, 0 none

# Which segments render, in left-to-right order. Comment a line to disable;
# move lines to reorder. Recognised: dir, git, model, ctx, rl5, rl7, cache, turn
SEGMENTS=(
  # dir         # current working directory
  git         # branch name, ahead/behind, dirty marker
  model       # model display name, effort badge, fast-mode rocket
  ctx         # context-window usage bar
  rl5         # 5-hour rate-limit bar with reset countdown
  rl7         # 7-day rate-limit bar with reset countdown
  cache       # session-wide cache-hit ratio (❄ when the prompt cache is cold)
  # opcode      # opcode-lite verdict — disabled, no longer shown in statusline
  # turn        # cumulative session tokens or USD (🔥)
  mr          # GitLab MR / GitHub PR badge for the current branch (glab / gh)
  ci          # latest pipeline for the branch as a traffic-light dot (glab / gh)
)
# ────────────────────────────────────────────────────────────────────────────

# ─── Pre-baked ANSI escapes (assignment-time expansion via $'\033') ─────────
# Use these instead of literal escapes in printf format strings.
C_OFF=$'\033[0m'
SEP=$'\033[38;5;'"$C_SEP"'m'"$SEP_CHAR$C_OFF"
BG_BAR=$'\033[48;5;'"$C_BAR_BG"'m'
EMPTY_FG=$'\033[38;5;'"$C_BAR_EMPTY"'m'
RESET_FG=$'\033[38;5;'"$C_RESET_TXT"'m'

# ─── Parse JSON payload ─────────────────────────────────────────────────────
# tsv columns, in order:
#   cwd, model, used%, cost$, rl5%, effort, fast,
#   rl7%, rl5_reset, rl7_reset, cache_read_tokens, total_input_tokens,
#   prompt_cache.hit_ratio (0–1), prompt_cache.warm (true/false)
# Optional fields emit "-" rather than "" so `read` (tab is whitespace IFS,
# consecutive tabs collapse) keeps every column in place.
tsv=$(jq -r '[
  .workspace.current_dir // .cwd // "",
  .model.display_name // .model.name // "?",
  ((.context_window.used_percentage // 0) | tonumber? // 0 | floor),
  ((.cost.total_cost_usd // 0) | tonumber? // 0),
  ((.rate_limits.five_hour.used_percentage // 0) | tonumber? // 0 | floor),
  .effort.level // "-",
  (.fast_mode // false | tostring),
  ((.rate_limits.seven_day.used_percentage // 0) | tonumber? // 0 | floor),
  ((.rate_limits.five_hour.resets_at // 0) | tonumber? // 0 | floor),
  ((.rate_limits.seven_day.resets_at // 0) | tonumber? // 0 | floor),
  ((.context_window.current_usage.cache_read_input_tokens // 0) | tonumber? // 0 | floor),
  ((.context_window.total_input_tokens // 0) | tonumber? // 0 | floor),
  (.prompt_cache.hit_ratio | if type == "number" then tostring else "-" end),
  (.prompt_cache.warm | if type == "boolean" then tostring else "-" end)
] | @tsv' 2>/dev/null) || { printf "\033[38;5;240m(parse failed)\033[0m"; exit 0; }
[ -z "$tsv" ] && { printf "\033[38;5;240m(parse failed)\033[0m"; exit 0; }

# The 'x' prefix is a sentinel that stops `read` from collapsing a leading
# empty cwd field; it's stripped immediately below.
IFS=$'\t' read -r cwd model used cost rl5 effort fast rl7 rl5_reset rl7_reset cache_read total_input pc_ratio pc_warm < <(printf 'x%s\n' "$tsv")
cwd="${cwd#x}"
used=${used:-0} rl5=${rl5:-0} cost=${cost:-0} effort=${effort:-} fast=${fast:-false}
rl7=${rl7:-0} rl5_reset=${rl5_reset:-0} rl7_reset=${rl7_reset:-0} cache_read=${cache_read:-0} total_input=${total_input:-0}
[ "$pc_ratio" = "-" ] && pc_ratio=""
[ "$pc_warm" = "-" ] && pc_warm=""
[ "$effort" = "-" ] && effort=""

# Strip control bytes from any field that will be emitted to the terminal or
# passed to git -C. A hostile git repo can create a branch like
# `$'feature\033[2J'` whose name contains a raw ESC byte; without this scrub
# the byte would survive into `printf '%s' "$out"` and let the repo inject
# arbitrary ANSI (clear screen, set window title, OSC 8 hyperlinks, etc.) on
# every render. Same risk for any `cwd` or `model` value that ever contains
# control bytes. Pure bash globstrip avoids forking tr — cheap on a hot path.
SCRUB_PAT=$'[\001-\037\177]'
cwd="${cwd//$SCRUB_PAT/}"
model="${model//$SCRUB_PAT/}"

# Pick a model-tier colour for the name (Opus orange, Sonnet blue, Haiku green).
# Substring match handles every variant: "Opus 4.7 (1M context)", "opus-4-7",
# future "Opus 5", etc. Unknown models keep the neutral blue fallback so new
# releases render visibly without code changes.
model_color=$C_MODEL
case "$model" in
  *[Oo]pus*)   model_color=$C_MODEL_OPUS ;;
  *[Ss]onnet*) model_color=$C_MODEL_SONNET ;;
  *[Hh]aiku*)  model_color=$C_MODEL_HAIKU ;;
esac

# ─── Build derived display values ───────────────────────────────────────────

# Effort/fast-mode badge (rendered next to model name)
badge=""
case "$effort" in
  low)    badge=$(printf " \033[38;5;%dm⚡Lo%s"  "$C_EFFORT_LOW"   "$C_OFF") ;;
  medium) badge=$(printf " \033[38;5;%dm⚡Med%s" "$C_EFFORT_MED"   "$C_OFF") ;;
  high)   badge=$(printf " \033[38;5;%dm⚡Hi%s"  "$C_EFFORT_HIGH"  "$C_OFF") ;;
  xhigh)  badge=$(printf " \033[38;5;%dm⚡xHi%s" "$C_EFFORT_XHIGH" "$C_OFF") ;;
  max)    badge=$(printf " \033[38;5;%dm⚡Max%s" "$C_EFFORT_MAX"   "$C_OFF") ;;
esac
[ "$fast" = "true" ] && badge+=$(printf " \033[38;5;%dm🚀%s" "$C_FAST" "$C_OFF")

# Model name — collapse "(1M context)" → "(1M)" so it doesn't dominate the line
case "$model" in
  *' (1M'*')'*) model="${model% (1M*}"' (1M)' ;;
esac

# Directory — last two path segments only
home_rel="${cwd/#$HOME/~}"
case "$home_rel" in
  */*/*)
    tail="${home_rel##*/}"
    rest="${home_rel%/*}"
    dir="${rest##*/}/$tail"
    ;;
  *) dir="$home_rel" ;;
esac

# Git status: branch, ahead/behind (↑N↓N) via @{u}, dirty marker (✗).
# git_safe() neuters config that would execute attacker-controlled code from a
# hostile .git/config — core.fsmonitor runs on every `git status`, hooks on
# many subcommands. The statusline fires on every render, so a malicious repo
# could otherwise run code on every keystroke.
git_safe() { git -C "$cwd" -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"; }
branch="" dirty="" ab=""
if [ -n "$cwd" ] && git_safe rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git_safe branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git_safe rev-parse --short HEAD 2>/dev/null)
  branch="${branch//$SCRUB_PAT/}"
  # Truncate to 20 codepoints. Bash's ${#var}/${var:0:n} are codepoint-aware
  # under a UTF-8 locale. en_US.UTF-8 ships on macOS by default and on
  # virtually every standard Linux. If absent (stripped containers), bash
  # falls back to byte semantics — one over-truncated render, never crashes.
  if [ -n "$branch" ] && [ "${#branch}" -gt 20 ]; then
    branch=$(LC_ALL=en_US.UTF-8; (( ${#branch} > 20 )) && printf '%s…' "${branch:0:19}" || printf '%s' "$branch")
  fi
  [ -n "$(git_safe status --porcelain --untracked-files=no 2>/dev/null | head -1)" ] && dirty="*"
  if c=$(git_safe rev-list --count --left-right '@{u}...HEAD' 2>/dev/null) && [ -n "$c" ]; then
    a=${c##*$'\t'} b=${c%%$'\t'*}
    (( a > 0 )) && ab+="↑$a"
    (( b > 0 )) && ab+="↓$b"
  fi
fi
git_part=""
[ -n "$branch" ] && git_part=$(printf " \033[38;5;%dmgit:(\033[38;5;%dm%s\033[38;5;%dm)%s" \
                                "$C_GIT_WRAP" "$C_GIT_BRANCH" "$branch" "$C_GIT_WRAP" "$C_OFF")
[ -n "$ab" ]     && git_part+=$(printf " \033[38;5;%dm%s%s" "$C_GIT_AHEAD" "$ab" "$C_OFF")
[ -n "$dirty" ]  && git_part+=$(printf " \033[38;5;%dm✗%s"  "$C_GIT_DIRTY" "$C_OFF")

# Per-session totals (🔥). Cumulative USD spend (default) or input-token
# count, straight from the JSON — no snapshot files, no disk state. Tiers:
# green under TURN_MED, yellow MED→HI, red ≥HI (USD or token thresholds
# depending on TURN_UNIT).
turn=""
if [ "$TURN_UNIT" = tokens ]; then
  read -r label col < <(LC_ALL=C awk \
      -v v="$total_input" \
      -v hi="$TURN_HI_TOK" -v med="$TURN_MED_TOK" \
      -v chi="$C_TURN_HI" -v cmed="$C_TURN_MED" -v clo="$C_TURN_LO" \
      'BEGIN{col=(v>=hi?chi:v>=med?cmed:clo);
             if(v>=1000000) s=sprintf("%.1fM",v/1000000);
             else if(v>=1000) s=sprintf("%.0fk",v/1000);
             else s=sprintf("%d",v);
             printf "%s %d\n", s, col}')
  turn=$(printf "  \033[%dm🔥 %s%s" "$col" "$label" "$C_OFF")
else
  read -r amount col < <(LC_ALL=C awk \
      -v v="$cost" \
      -v hi="$TURN_HI_USD" -v med="$TURN_MED_USD" \
      -v chi="$C_TURN_HI" -v cmed="$C_TURN_MED" -v clo="$C_TURN_LO" \
      'BEGIN{printf "%.2f %d\n", v, (v>=hi?chi:v>=med?cmed:clo)}')
  turn=$(printf "  \033[%dm🔥 \$%s%s" "$col" "$amount" "$C_OFF")
fi

# ─── Power-bar renderer ─────────────────────────────────────────────────────
# bar() — render a 5-cell sub-stepped power bar in one tier colour.
# Args:    $1       = percent (0–100, clamped, non-integers → 0)
#          $2..$4   = three tier-boundary thresholds. Default linear 60/80/95.
# Output:  "<fill>|<empty>|" on stdout. Fill carries one ANSI colour prefix;
#          empty is plain ░ characters (caller adds EMPTY_FG).
# Each of the 5 cells is sub-divided into 8 steps drawn with ▏▎▍▌▋▊▉█ so the
# bar moves visibly within a tier instead of waiting for the next boundary.
E_FULL="░░░░░"
BAR_STEPS=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█")
bar() {
  local p="${1:-0}" t1="${2:-60}" t2="${3:-80}" t3="${4:-95}"
  [[ "$p" =~ ^-?[0-9]+$ ]] || p=0
  (( p < 0 )) && p=0
  (( p > 100 )) && p=100
  local color=${TIER_COLOR[0]}
  (( p >= t1 )) && color=${TIER_COLOR[1]}
  (( p >= t2 )) && color=${TIER_COLOR[2]}
  (( p >= t3 )) && color=${TIER_COLOR[3]}
  local full=$(( p / 20 )) sub=$(( (p % 20) * 8 / 20 ))
  local fill="" i
  for (( i=0; i<full; i++ )); do fill+="█"; done
  local empty_len
  if (( sub > 0 && full < 5 )); then
    fill+="${BAR_STEPS[$sub]}"
    empty_len=$(( 4 - full ))
  else
    empty_len=$(( 5 - full ))
  fi
  if [ -n "$fill" ]; then
    printf '\033[38;5;%dm%s|%s|' "$color" "$fill" "${E_FULL:0:empty_len}"
  else
    printf '|%s|' "${E_FULL:0:empty_len}"
  fi
}
IFS='|' read -r ctx_fill ctx_empty _ < <(bar "${used:-0}" "${BAR_CTX[@]}")
IFS='|' read -r rl5_fill rl5_empty _ < <(bar "${rl5:-0}" "${BAR_LINEAR[@]}")
IFS='|' read -r rl7_fill rl7_empty _ < <(bar "${rl7:-0}" "${BAR_LINEAR[@]}")

# ─── Reset countdown ────────────────────────────────────────────────────────
# fmt_reset — convert a unix epoch into "Xh Ym" or "Ym".
# Args:   $1 = unix epoch (resets_at from JSON)
# Output: countdown string, or empty if already expired.
fmt_reset() {
  local now=$(date +%s) target="$1" diff h m
  diff=$(( target - now ))
  (( diff <= 0 )) && return
  h=$(( diff / 3600 ))
  m=$(( (diff % 3600) / 60 ))
  if (( h > 0 )); then printf "%dh%dm" "$h" "$m"
  else printf "%dm" "$m"
  fi
}
# Show countdown next to whichever limit bar is more constrained (and ≥ threshold).
reset_str=""
if (( rl5 >= rl7 )) && (( rl5 >= RESET_COUNTDOWN_PCT )); then
  reset_str=$(fmt_reset "$rl5_reset")
elif (( rl7 >= RESET_COUNTDOWN_PCT )); then
  reset_str=$(fmt_reset "$rl7_reset")
fi

# ─── Cache hit ratio ────────────────────────────────────────────────────────
# Prefer prompt_cache (Claude Code ≥ 2.1.251): session-wide hit ratio plus
# whether the cached prefix is still warm. Cold (❄) means the next turn
# re-caches the whole prefix. Older payloads fall back to per-turn maths,
# which is only meaningful once the session has crossed CACHE_MIN_TOKENS.
cache_str=""
ratio=""
glyph="↩"
if [ -n "$pc_ratio" ]; then
  ratio=$(LC_ALL=C awk -v r="$pc_ratio" 'BEGIN{printf "%d", r*100}')
  [[ "$ratio" =~ ^[0-9]+$ ]] || ratio=0
  [ "$pc_warm" = false ] && glyph="❄"
elif (( total_input > CACHE_MIN_TOKENS )); then
  ratio=$(( cache_read * 100 / total_input ))
fi
if [ -n "$ratio" ]; then
  (( ratio > 100 )) && ratio=100
  if   [ "$glyph" = "❄" ];           then ccol=$C_CACHE_COLD
  elif (( ratio >= CACHE_HI_PCT ));  then ccol=$C_CACHE_HI
  elif (( ratio >= CACHE_MED_PCT )); then ccol=$C_CACHE_MED
  else                                    ccol=$C_CACHE_LO
  fi
  cache_str=$(printf "\033[%dm%s%d%%%s" "$ccol" "$glyph" "$ratio" "$C_OFF")
fi

# ─── MR/PR badge + pipeline dot ─────────────────────────────────────────────
# Cache file per repo+branch holds one TSV line: iid state draft status
# conflicts web_url. An empty file is a cached "no MR/PR". GitHub's states
# are normalised into the same vocabulary as GitLab's so one renderer serves
# both. The badge is wrapped in an OSC 8 hyperlink to web_url, so terminals
# that support it (Ghostty, iTerm2, Kitty, WezTerm) make it Cmd/Ctrl-
# clickable; others show plain text. Lookups run via bg_refresh() in a
# detached background job so the render (and anything capturing its stdout)
# never waits on them; a lock dir stops concurrent renders from stacking up
# CLI calls. The pipeline dot shares the same host, key and TTL.
mr_str="" ci_str=""
# bg_refresh <cache-file> <fetch-fn>: run fetch-fn (stdout → cache file) in a
# detached background job. All fds closed so the render never waits on it.
bg_refresh() {
  local f="$1" fetch="$2" lock="$1.lock"
  mkdir "$lock" 2>/dev/null || {
    [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null
    return
  }
  (
    cd "$cwd" 2>/dev/null || exit
    "$fetch" > "$f.tmp" 2>/dev/null
    mv -f "$f.tmp" "$f" 2>/dev/null
    rmdir "$lock" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null
}
# Cache line: iid state draft status conflicts url
fetch_mr() {
  if [ "$mr_host" = github ]; then
    gh pr view --json number,state,isDraft,mergeable,mergeStateStatus,url 2>/dev/null \
      | jq -r '[
          .number,
          ({OPEN:"opened", MERGED:"merged", CLOSED:"closed"}[.state] // "opened"),
          (.isDraft|tostring),
          ({CLEAN:"mergeable", HAS_HOOKS:"mergeable", UNSTABLE:"mergeable",
            DIRTY:"conflict", BEHIND:"checking", BLOCKED:"checking",
            UNKNOWN:"checking", DRAFT:"checking"}[.mergeStateStatus] // "checking"),
          ((.mergeable == "CONFLICTING")|tostring),
          (.url // "-")
        ] | @tsv'
  else
    glab mr view --output json 2>/dev/null \
      | jq -r '[.iid, .state, (.draft|tostring), .detailed_merge_status, (.has_conflicts|tostring), (.web_url // "-")] | @tsv'
  fi
}
# Cache line: status sha url — status normalised to GitLab's vocabulary
fetch_ci() {
  if [ "$mr_host" = github ]; then
    gh run list --branch "$branch" --limit 1 --json status,conclusion,headSha,url 2>/dev/null \
      | jq -r '.[0] | select(. != null) | [
          (if .status == "completed" then
             ({success:"success", failure:"failed", timed_out:"failed", startup_failure:"failed",
               cancelled:"canceled", skipped:"skipped", action_required:"manual"}[.conclusion] // "pending")
           elif .status == "in_progress" then "running" else "pending" end),
          .headSha, (.url // "-")
        ] | @tsv'
  else
    glab ci get --output json 2>/dev/null \
      | jq -r 'select(.status != null) | [.status, .sha, (.web_url // "-")] | @tsv'
  fi
}
mr_host=""
if [ -n "$branch" ]; then
  # Remote to classify: origin, else the branch's upstream remote, else the
  # first remote listed. Repos that name their only remote `gitlab` or
  # `github` are common enough to matter.
  remote=origin
  git_safe remote get-url origin >/dev/null 2>&1 || {
    remote=$(git_safe config "branch.$branch.remote" 2>/dev/null)
    [ -z "$remote" ] && remote=$(git_safe remote 2>/dev/null | head -1)
  }
  origin=""
  [ -n "$remote" ] && origin=$(git_safe remote get-url "$remote" 2>/dev/null)
  case "$origin" in
    "")                                 ;;
    *github.com[:/]*)                   command -v gh   >/dev/null 2>&1 && mr_host=github ;;
    *)                                  command -v glab >/dev/null 2>&1 && mr_host=gitlab ;;
  esac
fi
if [ -n "$mr_host" ]; then
  mr_prefix=$MR_PREFIX_GITLAB
  [ "$mr_host" = github ] && mr_prefix=$MR_PREFIX_GITHUB
  top=$(git_safe rev-parse --show-toplevel 2>/dev/null)
  key=$(printf '%s|%s' "$top" "$branch" | cksum | cut -d' ' -f1)
  mkdir -p "$MR_CACHE_DIR" 2>/dev/null
  mr_file="$MR_CACHE_DIR/$key.mr"
  if [ -f "$mr_file" ]; then
    IFS=$'\t' read -r mr_iid mr_state mr_draft mr_status mr_conflicts mr_url < "$mr_file" || true
    mr_iid="${mr_iid//$SCRUB_PAT/}" mr_state="${mr_state//$SCRUB_PAT/}"
    mr_status="${mr_status//$SCRUB_PAT/}" mr_url="${mr_url//$SCRUB_PAT/}"
    case "$mr_url" in https://*|http://*) ;; *) mr_url="" ;; esac
    if [[ "$mr_iid" =~ ^[0-9]+$ ]]; then
      # Badge = [pre glyph] ref [post glyph], all in one state colour. A
      # linked badge restyles just the ref (underline + C_MR_LINK) so the
      # state glyph keeps carrying the status signal.
      mr_pre="" mr_post="" mr_col=$C_MR_PENDING
      case "$mr_state" in
        merged) mr_pre="⇄" mr_col=$C_MR_MERGED ;;
        closed) mr_col=$C_MR_CLOSED ;;
        *)
          if [ "$mr_draft" = true ]; then
            mr_pre="✎" mr_col=$C_MR_DRAFT
          elif [ "$mr_conflicts" = true ]; then
            mr_post="✗" mr_col=$C_MR_BAD
          else
            case "$mr_status" in
              mergeable) mr_post="✓" mr_col=$C_MR_OK ;;
              checking|unchecked|ci_still_running|preparing|approvals_syncing) ;;
              *)         mr_post="✗" mr_col=$C_MR_BAD ;;
            esac
          fi ;;
      esac
      if [ -n "$mr_url" ]; then
        mr_str=""
        [ -n "$mr_pre" ]  && mr_str+=$(printf "\033[38;5;%dm%s%s " "$mr_col" "$mr_pre" "$C_OFF")
        mr_str+=$(printf "\033[%dm\033[38;5;%dm%s%s" "$MR_LINK_STYLE" "${C_MR_LINK:-$mr_col}" "$mr_prefix$mr_iid" "$C_OFF")
        [ -n "$mr_post" ] && mr_str+=$(printf " \033[38;5;%dm%s%s" "$mr_col" "$mr_post" "$C_OFF")
        mr_str=$'\033]8;;'"$mr_url"$'\a'"$mr_str"$'\033]8;;\a'
      else
        mr_str=$(printf "\033[38;5;%dm%s%s%s%s" "$mr_col" "${mr_pre:+$mr_pre }" "$mr_prefix$mr_iid" "${mr_post:+ $mr_post}" "$C_OFF")
      fi
    fi
    stale=$(find "$mr_file" -maxdepth 0 -newermt "-$MR_TTL seconds" 2>/dev/null)
    [ -z "$stale" ] && bg_refresh "$mr_file" fetch_mr
  else
    bg_refresh "$mr_file" fetch_mr
  fi

  # ─── Pipeline dot ───
  ci_file="$MR_CACHE_DIR/$key.ci"
  if [ -f "$ci_file" ]; then
    IFS=$'\t' read -r ci_status ci_sha ci_url < "$ci_file" || true
    ci_status="${ci_status//$SCRUB_PAT/}" ci_sha="${ci_sha//$SCRUB_PAT/}" ci_url="${ci_url//$SCRUB_PAT/}"
    case "$ci_url" in https://*|http://*) ;; *) ci_url="" ;; esac
    if [ -n "$ci_status" ]; then
      head_sha=$(git_safe rev-parse HEAD 2>/dev/null)
      if [ -n "$ci_sha" ] && [ "$ci_sha" != "$head_sha" ]; then
        ci_dot=$CI_WAIT
      else
        case "$ci_status" in
          success)                 ci_dot=$CI_PASS ;;
          failed)                  ci_dot=$CI_FAIL ;;
          running)                 ci_dot=$CI_RUN ;;
          canceled|canceling)      ci_dot=$CI_CANCEL ;;
          skipped)                 ci_dot=$CI_SKIP ;;
          manual)                  ci_dot=$CI_MANUAL ;;
          *)                       ci_dot=$CI_WAIT ;;
        esac
      fi
      ci_str="$ci_dot"
      [ -n "$ci_url" ] && ci_str=$'\033]8;;'"$ci_url"$'\a'"$ci_str"$'\033]8;;\a'
    fi
    stale=$(find "$ci_file" -maxdepth 0 -newermt "-$MR_TTL seconds" 2>/dev/null)
    [ -z "$stale" ] && bg_refresh "$ci_file" fetch_ci
  else
    bg_refresh "$ci_file" fetch_ci
  fi
fi

# ─── Segment renderers ──────────────────────────────────────────────────────
# Each function returns the segment string on stdout, or empty if it should
# be suppressed (e.g. cache below CACHE_MIN_TOKENS, git when not in a repo).
# Add a new segment by defining seg_<name>() and adding <name> to SEGMENTS.
seg_dir()   { printf "\033[38;5;%dm%s%s" "$C_DIR" "$dir" "$C_OFF"; }
seg_git()   { printf "%s" "$git_part"; }
seg_model() { printf "\033[38;5;%dm%s%s%s" "$model_color" "$model" "$C_OFF" "$badge"; }
seg_ctx()   { printf "ctx:%s%s%s%s%s" "$BG_BAR" "$ctx_fill" "$EMPTY_FG" "$ctx_empty" "$C_OFF"; }
seg_rl5()   {
  printf "5h:%s%s%s%s%s" "$BG_BAR" "$rl5_fill" "$EMPTY_FG" "$rl5_empty" "$C_OFF"
  if [ -n "$reset_str" ] && (( rl5 >= rl7 )) && (( rl5 >= RESET_COUNTDOWN_PCT )); then
    printf " %s↺%s%s" "$RESET_FG" "$reset_str" "$C_OFF"
  fi
}
seg_rl7()   {
  printf "7d:%s%s%s%s%s" "$BG_BAR" "$rl7_fill" "$EMPTY_FG" "$rl7_empty" "$C_OFF"
  if [ -n "$reset_str" ] && ! { (( rl5 >= rl7 )) && (( rl5 >= RESET_COUNTDOWN_PCT )); }; then
    printf " %s↺%s%s" "$RESET_FG" "$reset_str" "$C_OFF"
  fi
}
seg_cache() { printf "%s" "$cache_str"; }
seg_mr()    { printf "%s" "$mr_str"; }
seg_ci()    { printf "%s" "$ci_str"; }
seg_turn()  { printf "%s" "$turn"; }
# opcode-lite verdict: reads <cwd>/.opcode-status (one line: "<glyph> <OP> <note>").
# Empty/absent → empty segment → skipped, so it only shows in opcode-lite projects.
seg_opcode() {
  local f="$cwd/.opcode-status" line="" color
  [ -r "$f" ] || return 0
  { IFS= read -r line || [ -n "$line" ]; } < "$f"
  [ -z "$line" ] && return 0
  case "$line" in
    "✗"*) color=196 ;;   # fail → red
    "✓"*) color=46  ;;   # pass → green
    *)    color=214 ;;   # other → amber
  esac
  printf "opcode \033[38;5;%dm%s%s" "$color" "$line" "$C_OFF"
}

# ─── Compose final line ─────────────────────────────────────────────────────
# Walk SEGMENTS in order. Empty segments are skipped entirely (so the
# separator never orphans). Turn appends without a leading separator (it
# carries its own leading whitespace), matching the original layout.
out=""
for seg in "${SEGMENTS[@]}"; do
  piece=$("seg_$seg" 2>/dev/null) || continue
  [ -z "$piece" ] && continue
  if [ -z "$out" ]; then
    out="$piece"
  elif [ "$seg" = "turn" ]; then
    out+="$piece"
  else
    out+="${SEP}${piece}"
  fi
done
printf '%s' "$out"
