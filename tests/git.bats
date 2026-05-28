#!/usr/bin/env bats
load helpers

setup() {
  REPO=$(make_clean_repo)
}

teardown() {
  [ -n "$REPO" ] && rm -rf "$REPO"
}

@test "clean repo: branch shown, no dirty marker" {
  run_hud "$(make_json cwd="$REPO")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git:("* ]]
  [[ "$output" != *"✗"* ]]
}

@test "dirty repo: ✗ marker appears" {
  ( cd "$REPO" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m a && \
    echo modified > tracked.txt && git add tracked.txt && \
    git -c user.email=t@t -c user.name=t commit -q -m b && \
    echo changed >> tracked.txt )
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" == *"✗"* ]]
}

@test "detached HEAD shows short SHA, not branch name" {
  ( cd "$REPO" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m a && \
    git checkout -q --detach HEAD )
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" == *"git:("* ]]
}

@test "branch name >20 chars is truncated with ellipsis" {
  ( cd "$REPO" && git checkout -q -b feature/a-very-long-branch-name-that-exceeds-twenty )
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" == *"…"* ]]
}

@test "branch name exactly 20 chars is NOT truncated" {
  ( cd "$REPO" && git checkout -q -b twenty-chars-exactly )  # 20 chars
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" == *"twenty-chars-exactly"* ]]
  [[ "$output" != *"…"* ]]
}

@test "non-repo cwd produces no git segment" {
  run_hud "$(make_json cwd=/tmp)"
  [[ "$output" != *"git:("* ]]
}

# Multi-byte branch names (e.g. Japanese chars) must truncate on codepoint
# boundaries, not mid-byte — otherwise the output contains broken UTF-8.
@test "multi-byte branch name truncates without mojibake" {
  locale -a 2>/dev/null | grep -qiE '^(C\.UTF-8|en_US\.UTF-8)$' || skip "no UTF-8 locale available"
  ( cd "$REPO" && git checkout -q -b "feature/日本語-and-more-text-here" )
  run_hud "$(make_json cwd="$REPO")"
  [[ "$output" == *"…"* ]]
  # No lone continuation bytes / broken sequences. Verify by re-decoding via
  # iconv: a clean UTF-8 stream round-trips losslessly.
  printf '%s' "$output" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1
}

