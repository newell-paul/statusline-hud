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

@test "row mirrors the HUD: robot, name, effort badge, ctx bar, tokens, elapsed, description" {
  run_sub "$(payload "$(task_json t1 Explore running high 12400 200000 'find remote tests')")"
  local plain; plain=$(strip_ansi "$(printf '%s' "$output" | jq -r .content)")
  [[ "$plain" == "🤖 Explore ⚡Hi ctx:"*"12k 0:4"*"· find remote tests" ]]
  [[ "$(printf '%s' "$output" | jq -r .content)" == *$'\033[38;5;220m⚡Hi'* ]]
}

@test "ctx bar takes its tier colour from tokenCount / contextWindowSize" {
  run_sub "$(payload "$(task_json t1 a running max 96000 200000 x)")"   # 48% → yellow
  [[ "$output" == *"38;5;226m██▍"* ]]
  run_sub "$(payload "$(task_json t1 a running max 130000 200000 x)")"  # 65% → red
  [[ "$output" == *"38;5;196m███"* ]]
}

@test "no ctx bar when contextWindowSize is absent" {
  run_sub '{"session_id":"s","columns":80,"tasks":[{"id":"t1","name":"a","status":"running","tokenCount":500}]}'
  [[ "$output" != *"ctx:"* ]]
  [[ "$(strip_ansi "$(printf '%s' "$output" | jq -r .content)")" == "🤖 a 500" ]]
}

@test "status glyphs: failed ✗ red, stopped ■ grey, completed ✓ green" {
  run_sub "$(payload "$(task_json t1 a failed high 1 1 x),$(task_json t2 b stopped high 1 1 x),$(task_json t3 c completed high 1 1 x)")"
  [[ "$output" == *'38;5;196m✗'* ]]
  [[ "$output" == *'38;5;240m■'* ]]
  [[ "$output" == *'38;5;46m✓'* ]]
}

@test "description is truncated with an ellipsis to fit columns" {
  run_sub '{"session_id":"s","columns":40,"tasks":[{"id":"t1","name":"Explore","status":"running","tokenCount":500,"description":"a very long description that should be truncated to fit"}]}'
  local plain; plain=$(strip_ansi "$(printf '%s' "$output" | jq -r .content)")
  [[ "$plain" == *"…" ]]
  [ "${#plain}" -le 40 ]
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
  [[ "$output" == *"Explore"* ]] && [[ "$output" == *"code-review"* ]]
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
