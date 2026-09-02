#!/usr/bin/env bash
# Test helpers for statusline-hud.bats
#
# Design note: the production script has NO env-var knobs — TURN_UNIT is a
# plain in-script assignment. To exercise both unit modes, run_hud builds a
# patched copy of the script per test. Tests set TURN_UNIT as a local shell
# var before calling run_hud; the helper sees it and rewrites the assignment
# in the patched copy.

SCRIPT="${BATS_TEST_DIRNAME}/../statusline-hud.sh"

# Run the statusline with the given JSON on stdin. Returns via bats' `run`
# so $status and $output are populated.
# Usage: run_hud '<json>'
# Optional local the caller can set before invoking:
#   TURN_UNIT    = usd | tokens
# The turn and cache segments are re-enabled in the patched copy regardless of
# whether they are commented out in SEGMENTS, so their bats files always
# exercise them.
#   MR_CACHE_DIR = directory for the mr segment's glab cache (isolates tests)
#   MR_TTL       = seconds before a cached MR lookup is considered stale
#   C_MR_LINK    = link colour for the MR ref ("" = inherit state colour)
#   MR_LINK_STYLE = SGR for a linked ref (tests default to 4, underline)
#   MR_PREFIX_GITLAB = text before a GitLab MR number (tests default to "!")
#   MR_PREFIX_GITHUB = text before a GitHub PR number (tests default to "🐙 #")
#   HUD_ARGS     = extra argv for the script (e.g. --demo)
#   HUD_CONF     = overrides file to source (tests default to a missing path so
#                  the developer's real ~/.claude/statusline-hud.conf is ignored)
run_hud() {
  local patched
  patched=$(mktemp)
  sed -e "s|^TURN_UNIT=.*|TURN_UNIT=${TURN_UNIT:-usd}|" \
      -e "s|^MR_CACHE_DIR=.*|MR_CACHE_DIR=${MR_CACHE_DIR:-/tmp/statusline-hud-test-\$\$}|" \
      -e "s|^MR_TTL=.*|MR_TTL=${MR_TTL:-60}|" \
      -e "s|^C_MR_LINK=.*|C_MR_LINK=${C_MR_LINK-39}|" \
      -e "s|^MR_LINK_STYLE=.*|MR_LINK_STYLE=${MR_LINK_STYLE-4}|" \
      -e "s|^  # turn  |  turn  |" \
      -e "s|^  # cache  |  cache  |" \
      -e "s|^  # session  |  session  |" \
      -e "s|^  # worktree  |  worktree  |" \
      -e "s|^MR_PREFIX_GITLAB=.*|MR_PREFIX_GITLAB=\"${MR_PREFIX_GITLAB-!}\"|" \
      -e "s|^MR_PREFIX_GITHUB=.*|MR_PREFIX_GITHUB=\"${MR_PREFIX_GITHUB-🐙 #}\"|" \
      -e "s|^HUD_CONF=.*|HUD_CONF=${HUD_CONF:-/nonexistent/statusline-hud.conf}|" \
    "$SCRIPT" > "$patched"
  run bash "$patched" ${HUD_ARGS:-} <<<"$1"
  rm -f "$patched"
}

# Create a throwaway git repo and echo its path. Caller is responsible
# for `rm -rf` (or rely on TMPDIR cleanup).
make_clean_repo() {
  local d
  d=$(mktemp -d)
  ( cd "$d" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init ) >/dev/null
  printf '%s' "$d"
}

# Strip ANSI escape sequences for easier substring assertions.
strip_ansi() {
  printf '%s' "$1" | sed -E $'s/\033\\[[0-9;]*m//g'
}

# Assert output contains a specific ANSI color code applied somewhere.
# $1 = output, $2 = color code (e.g. 196), $3 = description
assert_color() {
  [[ "$1" == *$'\033[38;5;'"$2"'m'* ]] || {
    echo "expected color $2 ($3) in output"
    echo "got: $1"
    return 1
  }
}

assert_no_color() {
  [[ "$1" != *$'\033[38;5;'"$2"'m'* ]] || {
    echo "unexpected color $2 ($3) in output"
    echo "got: $1"
    return 1
  }
}

