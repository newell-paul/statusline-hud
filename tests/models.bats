#!/usr/bin/env bats
load helpers

@test "Haiku 4.5: model name shown, no effort badge" {
  run_hud "$(make_json model='Haiku 4.5')"
  [[ "$output" == *"Haiku 4.5"* ]]
  [[ "$output" != *"⚡"* ]]
}

@test "Sonnet 4.6: model name shown, no effort badge by default" {
  run_hud "$(make_json model='Sonnet 4.6')"
  [[ "$output" == *"Sonnet 4.6"* ]]
  [[ "$output" != *"⚡"* ]]
}

@test "Opus 4.7 (1M context): compacted to (1M)" {
  run_hud "$(make_json model='Opus 4.7 (1M context)' effort=medium)"
  [[ "$output" == *"Opus 4.7 (1M)"* ]]
  [[ "$output" != *"(1M context)"* ]]
}

@test "Opus 4.7 without 1M: no (1M) suffix added" {
  run_hud "$(make_json model='Opus 4.7' effort=medium)"
  [[ "$output" == *"Opus 4.7"* ]]
  [[ "$output" != *"(1M)"* ]]
}

@test "Opus 4.7 with all effort levels renders badge" {
  for lvl in low medium high xhigh max; do
    run_hud "$(make_json model='Opus 4.7 (1M context)' effort=$lvl)"
    [[ "$output" == *"⚡"* ]] || { echo "missing badge for $lvl"; return 1; }
  done
}

@test "missing model field falls back to ?" {
  run_hud '{"cwd":"/Users/paulnewell/statusline-hud","context_window":{"used_percentage":10},"cost":{"total_cost_usd":0,"total_duration_ms":0},"rate_limits":{"five_hour":{"used_percentage":0}}}'
  [[ "$output" == *"?"* ]]
}

# --- Model-tier coloring: Opus → orange, Sonnet → bright blue, Haiku → green.
# Unknown models fall back to the neutral blue (34) so future releases still
# render visibly without a code change.

@test "Opus name is coloured orange (208)" {
  run_hud "$(make_json model='Opus 4.7 (1M context)')"
  assert_color "$output" 208 "Opus orange"
}

@test "Sonnet name is coloured bright blue (39)" {
  run_hud "$(make_json model='Sonnet 4.6')"
  assert_color "$output" 39 "Sonnet bright blue"
}

@test "Haiku name is coloured green (46)" {
  run_hud "$(make_json model='Haiku 4.5')"
  assert_color "$output" 46 "Haiku green"
}

@test "unknown model name falls back to neutral blue (34)" {
  run_hud "$(make_json model='Mystery Model X')"
  assert_color "$output" 34 "unknown model fallback blue"
}

@test "model match is case-insensitive (lowercase opus)" {
  run_hud "$(make_json model='opus-4-7')"
  assert_color "$output" 208 "lowercase opus still orange"
}
