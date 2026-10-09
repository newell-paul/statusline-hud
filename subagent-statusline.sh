#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#                              Author: Paul Newell
#                          Copyright (c) 2026 Paul Newell
# ════════════════════════════════════════════════════════════════════════════
# subagent-statusline.sh — statusline-hud rows for the agent panel.
# Wired in via settings.json `subagentStatusLine`. Claude Code sends every
# visible subagent row as one JSON object on stdin; this prints one
# {"id","content"} line per row, in the same style as statusline-hud.sh:
#   🤖 Explore      ⚡Hi  ███▌░  12k  0:42 · find remote tests
# Every column is fixed width so the rows line up under each other.
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
AGENT_RUN_OPUS="🧠"      # per-model glyphs, matched on the task's resolved model id; "" = AGENT_RUN
AGENT_RUN_SONNET=""
AGENT_RUN_HAIKU="🐇"
AGENT_RUN_FABLE="📖"
AGENT_DONE="✓"           # completed (rarely visible: successful rows are removed at once)
AGENT_FAIL="✗"           # failed
AGENT_STOP="■"           # stopped with `x`
C_AGENT_DONE=46
C_AGENT_FAIL=196
C_AGENT_STOP=240
C_AGENT_NAME=39          # agent name
C_AGENT_META=245         # tokens and elapsed time
C_AGENT_DESC=240         # what the agent is doing now (label), else its task description; truncated to the row width
AGENT_ELAPSED=1          # 0 hides the elapsed time
AGENT_NAME_WIDTH=12      # names are padded or cut to this many cells so the columns line up
AGENT_GAUGE=tokens       # the bar: tokens = work so far ███▎░, log scale from GAUGE_FLOOR to GAUGE_FULL tokens, never shrinks
                         # activity = last tick's growth vs the busiest tick · spark ▂▃▅▇ · pulse ● · rate +1.2k
                         # ctx = context fill (tokens / context window) · off
GAUGE_FLOOR=1000         # tokens bar is empty up to here ...
GAUGE_FULL=100000        # ... and full from here
C_GAUGE_BUSY=46          # gauge colour while tokens are still climbing
C_GAUGE_IDLE=240         # ... and when the last reading did not move

MR_CACHE_DIR=/tmp/statusline-hud-$UID   # shared with statusline-hud.sh: the 🤖 ×N count lives here

HUD_CONF=~/.claude/statusline-hud.conf
[ -f "$HUD_CONF" ] && . "$HUD_CONF"
# ─── END CONFIG ─────────────────────────────────────────────────────────────

# Running glyph from the task's resolved model id.
agent_glyph() {
  case "$1" in
    *[Oo]pus*)   printf '%s' "${AGENT_RUN_OPUS:-$AGENT_RUN}" ;;
    *[Ss]onnet*) printf '%s' "${AGENT_RUN_SONNET:-$AGENT_RUN}" ;;
    *[Hh]aiku*)  printf '%s' "${AGENT_RUN_HAIKU:-$AGENT_RUN}" ;;
    *[Ff]able*)  printf '%s' "${AGENT_RUN_FABLE:-$AGENT_RUN}" ;;
    *)           printf '%s' "$AGENT_RUN" ;;
  esac
}

C_OFF=$'\033[0m'
BG_BAR=$'\033[48;5;'"$C_BAR_BG"'m'
EMPTY_FG=$'\033[38;5;'"$C_BAR_EMPTY"'m'
SCRUB_PAT=$'[\001-\037\177]'

if [ -n "$HUD_DEMO" ]; then
  now_ms=$(( $(date +%s) * 1000 ))
  exec < <(printf '{"session_id":"demo","columns":100,"tasks":[
    {"id":"t1","name":"Explore","status":"running","effort":"high","model":"claude-haiku-5-5","tokenCount":12400,"contextWindowSize":200000,"startTime":%d,"tokenSamples":[9800,10100,10300,10900,11200,11800,12000,12400],"description":"find where remote host detection is tested"},
    {"id":"t2","name":"code-review","status":"running","effort":"max","model":"claude-opus-5-5","tokenCount":96000,"contextWindowSize":200000,"startTime":%d,"tokenSamples":[88000,91000,93500,95000,96000,96000,96000,96000],"description":"review PR #42"},
    {"id":"t3","name":"Plan","status":"failed","tokenCount":3100,"contextWindowSize":200000,"startTime":%d,"tokenSamples":[3100,3100],"description":"draft the migration plan"}]}' \
    $((now_ms - 42000)) $((now_ms - 190000)) $((now_ms - 5000)))