# Build a JSON payload from key=value overrides on top of a sane default.
# Usage: make_json model="Opus 4.7" effort=high used=25 over200k=true
make_json() {
  local cwd="/tmp"  # non-repo by default so tests don't pick up host git state
  local model="Opus 4.7"
  local effort=""
  local fast=false
  local used=10
  local rl5=5
  local rl7=8
  local rl5_reset=0
  local rl7_reset=0
  local cache_read=0
  local total_input=0
  local cost=0.1
  local pc_ratio=""
  local pc_warm=""
  local pr_number="" pr_url="" pr_state="" pr_kind=""
  local thinking="" lines_add="" lines_del="" pc_expires=""
  local dur="" session="" worktree="" repo_host="" session_id=""

  for kv in "$@"; do
    local k="${kv%%=*}" v="${kv#*=}"
    case "$k" in
      cwd) cwd="$v" ;;
      model) model="$v" ;;
      effort) effort="$v" ;;
      fast) fast="$v" ;;
      used) used="$v" ;;
      rl5) rl5="$v" ;;
      rl7) rl7="$v" ;;
      rl5_reset) rl5_reset="$v" ;;
      rl7_reset) rl7_reset="$v" ;;
      cache_read) cache_read="$v" ;;
      total_input) total_input="$v" ;;
      cost) cost="$v" ;;
      pc_ratio) pc_ratio="$v" ;;
      pc_warm) pc_warm="$v" ;;
      pr_number) pr_number="$v" ;;
      pr_url) pr_url="$v" ;;
      pr_state) pr_state="$v" ;;
      pr_kind) pr_kind="$v" ;;
      thinking) thinking="$v" ;;
      lines_add) lines_add="$v" ;;
      lines_del) lines_del="$v" ;;
      pc_expires) pc_expires="$v" ;;
      dur) dur="$v" ;;
      session) session="$v" ;;
      worktree) worktree="$v" ;;
      repo_host) repo_host="$v" ;;
      session_id) session_id="$v" ;;
    esac
  done

  local effort_json="null"
  [ -n "$effort" ] && effort_json="{\"level\":\"$effort\"}"
  local pc_json=""
  if [ -n "$pc_ratio" ] || [ -n "$pc_warm" ]; then
    pc_json=",\"prompt_cache\": {\"hit_ratio\": ${pc_ratio:-null}, \"warm\": ${pc_warm:-null}, \"ttl\": \"1h\", \"expires_at\": ${pc_expires:-null}}"
  fi
  local think_json="" lines_json=""
  [ -n "$thinking" ] && think_json=",\"thinking\": {\"enabled\": $thinking}"
  [ -n "$lines_add$lines_del" ] && lines_json=", \"total_lines_added\": ${lines_add:-0}, \"total_lines_removed\": ${lines_del:-0}"
  [ -n "$dur" ] && lines_json+=", \"total_duration_ms\": $dur"
  local extra_json=""
  [ -n "$session" ] && extra_json+=",\"session_name\": \"$session\""
  [ -n "$session_id" ] && extra_json+=",\"session_id\": \"$session_id\""
  [ -n "$worktree" ] && extra_json+=",\"worktree\": {\"name\": \"$worktree\"}"
  [ -n "$repo_host" ] && extra_json+=",\"workspace\": {\"current_dir\": \"$cwd\", \"repo\": {\"host\": \"$repo_host\"}}"

  local pr_json=""
  if [ -n "$pr_number" ]; then
    pr_json=",\"pr\": {\"number\": $pr_number"
    [ -n "$pr_url" ]   && pr_json+=", \"url\": \"$pr_url\""
    [ -n "$pr_state" ] && pr_json+=", \"review_state\": \"$pr_state\""
    [ -n "$pr_kind" ]  && pr_json+=", \"kind\": \"$pr_kind\""
    pr_json+="}"
  fi

  cat <<EOF
{
  "cwd": "$cwd",
  "model": {"display_name": "$model"},
  "effort": $effort_json,
  "fast_mode": $fast,
  "context_window": {
    "used_percentage": $used,
    "total_input_tokens": $total_input,
    "current_usage": {"cache_read_input_tokens": $cache_read}
  },
  "cost": {"total_cost_usd": $cost$lines_json},
  "rate_limits": {
    "five_hour": {"used_percentage": $rl5, "resets_at": $rl5_reset},
    "seven_day": {"used_percentage": $rl7, "resets_at": $rl7_reset}
  }$pc_json$pr_json$think_json$extra_json
}
EOF
}
