#!/usr/bin/env bats
load helpers

# Contract test: the recorded Claude Code statusline JSON is flattened to
# "path: type" lines and compared to a checked-in snapshot. If Anthropic
# adds, removes, renames, or changes the type of any field, this test fails.
#
# To regenerate after an intentional schema change:
#   ./tests/regen-schema.sh

FIXTURE="${BATS_TEST_DIRNAME}/fixtures/real-opus.json"
SNAPSHOT="${BATS_TEST_DIRNAME}/fixtures/real-opus.schema"

schema_of() {
  jq -r '
    . as $root
    | [paths(type != "object" and type != "array")]
    | map(. as $p | ($p | map(tostring) | join(".")) + ": " + ($root | getpath($p) | type))
    | sort
    | unique[]
  ' "$1"
}

@test "fixture file exists" {
  [ -f "$FIXTURE" ]
  [ -f "$SNAPSHOT" ]
}

@test "fixture matches checked-in schema snapshot" {
  current=$(schema_of "$FIXTURE")
  expected=$(cat "$SNAPSHOT")
  if [ "$current" != "$expected" ]; then
    echo "Schema drift detected!"
    echo "--- expected ($(echo "$expected" | wc -l | tr -d ' ') lines) ---"
    echo "$expected"
    echo "--- got ($(echo "$current" | wc -l | tr -d ' ') lines) ---"
    echo "$current"
    echo "--- diff ---"
    diff <(echo "$expected") <(echo "$current") || true
    return 1
  fi
}

# Sanity: every JSON path the script actually reads from must be present.
# This catches the case where the schema snapshot is updated but a field
# the script depends on disappears.
@test "script's required fields are present in fixture" {
  required=(
    "workspace.current_dir"
    "cwd"
    "model.display_name"
    "context_window.used_percentage"
    "cost.total_cost_usd"
    "rate_limits.five_hour.used_percentage"
    "effort.level"
    "fast_mode"
  )
  schema=$(schema_of "$FIXTURE")
  for path in "${required[@]}"; do
    if ! grep -q "^${path}: " <<<"$schema"; then
      echo "missing required field in fixture: $path"
      return 1
    fi
  done
}

@test "fixture renders without error through the statusline script" {
  run_hud "$(cat "$FIXTURE")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 4.7"* ]]
  [[ "$output" == *"⚡Med"* ]]
  [[ "$output" == *"ctx:"* ]]
  [[ "$output" == *"5h:"* ]]
}
