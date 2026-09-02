#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#                              Author: Paul Newell
#                          Copyright (c) 2026 Paul Newell
# ════════════════════════════════════════════════════════════════════════════
# subagent-statusline.sh — statusline-hud rows for the agent panel.
# Wired in via settings.json `subagentStatusLine`. Claude Code sends every
# visible subagent row as one JSON object on stdin; this prints one
# {"id","content"} line per row, in the same style as statusline-hud.sh:
#   🤖 Explore ⚡Hi ctx:█▏░░░ 12k 0:42 · find remote tests
# It also drops the running-agent count into the shared cache dir so the main
# line's `agents` segment can show 🤖 ×N (the main payload has no task data).
set -u
command -v jq >/dev/null || exit 0
HUD_DEMO=""; [ "${1:-}" = --demo ] && HUD_DEMO=1

# ─── CONFIG ─────────────────────────────────────────────────────────────────
# Same palette as statusline-hud.sh; ~/.claude/statusline-hud.conf overrides
# both scripts, so retheme once.
TIER_COLOR=(46 226 214 196)
BAR_CTX=(30 50 60)
C_BAR_BG=236
C_BAR_EMPTY=240
C_EFFORT_LOW=240
C_EFFORT_MED=250
C_EFFORT_HIGH=220
C_EFFORT_XHIGH=208
C_EFFORT_MAX=196

AGENT_RUN="🤖"           # glyph for a running agent
AGENT_DONE="✓"           # completed (rarely visible: successful rows are removed at once)
AGENT_FAIL="✗"           # failed
AGENT_STOP="■"           # stopped with `x`
C_AGENT_DONE=46
C_AGENT_FAIL=196
C_AGENT_STOP=240
C_AGENT_NAME=39          # agent name
C_AGENT_META=245         # tokens and elapsed time
C_AGENT_DESC=240         # task description, truncated to the row width
AGENT_ELAPSED=1          # 0 hides the elapsed time

MR_CACHE_DIR=/tmp/statusline-hud-$UID   # shared with statusline-hud.sh: the 🤖 ×N count lives here

HUD_CONF=~/.claude/statusline-hud.conf
[ -f "$HUD_CONF" ] && . "$HUD_CONF"
# ─── END CONFIG ─────────────────────────────────────────────────────────────

C_OFF=$'\033[0m'
BG_BAR=$'\033[48;5;'"$C_BAR_BG"'m'
EMPTY_FG=$'\033[38;5;'"$C_BAR_EMPTY"'m'
SCRUB_PAT=$'[\001-\037\177]'

if [ -n "$HUD_DEMO" ]; then
  now_ms=$(( $(date +%s) * 1000 ))
  exec < <(printf '{"session_id":"demo","columns":100,"tasks":[
    {"id":"t1","name":"Explore","status":"running","effort":"high","tokenCount":12400,"contextWindowSize":200000,"startTime":%d,"description":"find where remote host detection is tested"},
    {"id":"t2","name":"code-review","status":"running","effort":"max","tokenCount":96000,"contextWindowSize":200000,"startTime":%d,"description":"review PR #42"},
    {"id":"t3","name":"Plan","status":"failed","tokenCount":3100,"contextWindowSize":200000,"startTime":%d,"description":"draft the migration plan"}]}' \
    $((now_ms - 42000)) $((now_ms - 190000)) $((now_ms - 5000)))
fi

