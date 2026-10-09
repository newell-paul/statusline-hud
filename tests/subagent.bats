#!/usr/bin/env bats
# subagent-statusline.sh: rows for the agent panel, plus the running-count
# file the main line's `agents` segment reads.
load helpers

SUB="${BATS_TEST_DIRNAME}/../subagent-statusline.sh"

setup() {
  export MR_CACHE_DIR=$(mktemp -d)
  export HUD_CONF=/nonexistent/statusline-hud.conf
}
teardown() { rm -rf "$MR_CACHE_DIR"; }

# Patch the CONFIG assignments the same way run_hud does for the main script.
run_sub() {
  local patched; patched=$(mktemp)
  sed -e "s|^MR_CACHE_DIR=.*|MR_CACHE_DIR=$MR_CACHE_DIR|" \
      -e "s|^HUD_CONF=.*|HUD_CONF=$HUD_CONF|" "$SUB" > "$patched"
  run bash "$patched" ${SUB_ARGS:-} <<<"$1"
  rm -f "$patched"
}

task_json() {  # id name status effort tokens ctxsize desc
  printf '{"id":"%s","name":"%s","status":"%s","effort":"%s","tokenCount":%d,"contextWindowSize":%d,"startTime":%d,"description":"%s"}' \
    "$1" "$2" "$3" "$4" "$5" "$6" $(( ($(date +%s) - 42) * 1000 )) "$7"
}
payload() { printf '{"session_id":"sess-1","columns":120,"tasks":[%s]}' "$1"; }

@test "renders one JSON line per task with id and content" {
  run_sub "$(payload "$(task_json t1 Explore running high 12400 200000 'find tests'),$(task_json t2 Plan running low 500 200000 'plan')")"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 2 ]
  [ "$(printf '%s\n' "$output" | jq -r .id | paste -sd, -)" = "t1,t2" ]
  printf '%s\n' "$output" | jq -e 'has("content")' >/dev/null
}

@test "row mirrors the HUD: robot, name, effort badge, tokens bar, tokens, elapsed, description" {
  run_sub "$(payload "$(task_json t1 Explore running high 12400 200000 'find remote tests')")"
  local plain; plain=$(strip_ansi "$(printf '%s' "$output" | jq -r .content)")
  [[ "$plain" == "🤖 Explore      ⚡Hi  ██▋░░  12k  0:4"*"· find remote tests" ]]
  [[ "$(printf '%s' "$output" | jq -r .content)" == *$'\033[38;5;220m⚡Hi'* ]]
}

