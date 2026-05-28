#!/usr/bin/env bats
load helpers

@test "effort=low renders ⚡Lo in grey (240)" {
  run_hud "$(make_json effort=low)"
  [[ "$output" == *"⚡Lo"* ]]
  assert_color "$output" 240 "low"
}

@test "effort=medium renders ⚡Med in light grey (250)" {
  run_hud "$(make_json effort=medium)"
  [[ "$output" == *"⚡Med"* ]]
  assert_color "$output" 250 "medium"
}

@test "effort=high renders ⚡Hi in yellow (220)" {
  run_hud "$(make_json effort=high)"
  [[ "$output" == *"⚡Hi"* ]]
  assert_color "$output" 220 "high"
}

@test "effort=xhigh renders ⚡xHi in orange (208)" {
  run_hud "$(make_json effort=xhigh used=10 rl5=5)"
  [[ "$output" == *"⚡xHi"* ]]
  assert_color "$output" 208 "xhigh"
}

@test "effort=max renders ⚡Max in red (196)" {
  run_hud "$(make_json effort=max used=10 rl5=5)"
  [[ "$output" == *"⚡Max"* ]]
  assert_color "$output" 196 "max"
}

@test "fast_mode=true adds 🚀" {
  run_hud "$(make_json effort=high fast=true)"
  [[ "$output" == *"🚀"* ]]
}

@test "fast_mode=false omits 🚀" {
  run_hud "$(make_json effort=high fast=false)"
  [[ "$output" != *"🚀"* ]]
}
