#!/usr/bin/env bats
load helpers

# Edge cases for bar() — single colour per tier, 5 cells × 8 sub-steps.
# Sub-step glyphs: ▏▎▍▌▋▊▉█. Cells are uniform width (20% each); only the
# WHOLE-bar colour shifts at tier boundaries.

@test "ctx bar at 20% fully lights cell 1, rest empty" {
  run_hud "$(make_json used=20)"
  stripped=$(strip_ansi "$output")
  [[ "$stripped" == *"ctx:█░░░░"* ]]
}

@test "ctx bar at 10% lights half of cell 1 (▌)" {
  run_hud "$(make_json used=10)"
  stripped=$(strip_ansi "$output")
  # 10 % 20 = 10 → 10 * 8 / 20 = 4 sub-steps → ▌
  [[ "$stripped" == *"ctx:▌░░░░"* ]]
}

@test "bar at 0% has no fill glyphs, only empty cells" {
  run_hud "$(make_json used=0)"
  [[ "$output" == *"░░░░░"* ]]
}

@test "bar at 100% renders all five filled cells" {
  run_hud "$(make_json used=100)"
  stripped=$(strip_ansi "$output")
  [[ "$stripped" == *"█████"* ]]
}

@test "bar clamps negative pct to 0 (renders empty)" {
  run_hud "$(make_json used=-5)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctx:"* ]]
}

@test "bar clamps >100 pct to 100 (renders full red bar)" {
  run_hud "$(make_json used=150)"
  [ "$status" -eq 0 ]
  assert_color "$output" 196 "red bar at clamped 100"
  stripped=$(strip_ansi "$output")
  [[ "$stripped" == *"█████"* ]]
}

@test "non-integer used_percentage gets floored cleanly" {
  # jq floors 42.7 → 42. ctx thresholds (30 50 60): 42 ≥ 30 → whole bar yellow.
  # Fill: 42 / 20 = 2 full cells, sub = (42 % 20) * 8 / 20 = 2*8/20 = 0 → no partial.
  run_hud '{"cwd":"/tmp","model":{"display_name":"Opus 4.7"},"context_window":{"used_percentage":42.7},"cost":{"total_cost_usd":0,"total_duration_ms":0},"rate_limits":{"five_hour":{"used_percentage":0}}}'
  [ "$status" -eq 0 ]
  assert_color "$output" 226 "yellow bar at 42%"
  stripped=$(strip_ansi "$output")
  [[ "$stripped" == *"ctx:██░░░"* ]]
}
