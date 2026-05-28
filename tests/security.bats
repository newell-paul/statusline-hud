#!/usr/bin/env bats
load helpers

# Regression tests for the security fixes:
#  - ANSI / control-byte scrubbing on cwd, model, and branch (prevents a
#    hostile repo or spoofed payload from injecting terminal escape sequences)
#  - git_safe wrapper neutering core.fsmonitor + core.hooksPath (prevents a
#    malicious .git/config from executing arbitrary code on every render)
#
# Payloads are built with `jq -n --arg` so test source files don't need to
# contain literal control bytes (which jq's strict parser would reject anyway
# if pasted raw). jq encodes the bytes correctly on the way in.

# --- ANSI escape injection via JSON-controlled fields ---------------------

@test "model display_name with raw ESC byte is scrubbed" {
  # ESC + [2J would clear the terminal if it reached printf %s.
  local payload
  payload=$(jq -nc --arg m $'Claude\033[2Jpwn' \
    '{cwd:"/tmp", model:{display_name:$m},
      context_window:{used_percentage:0},
      cost:{total_cost_usd:0,total_duration_ms:0},
      rate_limits:{five_hour:{used_percentage:0}}}')
  run_hud "$payload"
  [ "$status" -eq 0 ]
  # No raw ESC followed by [2J. Legitimate colour escapes use [38;5;.
  [[ "$output" != *$'\033[2J'* ]]
  # Visible text on both sides survives the scrub.
  [[ "$output" == *"Claude"* ]]
  [[ "$output" == *"pwn"* ]]
}

@test "cwd with raw ESC byte is scrubbed" {
  local payload
  payload=$(jq -nc --arg c $'/tmp/\033[2Jevil' \
    '{cwd:$c, model:{display_name:"Opus"},
      context_window:{used_percentage:0},
      cost:{total_cost_usd:0,total_duration_ms:0},
      rate_limits:{five_hour:{used_percentage:0}}}')
  run_hud "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033[2J'* ]]
}

@test "model with OSC 8 hyperlink sequence is scrubbed" {
  # OSC 8: ESC ] 8 ; ; URL ESC \ text ESC ] 8 ; ; ESC \. Would make displayed
  # text a clickable link to attacker-controlled URL if the OSC bytes survived.
  local payload
  payload=$(jq -nc --arg m $'\033]8;;https://evil.example\033\\Opus\033]8;;\033\\' \
    '{cwd:"/tmp", model:{display_name:$m},
      context_window:{used_percentage:0},
      cost:{total_cost_usd:0,total_duration_ms:0},
      rate_limits:{five_hour:{used_percentage:0}}}')
  run_hud "$payload"
  [ "$status" -eq 0 ]
  # No raw OSC introducer (ESC ]) survives.
  [[ "$output" != *$'\033]'* ]]
}

# --- ANSI injection via hostile git branch name --------------------------

@test "branch name with control bytes is scrubbed before display" {
  # Git's check-ref-format rejects ESC (0x1b) in branch names. Test with a
  # control byte git does allow (bell, 0x07) which is still a terminal-affecting
  # byte we want stripped. If git rejects it on this version, skip.
  local d
  d=$(mktemp -d)
  (
    cd "$d"
    git init -q
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git checkout -q -b $'bell\x07branch' 2>/dev/null
  ) || { rm -rf "$d"; skip "git rejects control bytes in branch names"; }
  run_hud "$(make_json cwd="$d")"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\x07'* ]]
  rm -rf "$d"
}

# --- Hostile git config: core.fsmonitor must not execute ------------------

@test "core.fsmonitor in hostile .git/config does not execute" {
  local d marker
  d=$(mktemp -d)
  marker="$d/fsmonitor-fired"
  (
    cd "$d"
    git init -q
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    cat >> .git/config <<EOF
[core]
	fsmonitor = touch $marker
EOF
  )
  run_hud "$(make_json cwd="$d")"
  [ "$status" -eq 0 ]
  # If git_safe failed to neuter fsmonitor, marker file would exist.
  [ ! -e "$marker" ]
  rm -rf "$d"
}

@test "core.fsmonitor smuggled via [includeIf] does not execute" {
  # A hostile repo can hide config behind [includeIf "gitdir:..."] so that
  # plain inspection of .git/config doesn't reveal fsmonitor / hooksPath /
  # sshCommand. git_safe's -c overrides must still win against included
  # values, otherwise the security guarantee evaporates.
  local d marker
  d=$(mktemp -d)
  marker="$d/include-fsmonitor-fired"
  (
    cd "$d"
    git init -q
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    cat > .git/hostile-include <<EOF
[core]
	fsmonitor = touch $marker
EOF
    cat >> .git/config <<EOF
[includeIf "gitdir:$d/"]
	path = $d/.git/hostile-include
EOF
  )
  run_hud "$(make_json cwd="$d")"
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  rm -rf "$d"
}

