#!/usr/bin/env bats
load helpers

# Absent is not zero. Claude Code only sends rate_limits for Pro/Max
# subscriptions, and only after the first API response. An empty bar would
# read as "0% used", so a missing figure drops the segment instead.
# Assertions use [ ] / case: bash 3.2 lets [[ ]] mismatches pass silently.

has() { [ "${2%%"$1"*}" != "$2" ]; }
lacks() { [ "${2%%"$1"*}" = "$2" ]; }

@test "rate_limits:null hides both bars" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"rate_limits":null}'
  [ "$status" -eq 0 ]
  lacks "5h:" "$output"
  lacks "7d:" "$output"
}

@test "five_hour present, seven_day absent: only the 5h bar renders" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"rate_limits":{"five_hour":{"used_percentage":40}}}'
  has "5h:" "$output"
  lacks "7d:" "$output"
}

@test "seven_day present, five_hour absent: only the 7d bar renders" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"rate_limits":{"seven_day":{"used_percentage":40}}}'
  lacks "5h:" "$output"
  has "7d:" "$output"
}

@test "used_percentage:null inside a present window hides that bar" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"rate_limits":{"five_hour":{"used_percentage":null,"resets_at":1},"seven_day":{"used_percentage":12}}}'
  lacks "5h:" "$output"
  has "7d:" "$output"
}

@test "a genuine 0% still draws an empty bar" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"rate_limits":{"five_hour":{"used_percentage":0},"seven_day":{"used_percentage":0}}}'
  plain=$(strip_ansi "$output")
  has "5h:░░░░░" "$plain"
  has "7d:░░░░░" "$plain"
}

@test "numeric string percentage is coerced, not dropped" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"rate_limits":{"seven_day":{"used_percentage":"88"}}}'
  plain=$(strip_ansi "$output")
  has "7d:████▍" "$plain"
}

@test "gateway spend_limit without the windows hides both bars" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"rate_limits":{"spend_limit":{"used_percentage":63,"resets_at":1}}}'
  lacks "5h:" "$output"
  lacks "7d:" "$output"
}

@test "7d countdown still works when five_hour is absent" {
  future=$(( $(date +%s) + 3700 ))
  run_hud "{\"cwd\":\"/tmp\",\"model\":{\"display_name\":\"Opus 4.7\"},\"rate_limits\":{\"seven_day\":{\"used_percentage\":90,\"resets_at\":$future}}}"
  plain=$(strip_ansi "$output")
  has "7d:" "$plain"
  has "↺1h1m" "$plain"
}

@test "--demo still renders both bars" {
  HUD_ARGS=--demo run_hud ''
  plain=$(strip_ansi "$output")
  has "5h:" "$plain"
  has "7d:" "$plain"
}
