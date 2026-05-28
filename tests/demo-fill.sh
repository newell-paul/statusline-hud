#!/usr/bin/env bash
# Animate the statusline meters filling from 0 to 100% on a single line.
# Usage:  ./tests/demo-fill.sh [step] [delay]
#   step:  percent increment per frame (default 2)
#   delay: seconds between frames (default 0.05)
#
# A full statusline is ~140 visible chars. On narrower terminals the line
# wraps, leaving debris above the cursor on each frame. We disable line wrap
# (DECAWM \033[?7l) for the duration of the demo so the terminal truncates
# rather than wraps — the right edge of the line just gets cut off, but \r
# correctly returns to col 0 and \033[2K clears the whole row in one go.
set -u
step=${1:-2}
delay=${2:-0.05}
script="$(cd "$(dirname "$0")/.." && pwd)/statusline-hud.sh"

# Hide cursor + disable line wrap. Restore both on exit (incl. Ctrl-C).
printf '\033[?25l\033[?7l'
trap 'printf "\033[?25h\033[?7h\n"' EXIT INT TERM

for ((p=0; p<=100; p+=step)); do
  payload=$(printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus 4.7 (1M context)"},"effort":{"level":"medium"},"context_window":{"used_percentage":%d,"total_input_tokens":30000,"current_usage":{"cache_read_input_tokens":28000}},"cost":{"total_cost_usd":0.5,"total_duration_ms":600000},"rate_limits":{"five_hour":{"used_percentage":%d,"resets_at":0},"seven_day":{"used_percentage":%d,"resets_at":0}}}' \
    "$PWD" "$p" "$p" "$p")
  line=$(printf '%s' "$payload" | "$script")
  printf '\r\033[2K%s  (%d%%)' "$line" "$p"
  sleep "$delay"
done
