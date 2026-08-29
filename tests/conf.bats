#!/usr/bin/env bats
load helpers

setup() {
  HUD_CONF=$(mktemp)
}

teardown() {
  rm -f "$HUD_CONF"
}

@test "conf overrides a scalar setting" {
  echo 'SEP_CHAR=" | "' > "$HUD_CONF"
  run_hud "$(make_json)"
  [[ "$output" == *" | "* ]]
  [[ "$output" != *" · "* ]]
}

@test "conf overrides SEGMENTS" {
  echo 'SEGMENTS=(model)' > "$HUD_CONF"
  run_hud "$(make_json)"
  [[ "$output" != *"ctx:"* ]]
  [[ "$output" != *"5h:"* ]]
}

@test "conf TURN_UNIT is validated after sourcing" {
  echo 'TURN_UNIT=bogus' > "$HUD_CONF"
  run_hud "$(make_json cost=1.23)"
  [ "$status" -eq 0 ]
  [[ "$output" == *'$1.23'* ]]
}

@test "missing conf is ignored" {
  rm -f "$HUD_CONF"
  run_hud "$(make_json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctx:"* ]]
}
