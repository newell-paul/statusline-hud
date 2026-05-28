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
#   TURN_UNIT = usd | tokens
run_hud() {
  local patched
  patched=$(mktemp)
  sed -e "s|^TURN_UNIT=.*|TURN_UNIT=${TURN_UNIT:-usd}|" \
    "$SCRIPT" > "$patched"
  run bash "$patched" <<<"$1"
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
    esac
  done

  local effort_json="null"
  [ -n "$effort" ] && effort_json="{\"level\":\"$effort\"}"

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
  "cost": {"total_cost_usd": $cost},
  "rate_limits": {
    "five_hour": {"used_percentage": $rl5, "resets_at": $rl5_reset},
    "seven_day": {"used_percentage": $rl7, "resets_at": $rl7_reset}
  }
}
EOF
}