fi

# One jq pass: header line (columns, session id), then one TSV line per task.
# Free-text fields have tabs/newlines squashed so @tsv keeps the columns.
parsed=$(jq -r '
  def clean: (. // "-") | tostring | (if . == "" then "-" else . end) | gsub("[\\t\\n\\r]"; " ");
  ([(.columns // 0), (.session_id | clean), (.transcript_path | clean)] | @tsv),
  ((.tasks // [])[]? | [
    (.id | clean),
    (.name | clean),
    (.status | clean),
    (.effort | clean),
    ((.tokenCount // 0) | tonumber? // 0 | floor),
    ((.contextWindowSize // 0) | tonumber? // 0 | floor),
    ((.startTime // 0) | tonumber? // 0 | floor),
    (.model | clean),
    ((.tokenSamples // []) | map(tonumber? // 0 | floor) | join(",") | if . == "" then "-" else . end),
    ((.label | select(. != "")) // .description | clean)
  ] | @tsv)' 2>/dev/null) || exit 0
[ -z "$parsed" ] && exit 0

{ IFS=$'\t' read -r columns session_id transcript_path; } <<<"$parsed"
# The payload carries no agent type, but Claude Code writes one next to the
# session transcript: <transcript>/subagents/agent-<id>.meta.json → agentType.
meta_dir=""
[ "$transcript_path" != "-" ] && meta_dir="${transcript_path%.jsonl}/subagents"
[[ "$columns" =~ ^[0-9]+$ ]] || columns=0
session_id="${session_id//[^A-Za-z0-9._-]/}"

bar() {
  local p="${1:-0}" t1="${2:-60}" t2="${3:-80}" t3="${4:-95}"
  (( p < 0 )) && p=0
  (( p > 100 )) && p=100
  local color=${5:-}
  if [ -z "$color" ]; then
    color=${TIER_COLOR[0]}
    (( p >= t1 )) && color=${TIER_COLOR[1]}
    (( p >= t2 )) && color=${TIER_COLOR[2]}
    (( p >= t3 )) && color=${TIER_COLOR[3]}
  fi
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

# Gauge column, fixed width so rows line up. `tokens` is the running total on
# a log scale; the rest read tokenSamples, the last 16 counts one per refresh
# tick, oldest first, scaling each tick's growth against the busiest tick in
# the window. A zero delta on the latest tick means the agent is waiting.
gauge() {
  local style=$1 s d=() n prev=-1 max=0 last=0 out="" color i
  if [ "$style" = tokens ]; then
    bar "$(LC_ALL=C awk -v t="$3" -v lo="$GAUGE_FLOOR" -v hi="$GAUGE_FULL" 'BEGIN {
      p = (lo > 0 && t > lo && hi > lo) ? 100 * log(t / lo) / log(hi / lo) : 0; printf "%d", (p > 100 ? 100 : p) }')" 0 0 0 "$C_GAUGE_BUSY"
    return 0
  fi
  IFS=, read -r -a s <<<"$2"
  for n in "${s[@]}"; do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    if (( prev >= 0 )); then
      last=$(( n > prev ? n - prev : 0 )); d+=("$last"); (( last > max )) && max=$last
    fi
    prev=$n
  done
  color=$C_GAUGE_BUSY; (( last == 0 )) && color=$C_GAUGE_IDLE
  (( max == 0 )) && max=1   # bash 3.2 evaluates both arms of ?: so never divide by zero
  case "$style" in
    activity) bar $(( last * 100 / max )) 0 0 0 "$C_GAUGE_BUSY"; return 0 ;;
    spark) local lv=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
           for (( i=${#d[@]}; i<8; i++ )); do out+=▁; done
           for (( i=${#d[@]} > 8 ? ${#d[@]} - 8 : 0; i<${#d[@]}; i++ )); do out+=${lv[$(( d[i] * 7 / max ))]}; done ;;
    pulse) (( last > 0 )) && out=● || out=○ ;;
    rate)  out=$(printf '%5s' "+$(fmt_tokens "$last")") ;;
    *)     return 0 ;;
  esac
  printf '\033[38;5;%dm%s%s' "$color" "$out" "$C_OFF"
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

# Visible width of a string with ANSI SGR sequences stripped. Emoji (4-byte
# UTF-8, lead byte 0xF0–0xF7) count as two cells, which matters for the glyph.
vis_len() {
  local plain; plain=$(printf '%s' "$1" | sed -E $'s/\033\\[[0-9;]*m//g')
  local n=${#plain} wide; wide=$(printf '%s' "$plain" | LC_ALL=C tr -cd '\360-\367' | wc -c)
  printf '%d' $(( n + wide ))
}

running=0
rows=""
while IFS=$'\t' read -r id name status effort tokens ctx_size start model samples desc; do
  [ -z "$id" ] && continue
  name="${name//$SCRUB_PAT/}" desc="${desc//$SCRUB_PAT/}"
  [ "$desc" = "-" ] && desc=""
  [ "$name" = "-" ] && name=""
  if [ -z "$name" ] && [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "$meta_dir/agent-$id.meta.json" ]; then
    name=$(jq -r '.agentType // empty' "$meta_dir/agent-$id.meta.json" 2>/dev/null)
    name="${name//$SCRUB_PAT/}"
  fi

  glyph=$(agent_glyph "$model")
  case "$status" in
    running)   running=$(( running + 1 )) ;;
    completed) glyph=$(printf '\033[38;5;%dm%s%s ' "$C_AGENT_DONE" "$AGENT_DONE" "$C_OFF") ;;
    failed)    glyph=$(printf '\033[38;5;%dm%s%s ' "$C_AGENT_FAIL" "$AGENT_FAIL" "$C_OFF") ;;
    stopped)   glyph=$(printf '\033[38;5;%dm%s%s ' "$C_AGENT_STOP" "$AGENT_STOP" "$C_OFF") ;;
  esac

  # Fixed columns: name, effort badge (⚡ is two cells), gauge, tokens, elapsed.
  (( ${#name} > AGENT_NAME_WIDTH )) && name="${name:0:AGENT_NAME_WIDTH-1}…"
  name_part=$(printf '\033[38;5;%dm%s%*s%s' "$C_AGENT_NAME" "$name" $(( AGENT_NAME_WIDTH - ${#name} )) '' "$C_OFF")

  badge="     "
  case "$effort" in
    low)    badge=$(printf '\033[38;5;%dm⚡Lo %s' "$C_EFFORT_LOW"   "$C_OFF") ;;
    medium) badge=$(printf '\033[38;5;%dm⚡Med%s' "$C_EFFORT_MED"   "$C_OFF") ;;
    high)   badge=$(printf '\033[38;5;%dm⚡Hi %s' "$C_EFFORT_HIGH"  "$C_OFF") ;;
    xhigh)  badge=$(printf '\033[38;5;%dm⚡xHi%s' "$C_EFFORT_XHIGH" "$C_OFF") ;;
    max)    badge=$(printf '\033[38;5;%dm⚡Max%s' "$C_EFFORT_MAX"   "$C_OFF") ;;
  esac

  if [ "$AGENT_GAUGE" = ctx ]; then
    pct=0; (( ctx_size > 0 )) && pct=$(( tokens * 100 / ctx_size ))
    gauge=$(bar "$pct" "${BAR_CTX[@]}")
  else
    gauge=$(gauge "$AGENT_GAUGE" "$samples" "$tokens")
  fi
  [ -n "$gauge" ] && gauge=" $gauge"

  meta=$(printf '%4s' "$(fmt_tokens "$tokens")")
  [ "$AGENT_ELAPSED" = 1 ] && meta+=$(printf ' %5s' "$(fmt_elapsed "$start")")

  content=$(printf '%s %s %s%s \033[38;5;%dm%s%s' \
    "$glyph" "$name_part" "$badge" "$gauge" "$C_AGENT_META" "$meta" "$C_OFF")

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
