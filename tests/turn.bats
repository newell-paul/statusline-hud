#!/usr/bin/env bats
load helpers

# Session-cumulative 🔥 segment. Reads total_cost_usd or total_input_tokens
# straight from the JSON — no state files. Always renders (no first-render
# blank). Format: "🔥 $X.XX" (usd) or "🔥 N" / "Nk" / "N.NM" (tokens).
# Colour tiers: < TURN_MED green(92), TURN_MED..TURN_HI yellow(33), ≥TURN_HI red(31).

# --- TURN_UNIT=usd ---

@test "usd unit: 🔥 shows cumulative cost with dollar sign" {
  TURN_UNIT=usd run_hud "$(make_json cost=0.42)"
  [[ "$output" == *"🔥 \$0.42"* ]]
}

@test "usd unit: green below \$5" {
  TURN_UNIT=usd run_hud "$(make_json cost=2.50)"
  [[ "$output" == *$'\033[92m🔥'* ]]
}

@test "usd unit: yellow \$5-20" {
  TURN_UNIT=usd run_hud "$(make_json cost=10.00)"
  [[ "$output" == *$'\033[33m🔥'* ]]
}

@test "usd unit: red ≥\$20" {
  TURN_UNIT=usd run_hud "$(make_json cost=25.00)"
  [[ "$output" == *$'\033[31m🔥'* ]]
}

@test "usd unit: zero cost still renders \$0.00" {
  TURN_UNIT=usd run_hud "$(make_json cost=0)"
  [[ "$output" == *"🔥 \$0.00"* ]]
}

# --- TURN_UNIT=tokens ---

@test "tokens unit: formatted with k suffix" {
  TURN_UNIT=tokens run_hud "$(make_json total_input=25000)"
  [[ "$output" == *"🔥 25k"* ]]
}

@test "tokens unit: under 1000 shown raw" {
  TURN_UNIT=tokens run_hud "$(make_json total_input=500)"
  [[ "$output" == *"🔥 500"* ]]
}

@test "tokens unit: over 1M formatted with M suffix" {
  TURN_UNIT=tokens run_hud "$(make_json total_input=1200000)"
  [[ "$output" == *"🔥 1.2M"* ]]
}

@test "tokens unit: green below TURN_MED_TOK (250k)" {
  TURN_UNIT=tokens run_hud "$(make_json total_input=100000)"
  [[ "$output" == *$'\033[92m🔥'* ]]
}

@test "tokens unit: yellow at TURN_MED_TOK..TURN_HI_TOK" {
  TURN_UNIT=tokens run_hud "$(make_json total_input=500000)"
  [[ "$output" == *$'\033[33m🔥'* ]]
}

@test "tokens unit: red at or above TURN_HI_TOK (750k)" {
  TURN_UNIT=tokens run_hud "$(make_json total_input=800000)"
  [[ "$output" == *$'\033[31m🔥'* ]]
}

@test "tokens unit: zero tokens still renders 🔥 0" {
  TURN_UNIT=tokens run_hud "$(make_json total_input=0)"
  [[ "$output" == *"🔥 0"* ]]
}
