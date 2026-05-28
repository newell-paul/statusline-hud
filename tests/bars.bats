#!/usr/bin/env bats
load helpers

# Single-colour-per-tier bars. The whole bar paints in one TIER_COLOR:
#   46  green   — p below first threshold
#   226 yellow  — p ≥ first  threshold
#   214 orange  — p ≥ second threshold
#   196 red     — p ≥ third  threshold
#
# ctx thresholds  : BAR_CTX=(30 50 60)
# rate-limit bars : BAR_LINEAR=(60 80 95)

@test "ctx bar is green (46) at 10%" {
  run_hud "$(make_json used=10 rl5=5)"
  assert_color "$output" 46 "green bar"
}

@test "ctx bar still green at 29% (just below yellow boundary)" {
  run_hud "$(make_json used=29 rl5=5)"
  assert_color "$output" 46 "green bar"
  assert_no_color "$output" 226 "yellow bar"
}

@test "ctx bar flips to yellow (226) at 30%" {
  run_hud "$(make_json used=30 rl5=5)"
  assert_color "$output" 226 "yellow bar"
}

@test "ctx bar flips to orange (214) at 50%" {
  run_hud "$(make_json used=50 rl5=5)"
  assert_color "$output" 214 "orange bar"
}

@test "ctx bar flips to red (196) at 60%" {
  run_hud "$(make_json used=60 rl5=5)"
  assert_color "$output" 196 "red bar"
}

# 5h rate-limit bar — linear thresholds (60 80 95)

@test "5h bar green (46) at 20%" {
  run_hud "$(make_json used=10 rl5=20)"
  assert_color "$output" 46 "green bar"
}

@test "5h bar yellow (226) at 60%" {
  run_hud "$(make_json used=10 rl5=60)"
  assert_color "$output" 226 "yellow bar"
}

@test "5h bar orange (214) at 80%" {
  run_hud "$(make_json used=10 rl5=80)"
  assert_color "$output" 214 "orange bar"
}

@test "5h bar red (196) at 100%" {
  run_hud "$(make_json used=10 rl5=100)"
  assert_color "$output" 196 "red bar"
}