@test "every column is fixed width so the description starts at the same cell on every row" {
  run_sub "$(payload "$(task_json t1 Explore running high 12400 200000 'one'),$(task_json t2 code-review running max 96000 200000 'two'),$(task_json t3 a-very-long-agent-name running '' 5 1 'three'),$(task_json t4 x running low 1234567 1 'four')")"
  local cols; cols=$(printf '%s\n' "$output" | jq -r .content | while read -r row; do
    plain=$(strip_ansi "$row"); head=${plain%%·*}; head=${head//⚡/xx}; printf '%s\n' "${#head}"; done | sort -u | wc -l | tr -d ' ')   # ⚡ is two cells
  [ "$cols" = 1 ]
  [[ "$(strip_ansi "$(printf '%s\n' "$output" | sed -n 3p | jq -r .content)")" == "🤖 a-very-long…       "* ]]
  [[ "$(strip_ansi "$(printf '%s\n' "$output" | sed -n 4p | jq -r .content)")" == *"⚡Lo  █████ 1.2M  0:4"* ]]
  run_sub "$(payload "$(task_json t1 Plan failed '' 3100 1 'x')")"
  [[ "$(strip_ansi "$(printf '%s' "$output" | jq -r .content)")" == "✗  Plan               █▏░░░   3k  0:4"* ]]
}

gauge_json() {  # samples [tokens]
  printf '{"session_id":"s","columns":80,"tasks":[{"id":"t1","name":"a","status":"running","tokenCount":%d,"tokenSamples":[%s]}]}' "${2:-500}" "$1"
}
gauge_plain() { strip_ansi "$(printf '%s' "$output" | jq -r .content)"; }

@test "tokens bar: work so far on a log scale, empty at GAUGE_FLOOR, full at GAUGE_FULL, never shrinks" {
  run_sub "$(gauge_json 0 500)";    [[ "$(gauge_plain)" == *" ░░░░░  500"* ]]
  run_sub "$(gauge_json 0 1000)";   [[ "$(gauge_plain)" == *" ░░░░░   1k"* ]]
  run_sub "$(gauge_json 0 10000)";  [[ "$(gauge_plain)" == *" ██▌░░  10k"* ]] && [[ "$output" == *"38;5;46m██▌"* ]]
  run_sub "$(gauge_json 0 100000)"; [[ "$(gauge_plain)" == *" █████ 100k"* ]]
  run_sub "$(gauge_json 0 900000)"; [[ "$(gauge_plain)" == *" █████ 900k"* ]]
  HUD_CONF=$(mktemp); printf 'GAUGE_FLOOR=0\nGAUGE_FULL=1000\n' > "$HUD_CONF"
  run_sub "$(gauge_json 0 500)";    [[ "$(gauge_plain)" == *" ░░░░░  500"* ]]   # floor 0 disables the scale
  printf 'GAUGE_FLOOR=100\nGAUGE_FULL=10000\n' > "$HUD_CONF"
  run_sub "$(gauge_json 0 1000)";   [[ "$(gauge_plain)" == *" ██▌░░   1k"* ]]
  rm -f "$HUD_CONF"
}

@test "activity bar: last tick's growth against the busiest tick in the window, empty while waiting or before any tick" {
  HUD_CONF=$(mktemp); echo 'AGENT_GAUGE=activity' > "$HUD_CONF"
  run_sub "$(gauge_json 0,100,300)"            # last 200 = busiest → full
  [[ "$(gauge_plain)" == "🤖 a                  █████  500"* ]]
  [[ "$output" == *"38;5;46m█████"* ]]
  run_sub "$(gauge_json 0,100,150)"            # 50 of 100 → half
  [[ "$(gauge_plain)" == *" ██▌░░  500"* ]]
  run_sub "$(gauge_json 0,100,100)"            # no growth on the last tick
  [[ "$(gauge_plain)" == *" ░░░░░  500"* ]]
  run_sub "$(gauge_json 500)"
  [[ "$(gauge_plain)" == *" ░░░░░  500"* ]]
  run_sub '{"session_id":"s","columns":80,"tasks":[{"id":"t1","name":"a","status":"running","tokenCount":500}]}'
  [[ "$(gauge_plain)" == *" ░░░░░  500"* ]]
  run_sub "$(gauge_json 900,100,300)"          # a falling count resets the baseline
  [[ "$(gauge_plain)" == *" █████  500"* ]]
  rm -f "$HUD_CONF"
}

@test "spark, pulse and rate gauges from the conf; ctx is the context bar; off hides the column" {
  HUD_CONF=$(mktemp)
  echo 'AGENT_GAUGE=spark' > "$HUD_CONF"; run_sub "$(gauge_json 0,100,200,400,800,800)"   # deltas 100 100 200 400 0, padded to 8
  [[ "$(gauge_plain)" == *" ▁▁▁▂▂▄█▁  500"* ]] && [[ "$output" == *"38;5;240m▁▁▁▂▂▄█▁"* ]]
  run_sub "$(gauge_json 0,1,2,3,4,5,6,7,8,9,10,11)"                                   # 11 deltas → last 8
  [[ "$(gauge_plain)" == *" ████████  500"* ]] && [[ "$output" == *"38;5;46m████████"* ]]
  echo 'AGENT_GAUGE=pulse' > "$HUD_CONF"; run_sub "$(gauge_json 0,5)"
  [[ "$(gauge_plain)" == *" ●  500"* ]]
  run_sub "$(gauge_json 5,5)"
  [[ "$(gauge_plain)" == *" ○  500"* ]] && [[ "$output" == *"38;5;240m○"* ]]
  echo 'AGENT_GAUGE=rate' > "$HUD_CONF"; run_sub "$(gauge_json 1000,3500)"
  [[ "$(gauge_plain)" == *"   +2k  500"* ]]
  echo 'AGENT_GAUGE=ctx' > "$HUD_CONF"
  run_sub "$(payload "$(task_json t1 a running max 96000 200000 x)")"   # 48% → yellow
  [[ "$output" == *"38;5;226m██▍"* ]]
  run_sub "$(payload "$(task_json t1 a running max 130000 200000 x)")"  # 65% → red
  [[ "$output" == *"38;5;196m███"* ]]
  run_sub '{"session_id":"s","columns":80,"tasks":[{"id":"t1","name":"a","status":"running","tokenCount":500}]}'
  [[ "$(gauge_plain)" == *" ░░░░░  500"* ]]
  echo 'AGENT_GAUGE=off' > "$HUD_CONF"; run_sub "$(gauge_json 0,5,9)"
  [[ "$(gauge_plain)" == "🤖 a "*"  500"* ]] && [[ "$(gauge_plain)" != *"░"* ]]
  rm -f "$HUD_CONF"
}

@test "status glyphs: failed ✗ red, stopped ■ grey, completed ✓ green" {
  run_sub "$(payload "$(task_json t1 a failed high 1 1 x),$(task_json t2 b stopped high 1 1 x),$(task_json t3 c completed high 1 1 x)")"
  [[ "$output" == *'38;5;196m✗'* ]]
  [[ "$output" == *'38;5;240m■'* ]]
  [[ "$output" == *'38;5;46m✓'* ]]
}

@test "description is truncated with an ellipsis to fit columns" {
  run_sub '{"session_id":"s","columns":60,"tasks":[{"id":"t1","name":"Explore","status":"running","tokenCount":500,"description":"a very long description that should be truncated to fit"}]}'
  local plain; plain=$(strip_ansi "$(printf '%s' "$output" | jq -r .content)")
  [[ "$plain" == *"…" ]]
  [ "${#plain}" -le 60 ]
}

@test "description is dropped when there is no room, never wrapped" {
  run_sub '{"session_id":"s","columns":14,"tasks":[{"id":"t1","name":"Explore","status":"running","tokenCount":500,"description":"long long long"}]}'
  [[ "$output" != *"·"* ]]
}

@test "tabs, newlines and control bytes in names and descriptions are squashed" {
  run_sub "$(printf '{"session_id":"s","columns":0,"tasks":[{"id":"t1","name":"Ex\\tplore\\u001b[2J","status":"running","tokenCount":5,"description":"line1\\nline2"}]}')"
  [ "$status" -eq 0 ]
  local plain; plain=$(strip_ansi "$(printf '%s' "$output" | jq -r .content)")
  [[ "$plain" == "🤖 Ex plore"*"· line1 line2" ]]
  [[ "$plain" != *$'\033[2J'* ]]
}

@test "writes the running count for the session, ignoring finished rows" {
  run_sub "$(payload "$(task_json t1 a running high 1 1 x),$(task_json t2 b failed high 1 1 x),$(task_json t3 c running high 1 1 x)")"
  [ "$(cat "$MR_CACHE_DIR/agents-sess-1")" = 2 ]
}

@test "an empty task list writes 0 so the main line clears" {
  run_sub "$(payload "$(task_json t1 a running high 1 1 x)")"
  run_sub '{"session_id":"sess-1","columns":80,"tasks":[]}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$MR_CACHE_DIR/agents-sess-1")" = 0 ]
}

@test "session id is sanitised before it becomes a filename" {
  run_sub '{"session_id":"../evil/x","columns":80,"tasks":[{"id":"t1","name":"a","status":"running"}]}'
  [ -f "$MR_CACHE_DIR/agents-..evilx" ]
  [ ! -e "$MR_CACHE_DIR/../evil" ]
}

@test "malformed input exits 0 with no output" {
  run_sub 'not json'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run_sub ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "conf overrides the palette for rows too" {
  HUD_CONF=$(mktemp); echo 'C_AGENT_NAME=99; AGENT_RUN="🦾"' > "$HUD_CONF"
  run_sub "$(payload "$(task_json t1 Explore running high 1 1 x)")"
  [[ "$(printf '%s' "$output" | jq -r .content)" == *'🦾 '$'\033[38;5;99mExplore'* ]]
  rm -f "$HUD_CONF"
}

@test "a regex-metachar AGENT_RUN glyph is counted literally, not as a pattern" {
  HUD_CONF=$(mktemp); echo 'AGENT_RUN="."' > "$HUD_CONF"
  # Content before the description is ~30 columns; a 60-char description fits
  # the real room (87) but not the room a doubled width leaves (57).
  local desc; desc=$(printf 'x%.0s' $(seq 60))
  run_sub "$(payload "$(task_json t1 Explore running high 1 1 "$desc")")"
  [ "$status" -eq 0 ]
  content=$(printf '%s' "$output" | jq -r .content)
  echo "$content"
  [ "$(printf '%s' "$content" | grep -cF '. ')" = 1 ]
  [ "$(printf '%s' "$content" | grep -cF '…')" = 0 ]
  rm -f "$HUD_CONF"
}

@test "--demo renders three rows and writes no count file" {
  SUB_ARGS=--demo run_sub ''
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 3 ]
  [[ "$output" == *"🐇"*"Explore"* ]] && [[ "$output" == *"🧠"*"code-review"* ]]
  [ -z "$(ls -A "$MR_CACHE_DIR")" ]
}

@test "name slot is omitted when Claude Code sends no name (typed agents send only type=local_agent)" {
  run_sub '{"session_id":"s","columns":80,"tasks":[{"id":"t1","type":"local_agent","status":"running","tokenCount":500,"label":"Checking tests","description":"run the suite"}]}'
  [ "$status" -eq 0 ]
  c=$(printf '%s' "$output" | jq -r .content)
  [[ "$c" != *" - "* ]]
  [[ "$c" != *local_agent* ]]
  [[ "$c" == *"Checking tests"* ]]
}

@test "missing name is filled from the agentType in the subagent meta file" {
  local tp="$MR_CACHE_DIR/sess.jsonl"
  mkdir -p "$MR_CACHE_DIR/sess/subagents"
  printf '{"agentType":"test-runner","description":"Run the bats test suite"}' > "$MR_CACHE_DIR/sess/subagents/agent-t1.meta.json"
  run_sub "{\"session_id\":\"s\",\"columns\":80,\"transcript_path\":\"$tp\",\"tasks\":[{\"id\":\"t1\",\"type\":\"local_agent\",\"status\":\"running\",\"tokenCount\":500,\"description\":\"run the suite\"},{\"id\":\"t2\",\"type\":\"local_agent\",\"status\":\"running\",\"tokenCount\":500,\"description\":\"no meta\"}]}"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | sed -n 1p | jq -r .content)" == *"🤖 "*"test-runner"* ]]
  [[ "$(printf '%s\n' "$output" | sed -n 2p | jq -r .content)" != *" - "* ]]
}

@test "row shows the live label when present, else the task description" {
  run_sub '{"session_id":"s","columns":80,"tasks":[{"id":"t1","name":"a","status":"running","tokenCount":1,"label":"Reading tests/mr.bats","description":"run the suite"}]}'
  [[ "$(printf '%s' "$output" | jq -r .content)" == *"Reading tests/mr.bats"* ]]
  run_sub '{"session_id":"s","columns":80,"tasks":[{"id":"t1","name":"a","status":"running","tokenCount":1,"label":"","description":"run the suite"}]}'
  [[ "$(printf '%s' "$output" | jq -r .content)" == *"run the suite"* ]]
}

@test "running glyph follows the task's resolved model: Opus 🧠, Haiku 🐇, Fable 📖, Sonnet and unknown 🤖" {
  run_sub '{"session_id":"s","columns":80,"tasks":[
    {"id":"t1","name":"a","status":"running","model":"claude-opus-5-5","tokenCount":1},
    {"id":"t2","name":"b","status":"running","model":"claude-haiku-5-5","tokenCount":1},
    {"id":"t3","name":"c","status":"running","model":"claude-sonnet-5-5","tokenCount":1},
    {"id":"t4","name":"d","status":"running","tokenCount":1},
    {"id":"t5","name":"e","status":"running","model":"claude-fable-5-1","tokenCount":1}]}'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r .content | cut -c1 | paste -sd, -)" = "🧠,🐇,🤖,🤖,📖" ]
}

