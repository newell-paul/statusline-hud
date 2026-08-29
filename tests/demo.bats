#!/usr/bin/env bats
load helpers

@test "--demo renders every segment on one line without reading stdin" {
  HUD_ARGS=--demo run_hud ''
  [ "$status" -eq 0 ]
  local plain; plain=$(strip_ansi "$output")
  for want in "🐙 #42 ✓" "🟢" "Opus 5" "⚡Hi" "💭" "ctx:" "5h:" "↺" "7d:" "+156 −23" "Wire up the statusline" "⎇ feature-xyz" "↩94%" "❄4m" '🔥 $5.64' "/h)"; do
    [[ "$plain" == *"$want"* ]] || { echo "missing: $want"; echo "$plain"; return 1; }
  done
  [[ "$plain" != *$'\n'* ]]
}

@test "--demo spawns no background fetch" {
  MR_CACHE_DIR=$(mktemp -d)
  HUD_ARGS=--demo run_hud ''
  sleep 0.3
  [ -z "$(ls -A "$MR_CACHE_DIR" 2>/dev/null)" ]
  rm -rf "$MR_CACHE_DIR"
}
