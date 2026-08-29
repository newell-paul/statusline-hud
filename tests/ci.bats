#!/usr/bin/env bats
load helpers

# The ci segment shows the latest pipeline for the current branch as a
# traffic-light dot, linked to the pipeline. GitLab via `glab ci get`, GitHub
# via `gh run list`. Same background-refresh cache as the mr segment. A
# pipeline whose sha is not the local HEAD renders ⚪ — the result belongs
# to an older commit.

setup() {
  REPO=$(make_clean_repo)
  ( cd "$REPO" && git checkout -q -b feature && git remote add origin git@gitlab.com:acme/widgets.git )
  HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
  MR_CACHE_DIR=$(mktemp -d)
  FAKE_BIN=$(mktemp -d)
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  rm -rf "$REPO" "$MR_CACHE_DIR" "$FAKE_BIN"
}

# fake_glab_ci <status> [sha]  — `glab ci get` answers; `glab mr view` says no MR
fake_glab_ci() {
  local sha="${2:-$HEAD_SHA}"
  cat > "$FAKE_BIN/glab" <<G
#!/usr/bin/env bash
[ "\$1 \$2" = "ci get" ] || exit 1
printf '{"id":77,"status":"%s","sha":"%s","web_url":"https://gitlab.example/acme/widgets/-/pipelines/77"}' "$1" "$sha"
G
  chmod +x "$FAKE_BIN/glab"
}

# fake_gh_ci <status> <conclusion> [sha]
fake_gh_ci() {
  local sha="${3:-$HEAD_SHA}"
  cat > "$FAKE_BIN/gh" <<G
#!/usr/bin/env bash
[ "\$1 \$2" = "run list" ] || exit 1
printf '[{"status":"%s","conclusion":%s,"headSha":"%s","url":"https://github.com/acme/widgets/actions/runs/9"}]' "$1" '$2' "$sha"
G
  chmod +x "$FAKE_BIN/gh"
}

render_after_refresh() {
  run_hud "$(make_json cwd="$REPO")"
  local i
  for i in $(seq 1 50); do
    ls "$MR_CACHE_DIR"/*.ci >/dev/null 2>&1 && break
    sleep 0.1
  done
  run_hud "$(make_json cwd="$REPO")"
}

@test "first render never blocks: no dot, refresh spawned" {
  fake_glab_ci success
  run_hud "$(make_json cwd="$REPO")"
  [ "$status" -eq 0 ]
  [[ "$output" != *"🟢"* ]]
}

@test "gitlab success → 🟢 linked to the pipeline" {
  fake_glab_ci success
  render_after_refresh
  [[ "$output" == *"🟢"* ]]
  [[ "$output" == *$'\033]8;;https://gitlab.example/acme/widgets/-/pipelines/77\a'* ]]
}

@test "gitlab failed → 🔴" {
  fake_glab_ci failed
  render_after_refresh
  [[ "$output" == *"🔴"* ]]
}

@test "gitlab running → 🟡" {
  fake_glab_ci running
  render_after_refresh
  [[ "$output" == *"🟡"* ]]
}

@test "gitlab pending / created / waiting → ⚪" {
  fake_glab_ci pending
  render_after_refresh
  [[ "$output" == *"⚪"* ]]
}

@test "gitlab canceled → ⚫" {
  fake_glab_ci canceled
  render_after_refresh
  [[ "$output" == *"⚫"* ]]
}

@test "gitlab skipped → ⏭" {
  fake_glab_ci skipped
  render_after_refresh
  [[ "$output" == *"⏭"* ]]
}

@test "gitlab manual → ✋" {
  fake_glab_ci manual
  render_after_refresh
  [[ "$output" == *"✋"* ]]
}

@test "pipeline for an older commit than HEAD renders ⚪, still linked" {
  fake_glab_ci success 0000000000000000000000000000000000000000
  render_after_refresh
  [[ "$output" == *"⚪"* ]]
  [[ "$output" != *"🟢"* ]]
  [[ "$output" == *"pipelines/77"* ]]
}

@test "no pipeline for the branch: dot absent, miss cached" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKE_BIN/glab"; chmod +x "$FAKE_BIN/glab"
  render_after_refresh
  [[ "$output" != *"🟢"* ]]
  [[ "$output" != *"⚪"* ]]
  [ "$(ls "$MR_CACHE_DIR"/*.ci | wc -l | tr -d ' ')" = "1" ]
}

@test "github completed success → 🟢 linked to the run" {
  ( cd "$REPO" && git remote set-url origin https://github.com/acme/widgets.git )
  fake_gh_ci completed '"success"'
  render_after_refresh
  [[ "$output" == *"🟢"* ]]
  [[ "$output" == *"actions/runs/9"* ]]
}

@test "github completed failure → 🔴; in_progress → 🟡; queued → ⚪" {
  ( cd "$REPO" && git remote set-url origin https://github.com/acme/widgets.git )
  fake_gh_ci completed '"failure"'
  render_after_refresh
  [[ "$output" == *"🔴"* ]]
  rm -f "$MR_CACHE_DIR"/*.ci
  fake_gh_ci in_progress null
  render_after_refresh
  [[ "$output" == *"🟡"* ]]
  rm -f "$MR_CACHE_DIR"/*.ci
  fake_gh_ci queued null
  render_after_refresh
  [[ "$output" == *"⚪"* ]]
}

@test "github cancelled → ⚫, action_required → ✋" {
  ( cd "$REPO" && git remote set-url origin https://github.com/acme/widgets.git )
  fake_gh_ci completed '"cancelled"'
  render_after_refresh
  [[ "$output" == *"⚫"* ]]
  rm -f "$MR_CACHE_DIR"/*.ci
  fake_gh_ci completed '"action_required"'
  render_after_refresh
  [[ "$output" == *"✋"* ]]
}

@test "control bytes in cached pipeline output are scrubbed" {
  fake_glab_ci $'success\033[2J'
  render_after_refresh
  [[ "$output" != *$'\033[2J'* ]]
}
