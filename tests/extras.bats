#!/usr/bin/env bats
load helpers

# --- Reset countdown ---

@test "no countdown when both rate limits below 60%" {
  run_hud "$(make_json rl5=30 rl7=20)"
  [[ "$output" != *"↺"* ]]
}

@test "countdown appears on 5h bar when rl5 >= 60% and >= rl7" {
  future=$(( $(date +%s) + 3700 ))  # ~1h 1m
  run_hud "$(make_json rl5=70 rl5_reset=$future rl7=20)"
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"↺"* ]]
  [[ "$output" == *"1h1m"* ]]
}

@test "countdown shows minutes only when < 1 hour" {
  future=$(( $(date +%s) + 1500 ))  # 25m
  run_hud "$(make_json rl5=65 rl5_reset=$future)"
  [[ "$output" == *"↺25m"* ]]
  [[ "$output" != *"h"* ]] || [[ "$output" == *"5h:"* ]]  # the "5h:" label is fine
}

@test "expired reset timestamp produces no countdown" {
  past=$(( $(date +%s) - 100 ))
  run_hud "$(make_json rl5=70 rl5_reset=$past)"
  [[ "$output" != *"↺"* ]]
}

# --- Cache hit ratio ---

@test "no cache indicator when total_input is small (<5000)" {
  run_hud "$(make_json total_input=1000 cache_read=800)"
  [[ "$output" != *"↩"* ]]
}

@test "cache ratio shown when total_input > 5000, green at >=60%" {
  run_hud "$(make_json total_input=10000 cache_read=8500)"
  [[ "$output" == *"↩85%"* ]]
  [[ "$output" == *$'\033[92m↩'* ]]
}

@test "cache ratio yellow at 30-59%" {
  run_hud "$(make_json total_input=10000 cache_read=4500)"
  [[ "$output" == *"↩45%"* ]]
  [[ "$output" == *$'\033[33m↩'* ]]
}

@test "cache ratio red at <30%" {
  run_hud "$(make_json total_input=10000 cache_read=1000)"
  [[ "$output" == *"↩10%"* ]]
  [[ "$output" == *$'\033[31m↩'* ]]
}

@test "cache ratio capped at 100%" {
  run_hud "$(make_json total_input=10000 cache_read=15000)"
  [[ "$output" == *"↩100%"* ]]
}

# --- Integration: real Opus payload renders all sections without crash ---

@test "real Opus payload renders all extras correctly" {
  run_hud "$(cat "${BATS_TEST_DIRNAME}/fixtures/real-opus.json")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"7d:"* ]]
  [[ "$output" != *"↺"* ]]  # both 5%/8% — below 60% threshold
  [[ "$output" == *"↩"* ]]  # total_input=30352 (>5k), cache_read=29743 → ~98%
}
