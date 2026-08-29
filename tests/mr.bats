#!/usr/bin/env bats
load helpers

# The mr segment shows the GitLab merge request for the current branch via
# `glab mr view`. glab takes ~1s, and the statusline renders on every
# keystroke, so the lookup runs in the background and is cached per
# repo+branch for MR_TTL seconds. A render never blocks on glab:
#   - no cache  → spawn refresh, print nothing
#   - fresh     → print cached badge
#   - stale     → print cached badge, spawn refresh
# Tests put a fake `glab` first on PATH and wait for the cache file.

setup() {
  REPO=$(make_clean_repo)
  ( cd "$REPO" && git checkout -q -b feature )
  MR_CACHE_DIR=$(mktemp -d)
  FAKE_BIN=$(mktemp -d)
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  rm -rf "$REPO" "$MR_CACHE_DIR" "$FAKE_BIN"
}

# fake_glab <json | empty>  — empty body means "no MR for this branch" (exit 1)
fake_glab() {
  if [ -z "$1" ]; then
    printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKE_BIN/glab"
  else
    printf '#!/usr/bin/env bash\ncat <<'"'"'J'"'"'\n%s\nJ\n' "$1" > "$FAKE_BIN/glab"
  fi
  chmod +x "$FAKE_BIN/glab"
}

mr_json() {
  # $1 state, $2 draft, $3 detailed_merge_status, $4 has_conflicts
  printf '{"iid":23,"state":"%s","draft":%s,"detailed_merge_status":"%s","has_conflicts":%s}' "$1" "$2" "$3" "$4"
}

# Render once to prime, wait for the background refresh, render again.
render_after_refresh() {
  run_hud "$(make_json cwd="$REPO")"
  local i
  for i in $(seq 1 50); do
    ls "$MR_CACHE_DIR"/*.mr >/dev/null 2>&1 && break
    sleep 0.1
  done
  run_hud "$(make_json cwd="$REPO")"
}

@test "first render never blocks: no badge, refresh spawned" {
  fake_glab "$(mr_json opened false mergeable false)"
  run_hud "$(make_json cwd="$REPO")"
  [ "$status" -eq 0 ]
  [[ "$output" != *"!23"* ]]
}

@test "mergeable MR renders green !N ✓" {
  fake_glab "$(mr_json opened false mergeable false)"
  render_after_refresh
  [[ "$output" == *"!23 ✓"* ]]
  assert_color "$output" 46 "mergeable green"
}

@test "draft MR renders ✎ !N in grey" {
  fake_glab "$(mr_json opened true mergeable false)"
  render_after_refresh
  [[ "$output" == *"✎ !23"* ]]
  assert_color "$output" 245 "draft grey"
}

@test "MR with conflicts renders red !N ✗" {
  fake_glab "$(mr_json opened false conflict true)"
  render_after_refresh
  [[ "$output" == *"!23 ✗"* ]]
  assert_color "$output" 196 "conflict red"
}

@test "MR still checking renders yellow !N without glyph" {
  fake_glab "$(mr_json opened false checking false)"
  render_after_refresh
  [[ "$output" == *"!23"* ]]
  [[ "$output" != *"!23 ✓"* ]]
  [[ "$output" != *"!23 ✗"* ]]
  assert_color "$output" 226 "pending yellow"
}

@test "merged MR renders ⇄ !N" {
  fake_glab "$(mr_json merged false not_open false)"
  render_after_refresh
  [[ "$output" == *"⇄ !23"* ]]
  assert_color "$output" 99 "merged purple"
}

@test "closed MR renders dim !N" {
  fake_glab "$(mr_json closed false not_open false)"
  render_after_refresh
  [[ "$output" == *"!23"* ]]
  assert_color "$output" 240 "closed dim"
}

@test "branch with no MR caches the miss and shows nothing" {
  fake_glab ""
  render_after_refresh
  [[ "$output" != *"!"* ]]
  [ "$(ls "$MR_CACHE_DIR"/*.mr | wc -l | tr -d ' ')" = "1" ]
}

@test "fresh cache is served without calling glab again" {
  fake_glab "$(mr_json opened false mergeable false)"
  render_after_refresh
  fake_glab ""
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" == *"!23 ✓"* ]]
}

@test "stale cache is served immediately and refreshed in the background" {
  MR_TTL=1
  fake_glab "$(mr_json opened false mergeable false)"
  render_after_refresh
  sleep 1.2
  fake_glab "$(mr_json opened false conflict true)"
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" == *"!23 ✓"* ]]
  local i
  for i in $(seq 1 50); do
    grep -q conflict "$MR_CACHE_DIR"/*.mr 2>/dev/null && break
    sleep 0.1
  done
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" == *"!23 ✗"* ]]
}

@test "cache is keyed per branch" {
  fake_glab "$(mr_json opened false mergeable false)"
  render_after_refresh
  ( cd "$REPO" && git checkout -q -b other )
  fake_glab ""
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" != *"!23"* ]]
}

@test "no glab on PATH: segment silently absent" {
  PATH="$FAKE_BIN:/usr/bin:/bin"
  run_hud "$(make_json cwd="$REPO")"
  [ "$status" -eq 0 ]
  [[ "$output" != *"!"* ]]
  [ -z "$(ls -A "$MR_CACHE_DIR")" ]
}

@test "outside a git repo: segment absent, no cache written" {
  fake_glab "$(mr_json opened false mergeable false)"
  run_hud "$(make_json cwd=/tmp)"
  [[ "$output" != *"!23"* ]]
  [ -z "$(ls -A "$MR_CACHE_DIR")" ]
}

@test "control bytes in cached glab output are scrubbed" {
  fake_glab "$(printf '{"iid":23,"state":"opened\\u001b[2J","draft":false,"detailed_merge_status":"mergeable","has_conflicts":false}')"
  render_after_refresh
  [[ "$output" != *$'\033[2J'* ]]
}