# One jq pass: header line (columns, session id), then one TSV line per task.
# Free-text fields have tabs/newlines squashed so @tsv keeps the columns.
parsed=$(jq -r '
  def clean: (. // "-") | tostring | gsub("[\\t\\n\\r]"; " ");
  ([(.columns // 0), (.session_id | clean)] | @tsv),
  ((.tasks // [])[]? | [
    (.id | clean),
    (.name | clean),
    (.status | clean),
    (.effort | clean),
    ((.tokenCount // 0) | tonumber? // 0 | floor),
    ((.contextWindowSize // 0) | tonumber? // 0 | floor),
    ((.startTime // 0) | tonumber? // 0 | floor),
    (.description | clean)
  ] | @tsv)' 2>/dev/null) || exit 0
[ -z "$parsed" ] && exit 0

{ IFS=$'\t' read -r columns session_id; } <<<"$parsed"
[[ "$columns" =~ ^[0-9]+$ ]] || columns=0
session_id="${session_id//[^A-Za-z0-9._-]/}"

bar() {
  local p="${1:-0}" t1="${2:-60}" t2="${3:-80}" t3="${4:-95}"
  (( p < 0 )) && p=0
  (( p > 100 )) && p=100
  local color=${TIER_COLOR[0]}
  (( p >= t1 )) && color=${TIER_COLOR[1]}
  (( p >= t2 )) && color=${TIER_COLOR[2]}
  (( p >= t3 )) && color=${TIER_COLOR[3]}
  local steps=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█") empty="░░░░░"
  local full=$(( p / 20 )) sub=$(( (p % 20) * 8 / 20 )) fill="" i
  for (( i=0; i<full; i++ )); do fill+="█"; done
  if (( sub > 0 && full < 5 )); then fill+="${steps[$sub]}"; empty="${empty:0:4-full}"
  else empty="${empty:0:5-full}"; fi
  printf '%s\033[38;5;%dm%s%s%s%s' "$BG_BAR" "$color" "$fill" "$EMPTY_FG" "$empty" "$C_OFF"
}

fmt_tokens() {
  if   (( $1 >= 1000000 )); then LC_ALL=C awk -v v="$1" 'BEGIN{printf "%.1fM", v/1000000}'
  elif (( $1 >= 1000 ));    then printf '%dk' $(( $1 / 1000 ))
  else                           printf '%d' "$1"
  fi
}

# startTime is epoch milliseconds; tolerate seconds too.
fmt_elapsed() {
  local start=$1 s
  (( start <= 0 )) && return 0
  (( start > 100000000000 )) && start=$(( start / 1000 ))
  s=$(( $(date +%s) - start ))
  (( s < 0 )) && s=0
  if (( s >= 3600 )); then printf '%dh%02dm' $(( s / 3600 )) $(( s % 3600 / 60 ))
  else printf '%d:%02d' $(( s / 60 )) $(( s % 60 )); fi
}

# Visible width of a string with ANSI SGR sequences stripped. Emoji count as
# two cells, which matters for the 🤖 prefix.
vis_len() {
  local plain; plain=$(printf '%s' "$1" | sed -E $'s/\033\\[[0-9;]*m//g')
  local n=${#plain} wide; wide=$(printf '%s' "$plain" | grep -o "$AGENT_RUN" | wc -l)
  printf '%d' $(( n + wide ))
}

running=0
rows=""
while IFS=$'\t' read -r id name status effort tokens ctx_size start desc; do
  [ -z "$id" ] && continue
  name="${name//$SCRUB_PAT/}" desc="${desc//$SCRUB_PAT/}"
  [ "$desc" = "-" ] && desc=""

  case "$status" in
    running)   glyph="$AGENT_RUN"; running=$(( running + 1 )) ;;
    completed) glyph=$(printf '\033[38;5;%dm%s%s' "$C_AGENT_DONE" "$AGENT_DONE" "$C_OFF") ;;
    failed)    glyph=$(printf '\033[38;5;%dm%s%s' "$C_AGENT_FAIL" "$AGENT_FAIL" "$C_OFF") ;;
    stopped)   glyph=$(printf '\033[38;5;%dm%s%s' "$C_AGENT_STOP" "$AGENT_STOP" "$C_OFF") ;;
    *)         glyph="$AGENT_RUN" ;;
  esac

  badge=""
  case "$effort" in
    low)    badge=$(printf ' \033[38;5;%dm⚡Lo%s'  "$C_EFFORT_LOW"   "$C_OFF") ;;
    medium) badge=$(printf ' \033[38;5;%dm⚡Med%s' "$C_EFFORT_MED"   "$C_OFF") ;;
    high)   badge=$(printf ' \033[38;5;%dm⚡Hi%s'  "$C_EFFORT_HIGH"  "$C_OFF") ;;
    xhigh)  badge=$(printf ' \033[38;5;%dm⚡xHi%s' "$C_EFFORT_XHIGH" "$C_OFF") ;;
    max)    badge=$(printf ' \033[38;5;%dm⚡Max%s' "$C_EFFORT_MAX"   "$C_OFF") ;;
  esac

  ctx=""
  (( ctx_size > 0 )) && ctx=" ctx:$(bar $(( tokens * 100 / ctx_size )) "${BAR_CTX[@]}")"

  meta=$(fmt_tokens "$tokens")
  [ "$AGENT_ELAPSED" = 1 ] && { el=$(fmt_elapsed "$start"); [ -n "$el" ] && meta+=" $el"; }

  content=$(printf '%s \033[38;5;%dm%s%s%s%s \033[38;5;%dm%s%s' \
    "$glyph" "$C_AGENT_NAME" "$name" "$C_OFF" "$badge" "$ctx" "$C_AGENT_META" "$meta" "$C_OFF")

  if [ -n "$desc" ]; then
    room=$(( columns - $(vis_len "$content") - 3 ))
    if (( columns == 0 || ${#desc} <= room )); then
      content+=$(printf ' \033[38;5;%dm· %s%s' "$C_AGENT_DESC" "$desc" "$C_OFF")
    elif (( room > 4 )); then
      content+=$(printf ' \033[38;5;%dm· %s…%s' "$C_AGENT_DESC" "${desc:0:room-1}" "$C_OFF")
    fi
  fi
  rows+="$id"$'\t'"$content"$'\n'
done < <(tail -n +2 <<<"$parsed")

# Running-agent count for the main line's `agents` segment. Written atomically
# and keyed by session so parallel sessions don't see each other's fleet.
if [ -n "$session_id" ] && [ -z "$HUD_DEMO" ]; then
  mkdir -p -m 700 "$MR_CACHE_DIR" 2>/dev/null
  if [ -O "$MR_CACHE_DIR" ]; then
    f="$MR_CACHE_DIR/agents-$session_id"
    printf '%d\n' "$running" > "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null
  fi
fi

[ -n "$rows" ] && printf '%s' "$rows" | jq -Rc 'split("\t") | {id: .[0], content: .[1]}'
exit 0
