#!/usr/bin/env bats
load helpers

# prompt_cache (Claude Code >= 2.1.251) is the session-wide view of the
# prompt cache. When present it takes precedence over the per-turn
# cache_read/total_input fallback. `warm` says whether the cached prefix is
# still inside its TTL — cold means the next turn re-caches the whole prefix.

@test "prompt_cache.hit_ratio used in preference to per-turn fallback" {
  run_hud "$(make_json total_input=10000 cache_read=1000 pc_ratio=0.91 pc_warm=true)"
  [[ "$output" == *"↩91%"* ]]
  [[ "$output" != *"↩10%"* ]]
}

@test "prompt_cache shown even when total_input is below the fallback minimum" {
  run_hud "$(make_json total_input=100 cache_read=0 pc_ratio=0.75 pc_warm=true)"
  [[ "$output" == *"↩75%"* ]]
}

@test "warm cache uses ↩ glyph with ratio tier colour" {
  run_hud "$(make_json pc_ratio=0.85 pc_warm=true)"
  [[ "$output" == *$'\033[92m↩85%'* ]]
}

@test "cold cache uses ❄ glyph" {
  run_hud "$(make_json pc_ratio=0.85 pc_warm=false)"
  [[ "$output" == *"❄85%"* ]]
  [[ "$output" != *"↩"* ]]
}

@test "cold cache glyph is cyan regardless of ratio" {
  run_hud "$(make_json pc_ratio=0.85 pc_warm=false)"
  [[ "$output" == *$'\033[36m❄'* ]]
}

@test "prompt_cache ratio tiers: yellow at 30-59%, red below 30%" {
  run_hud "$(make_json pc_ratio=0.45 pc_warm=true)"
  [[ "$output" == *$'\033[33m↩45%'* ]]
  run_hud "$(make_json pc_ratio=0.12 pc_warm=true)"
  [[ "$output" == *$'\033[31m↩12%'* ]]
}

@test "null hit_ratio falls back to per-turn maths" {
  run_hud "$(make_json total_input=10000 cache_read=8500 pc_warm=true)"
  [[ "$output" == *"↩85%"* ]]
}

@test "absent prompt_cache keeps the legacy fallback behaviour" {
  run_hud "$(make_json total_input=10000 cache_read=4500)"
  [[ "$output" == *"↩45%"* ]]
}

@test "prompt_cache ratio above 1 is capped at 100%" {
  run_hud "$(make_json pc_ratio=1.5 pc_warm=true)"
  [[ "$output" == *"↩100%"* ]]
}

# --- Expiry countdown (prompt_cache.expires_at) ----------------------------

@test "warm cache expiring within the warn window shows ❄Xm after the ratio" {
  local soon=$(( $(date +%s) + 250 ))   # ~4m
  run_hud "$(make_json pc_ratio=0.97 pc_warm=true pc_expires=$soon)"
  [[ "$(strip_ansi "$output")" == *"↩97% ❄4m"* ]]
}

@test "warm cache with plenty of TTL left shows no countdown" {
  local later=$(( $(date +%s) + 3000 ))  # 50m > CACHE_EXPIRY_WARN_MIN
  run_hud "$(make_json pc_ratio=0.97 pc_warm=true pc_expires=$later)"
  [[ "$(strip_ansi "$output")" == *"↩97%"* ]]
  [[ "$output" != *"❄"* ]]
}

@test "cold cache keeps the ❄ glyph and never shows a countdown" {
  local soon=$(( $(date +%s) + 250 ))
  run_hud "$(make_json pc_ratio=0.97 pc_warm=false pc_expires=$soon)"
  [[ "$(strip_ansi "$output")" == *"❄97%"* ]]
  [[ "$(strip_ansi "$output")" != *"❄4m"* ]]
}

@test "expired expires_at while still warm shows no countdown" {
  local past=$(( $(date +%s) - 10 ))
  run_hud "$(make_json pc_ratio=0.97 pc_warm=true pc_expires=$past)"
  [[ "$(strip_ansi "$output")" == *"↩97%"* ]]
  [[ "$output" != *"❄"* ]]
}
