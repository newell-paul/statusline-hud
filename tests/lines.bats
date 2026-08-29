#!/usr/bin/env bats
load helpers

@test "lines segment hidden when nothing changed" {
  run_hud "$(make_json)"
  [[ "$(strip_ansi "$output")" != *"+0"* ]]
  run_hud "$(make_json lines_add=0 lines_del=0)"
  [[ "$(strip_ansi "$output")" != *"+0"* ]]
}

@test "lines segment shows +N −N in green and red" {
  run_hud "$(make_json lines_add=156 lines_del=23)"
  [[ "$(strip_ansi "$output")" == *"+156 −23"* ]]
  assert_color "$output" 46 "added green"
  assert_color "$output" 196 "removed red"
}

@test "lines segment shows when only one side is non-zero" {
  run_hud "$(make_json lines_add=3)"
  [[ "$(strip_ansi "$output")" == *"+3 −0"* ]]
}

@test "thinking.enabled adds 💭 after the effort badge" {
  run_hud "$(make_json effort=high thinking=true)"
  [[ "$(strip_ansi "$output")" == *"⚡Hi 💭"* ]]
  run_hud "$(make_json effort=high thinking=false)"
  [[ "$output" != *"💭"* ]]
  run_hud "$(make_json effort=high)"
  [[ "$output" != *"💭"* ]]
}
