#!/usr/bin/env bats
load helpers

# --- burn rate in the flame -------------------------------------------------

@test "usd flame shows burn rate once the session is 30s old" {
  run_hud "$(make_json cost=1.00 dur=1800000)"
  [[ "$(strip_ansi "$output")" == *'🔥 $1.00 ($2.00/h)'* ]]
}

@test "no burn rate under 30s or when TURN_RATE=0" {
  run_hud "$(make_json cost=1.00 dur=20000)"
  [[ "$(strip_ansi "$output")" == *'🔥 $1.00'* ]]
  [[ "$output" != *"/h)"* ]]
  HUD_CONF=$(mktemp); echo 'TURN_RATE=0' > "$HUD_CONF"
  run_hud "$(make_json cost=1.00 dur=1800000)"
  [[ "$output" != *"/h)"* ]]
  rm -f "$HUD_CONF"
}

@test "tokens flame never shows a burn rate" {
  TURN_UNIT=tokens run_hud "$(make_json total_input=50000 dur=1800000)"
  [[ "$output" != *"/h)"* ]]
}

# --- session / worktree segments -------------------------------------------

@test "session segment shows the name, truncated at SESSION_MAX" {
  run_hud "$(make_json session='Fix the flaky login test')"
  [[ "$(strip_ansi "$output")" == *"Fix the flaky login test"* ]]
  run_hud "$(make_json session='A very long session name that keeps going')"
  [[ "$(strip_ansi "$output")" == *"A very long session nam…"* ]]
}

@test "session and worktree segments hide when absent" {
  run_hud "$(make_json)"
  [[ "$output" != *"⎇"* ]]
  [[ "$(strip_ansi "$output")" != *"·  ·"* ]]
}

@test "worktree segment prefers workspace.git_worktree, falls back to worktree.name" {
  run_hud "$(make_json worktree=my-feature)"
  [[ "$(strip_ansi "$output")" == *"⎇ my-feature"* ]]
  run_hud "$(jq -c '.workspace.git_worktree="linked-wt"' <<<"$(make_json worktree=other)")"
  [[ "$(strip_ansi "$output")" == *"⎇ linked-wt"* ]]
}

# --- NERD_FONT --------------------------------------------------------------

@test "NERD_FONT=1 swaps the MR prefix for the Octocat glyph" {
  HUD_CONF=$(mktemp); echo 'NERD_FONT=1' > "$HUD_CONF"
  run_hud "$(make_json pr_number=42 pr_state=approved)"
  [[ "$(strip_ansi "$output")" == *$' #42 ✓'* ]]
  [[ "$output" != *"🐙"* ]]
  rm -f "$HUD_CONF"
}

@test "NERD_FONT=1 leaves a user-set prefix alone" {
  HUD_CONF=$(mktemp); printf 'NERD_FONT=1\nMR_PREFIX_GITHUB="PR "\n' > "$HUD_CONF"
  run_hud "$(make_json pr_number=42 pr_state=approved)"
  [[ "$(strip_ansi "$output")" == *"PR 42 ✓"* ]]
  rm -f "$HUD_CONF"
}

# --- custom segment from the conf ------------------------------------------

@test "a seg_<name> function in the conf becomes a segment" {
  HUD_CONF=$(mktemp); printf 'seg_hello() { printf "hi there"; }\nSEGMENTS=(hello model)\n' > "$HUD_CONF"
  run_hud "$(make_json)"
  [[ "$(strip_ansi "$output")" == "hi there · Opus 4.7"* ]]
  rm -f "$HUD_CONF"
}

# --- agents segment ---------------------------------------------------------
# subagent-statusline.sh writes the running count to $MR_CACHE_DIR/agents-<session_id>;
# the segment shows 🤖 ×N while that file is fresh. Off by default: the panel
# rows under the prompt already show each agent.

@test "agents segment shows 🤖 ×N from a fresh count file" {
  MR_CACHE_DIR=$(mktemp -d); chmod 700 "$MR_CACHE_DIR"
  HUD_CONF=$(mktemp); echo 'SEGMENTS=(model agents ctx)' > "$HUD_CONF"
  echo 2 > "$MR_CACHE_DIR/agents-sess-1"
  run_hud "$(make_json session_id=sess-1)"
  [[ "$output" == *$'\033[38;5;141m🤖 ×2'* ]]
  rm -rf "$MR_CACHE_DIR" "$HUD_CONF"
}

@test "agents segment hides on zero, a stale file, garbage, or no session id" {
  MR_CACHE_DIR=$(mktemp -d); chmod 700 "$MR_CACHE_DIR"
  echo 0 > "$MR_CACHE_DIR/agents-sess-1"
  run_hud "$(make_json session_id=sess-1)"
  [[ "$output" != *"🤖"* ]]
  echo 3 > "$MR_CACHE_DIR/agents-sess-1"; touch -t 202001010000 "$MR_CACHE_DIR/agents-sess-1"
  run_hud "$(make_json session_id=sess-1)"
  [[ "$output" != *"🤖"* ]]
  echo 'x; rm -rf /' > "$MR_CACHE_DIR/agents-sess-1"
  run_hud "$(make_json session_id=sess-1)"
  [[ "$output" != *"🤖"* ]]
  echo 2 > "$MR_CACHE_DIR/agents-sess-1"
  run_hud "$(make_json)"
  [[ "$output" != *"🤖"* ]]
  rm -rf "$MR_CACHE_DIR"
}