@test "per-model glyphs come from the conf; an empty one falls back to AGENT_RUN" {
  HUD_CONF=$(mktemp); printf 'AGENT_RUN="🦾"\nAGENT_RUN_OPUS="🦉"\nAGENT_RUN_HAIKU=""\n' > "$HUD_CONF"
  run_sub '{"session_id":"s","columns":80,"tasks":[
    {"id":"t1","name":"a","status":"running","model":"claude-opus-5-5","tokenCount":1},
    {"id":"t2","name":"b","status":"running","model":"claude-haiku-5-5","tokenCount":1}]}'
  [ "$(printf '%s\n' "$output" | jq -r .content | cut -c1 | paste -sd, -)" = "🦉,🦾" ]
  rm -f "$HUD_CONF"
}

@test "any emoji glyph is counted as two cells when fitting the description" {
  # Content before the description is 42 columns with the glyph counted
  # twice; a 59-char description fits only if it is counted once.
  HUD_CONF=$(mktemp); echo 'AGENT_RUN_OPUS="🦉"' > "$HUD_CONF"
  local desc; desc=$(printf 'x%.0s' $(seq 59))
  run_sub '{"session_id":"s","columns":103,"tasks":[{"id":"t1","name":"Explore","status":"running","effort":"high","model":"claude-opus-5-5","tokenCount":1,"startTime":1,"description":"'"$desc"'"}]}'
  content=$(printf '%s' "$output" | jq -r .content)
  echo "$content"
  [ "$(printf '%s' "$content" | grep -cF '…')" = 1 ]
  rm -f "$HUD_CONF"
}
