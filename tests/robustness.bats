#!/usr/bin/env bats
load helpers

@test "malformed JSON prints '(parse failed)'" {
  run_hud 'not json at all'
  [ "$status" -eq 0 ]
  [[ "$output" == *"parse failed"* ]]
}

@test "empty input prints '(parse failed)' and exits 0" {
  run_hud ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"parse failed"* ]]
}

@test "missing context_window defaults to 0% (empty bar, no fill colour)" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"cost":{"total_cost_usd":0,"total_duration_ms":0},"rate_limits":{"five_hour":{"used_percentage":0}}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctx:"* ]]
  [[ "$output" == *"░░░░░"* ]]
  assert_no_color "$output" 46  "no green fill at 0%"
}

@test "missing rate_limits defaults to 0% (empty 5h bar, no fill colour)" {
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"context_window":{"used_percentage":10},"cost":{"total_cost_usd":0,"total_duration_ms":0}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h:"* ]]
  # 5h section should contain the empty-track glyphs after the label
  [[ "$output" == *"5h:"*"░░░░░"* ]]
}

@test "real Haiku JSON payload (no effort field)" {
  run_hud '{"session_id":"test","model":{"display_name":"Haiku 4.5"},"cwd":"/tmp","context_window":{"used_percentage":12},"cost":{"total_cost_usd":0.01,"total_duration_ms":60000},"rate_limits":{"five_hour":{"used_percentage":3}}}'
  [[ "$output" == *"Haiku 4.5"* ]]
  [[ "$output" != *"⚡"* ]]
}

# --- TURN_UNIT validation: anything outside {usd,tokens} falls back to the
# documented default (usd). Coercing to tokens would silently change
# semantics for anyone who typo'd the value in the script.

@test "TURN_UNIT=bogus falls back to usd (the documented default)" {
  TURN_UNIT=bogus run_hud "$(make_json cost=0.20 total_input=25000)"
  [[ "$output" == *"🔥 \$"* ]]
}

@test "TURN_UNIT=Tokens (mixed case) falls back to usd (allowlist is lowercase)" {
  TURN_UNIT=Tokens run_hud "$(make_json cost=0.20 total_input=25000)"
  [[ "$output" == *"🔥 \$"* ]]
}
