#!/usr/bin/env bash
# SessionStart and UserPromptSubmit hook. With SESSION_TITLE=branch in
# ~/.claude/statusline-hud.conf it names the session after the current git
# branch, and renames it on the next prompt after the branch changes. A title
# set by hand (/rename, --name) is left alone: the hook only replaces a title
# it set itself, remembered per session. Off by default.
set -u

# ─── CONFIG ─────────────────────────────────────────────────────────────────
SESSION_TITLE=off       # off | branch
HUD_CONF=~/.claude/statusline-hud.conf
# shellcheck source=/dev/null
[ -f "$HUD_CONF" ] && . "$HUD_CONF" >/dev/null 2>&1
# ─────────────────────────────────────────────────────────────────────────────

[ "$SESSION_TITLE" = branch ] || exit 0
command -v jq >/dev/null || exit 0
input=$(cat)
{ IFS= read -r event; IFS= read -r session; IFS= read -r cwd; IFS= read -r current; } < <(
  jq -r '.hook_event_name // "", .session_id // "", .cwd // "", .session_title // ""' <<<"$input" 2>/dev/null)
case "$event" in SessionStart|UserPromptSubmit) ;; *) exit 0 ;; esac
# The id names a state file, so only a plain id is accepted.
case "$session" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
[ -d "$cwd" ] || exit 0

# Same guard as statusline-hud.sh: a hostile .git/config must not run code.
branch=$(git -C "$cwd" -c core.fsmonitor=false -c core.hooksPath=/dev/null \
  symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 0
[ -n "$branch" ] || exit 0

data="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/statusline-hud}/titles"
mkdir -p "$data" 2>/dev/null || exit 0
ours=$(cat "$data/$session" 2>/dev/null)
[ -n "$current" ] && [ "$current" != "$ours" ] && exit 0
[ "$current" = "$branch" ] && exit 0

printf '%s' "$branch" > "$data/$session"
find "$data" -type f -mtime +30 -delete 2>/dev/null
jq -cn --arg event "$event" --arg title "$branch" \
  '{hookSpecificOutput: {hookEventName: $event, sessionTitle: $title}}'
