#!/usr/bin/env bats
# scripts/session-start.sh: symlink upkeep and the one-time nudge.

HOOK="${BATS_TEST_DIRNAME}/../scripts/session-start.sh"

setup() {
  export HOME=$(mktemp -d)
  mkdir -p "$HOME/.claude"
  export CLAUDE_PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
  export CLAUDE_PLUGIN_DATA="$HOME/data"
}

teardown() { rm -rf "$HOME"; }

@test "nudges once when nothing is wired up, then stays quiet" {
  echo '{}' > "$HOME/.claude/settings.json"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/statusline-hud"* ]]
  run bash "$HOOK"
  [ -z "$output" ]
}

@test "no nudge when settings already reference statusline-hud" {
  echo '{"statusLine":{"command":"~/statusline-hud/statusline-hud.sh"}}' > "$HOME/.claude/settings.json"
  run bash "$HOOK"
  [ -z "$output" ]
}

@test "re-points a stale symlink at the current plugin script" {
  ln -s /old/cache/statusline-hud.sh "$HOME/.claude/statusline-hud.sh"
  run bash "$HOOK"
  [ -z "$output" ]
  [ "$(readlink "$HOME/.claude/statusline-hud.sh")" = "$CLAUDE_PLUGIN_ROOT/statusline-hud.sh" ]
}

@test "re-points the subagent symlink too, and leaves a missing one alone" {
  ln -s /old/cache/statusline-hud.sh "$HOME/.claude/statusline-hud.sh"
  ln -s /old/cache/subagent-statusline.sh "$HOME/.claude/subagent-statusline.sh"
  run bash "$HOOK"
  [ "$(readlink "$HOME/.claude/subagent-statusline.sh")" = "$CLAUDE_PLUGIN_ROOT/subagent-statusline.sh" ]
  rm "$HOME/.claude/subagent-statusline.sh"
  run bash "$HOOK"
  [ ! -e "$HOME/.claude/subagent-statusline.sh" ]
}

@test "leaves a hand-installed regular file alone" {
  echo 'mine' > "$HOME/.claude/statusline-hud.sh"
  run bash "$HOOK"
  [ -z "$output" ]
  [ ! -L "$HOME/.claude/statusline-hud.sh" ]
  [ "$(cat "$HOME/.claude/statusline-hud.sh")" = mine ]
}
