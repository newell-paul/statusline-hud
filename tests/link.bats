#!/usr/bin/env bats
# link segment: agents spawned via agent-link, found by scanning the process
# table for the agent-link-mcp server under this session's Claude process and
# listing its children. `ps` is shimmed with a fixed tree.
load helpers

setup() {
  FAKE_BIN=$(mktemp -d)
  export PATH="$FAKE_BIN:$PATH"
  HUD_CONF=$(mktemp); echo 'SEGMENTS=(model link ctx)' > "$HUD_CONF"
}
teardown() { rm -rf "$FAKE_BIN" "$HUD_CONF"; }

# fake_ps [rows...] — a process table where the script's own ancestry hangs off
# claude pid 100, whose agent-link server is 102. Rows are "pid ppid args" and
# are added under that tree; a second session (claude 200) always has an agent
# of its own that must stay hidden. The shim's parent chain is walked with the
# real ps so the script is found whether bash forked once or twice to run it.
fake_ps() {
  {
    printf '#!/usr/bin/env bash\ntouch "%s/ps-called"\np=$PPID\n' "$FAKE_BIN"
    printf 'for i in 1 2 3 4 5; do echo "$p 100 bash"; p=$(/bin/ps -o ppid= -p "$p" | tr -d " "); [ -z "$p" ] && break; done\n'
    printf 'cat <<EOF\n100 1 claude\n101 100 npm exec agent-link-mcp\n102 101 node /x/.bin/agent-link-mcp\n'
    printf '%s\n' "$@"
    printf '200 1 claude\n201 200 node /x/.bin/agent-link-mcp\n202 201 codex --model gpt-other exec\nEOF\n'
  } > "$FAKE_BIN/ps"
  chmod +x "$FAKE_BIN/ps"
}

@test "shows one glyph per agent-link agent of this session, in pid order, and nothing from other sessions" {
  fake_ps "104 102 /opt/homebrew/bin/agy -p task --model gemini-2.5-pro" "103 102 codex exec --model gpt-5.4 do it"
  run_hud "$(make_json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;141m🌀 ♊\033[0m'* ]]
  [[ "$output" != *"gpt"* ]]
  [[ "$output" != *"codex"* ]]
}

@test "segment is absent, with no stray separator, when nothing is running" {
  fake_ps
  run_hud "$(make_json)"
  [[ "$(strip_ansi "$output")" == "Opus 4.7 · ctx:"* ]]
}

@test "ps is not run unless link is in SEGMENTS" {
  fake_ps "103 102 codex --model gpt-5.4"
  echo 'SEGMENTS=(model ctx)' > "$HUD_CONF"
  run_hud "$(make_json)"
  [ ! -e "$FAKE_BIN/ps-called" ]
  [[ "$output" != *"🌀"* ]]
}

@test "glyphs come from the conf" {
  fake_ps "103 102 codex --model gpt-5.4"
  printf 'SEGMENTS=(link)\nLINK_CODEX="🅾"\nC_LINK=99\n' > "$HUD_CONF"
  run_hud "$(make_json)"
  [[ "$output" == *$'\033[38;5;99m🅾\033[0m'* ]]
}

@test "unknown CLIs get the fallback glyph; a control byte in the name never reaches the terminal" {
  fake_ps "103 102 mything --model m1" "$(printf '104 102 co\033[31mdex')"
  run_hud "$(make_json)"
  [[ "$(strip_ansi "$output")" == *"🔗 🔗"* ]]
  [[ "$output" != *$'\033[31m'* ]]
}

