#!/usr/bin/env bats
# scripts/session-title.sh: opt-in session title from the git branch.

HOOK="${BATS_TEST_DIRNAME}/../scripts/session-title.sh"

setup() {
  export HOME=$(mktemp -d)
  mkdir -p "$HOME/.claude"
  export CLAUDE_PLUGIN_DATA="$HOME/data"
  REPO="$HOME/repo"
  git init -q -b feature/wind "$REPO"
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

teardown() { rm -rf "$HOME"; }

opt_in() { echo 'SESSION_TITLE=branch' > "$HOME/.claude/statusline-hud.conf"; }

payload() {
  jq -cn --arg event "${1:-UserPromptSubmit}" --arg cwd "$REPO" --arg title "${2:-}" \
    '{hook_event_name: $event, session_id: "abc-123", cwd: $cwd}
     + (if $title == "" then {} else {session_title: $title} end)'
}

@test "off by default: no output" {
  run bash "$HOOK" <<<"$(payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "opted in: names an untitled session after the branch" {
  opt_in
  run bash "$HOOK" <<<"$(payload SessionStart)"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$output")" = "feature/wind" ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = "SessionStart" ]
}

@test "no output when the title already matches the branch" {
  opt_in
  run bash "$HOOK" <<<"$(payload)"
  run bash "$HOOK" <<<"$(payload UserPromptSubmit feature/wind)"
  [ -z "$output" ]
}

@test "renames after a branch change when it set the old title" {
  opt_in
  run bash "$HOOK" <<<"$(payload)"
  git -C "$REPO" switch -q -c fix/gusts
  run bash "$HOOK" <<<"$(payload UserPromptSubmit feature/wind)"
  [ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$output")" = "fix/gusts" ]
}

@test "leaves a title the user set alone" {
  opt_in
  run bash "$HOOK" <<<"$(payload UserPromptSubmit "my release work")"
  [ -z "$output" ]
  run bash "$HOOK" <<<"$(payload)"
  git -C "$REPO" switch -q -c fix/gusts
  run bash "$HOOK" <<<"$(payload UserPromptSubmit "renamed by hand")"
  [ -z "$output" ]
}

@test "detached HEAD and non-repos are skipped" {
  opt_in
  git -C "$REPO" switch -q --detach
  run bash "$HOOK" <<<"$(payload)"
  [ -z "$output" ]
  REPO="$HOME"
  run bash "$HOOK" <<<"$(payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ignores other events and unsafe session ids" {
  opt_in
  run bash "$HOOK" <<<"$(payload Stop)"
  [ -z "$output" ]
  run bash "$HOOK" <<<"$(jq -cn --arg cwd "$REPO" '{hook_event_name: "UserPromptSubmit", session_id: "../x", cwd: $cwd}')"
  [ -z "$output" ]
  [ ! -e "$HOME/data/x" ]
}

@test "a hostile repo config does not run code" {
  opt_in
  printf '#!/bin/sh\ntouch "%s/pwned"\n' "$HOME" > "$HOME/evil.sh"
  chmod +x "$HOME/evil.sh"
  git -C "$REPO" config core.fsmonitor "$HOME/evil.sh"
  run bash "$HOOK" <<<"$(payload)"
  [ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$output")" = "feature/wind" ]
  [ ! -e "$HOME/pwned" ]
}
