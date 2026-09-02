#!/usr/bin/env bash
# SessionStart hook. ~/.claude/statusline-hud.sh is a symlink into the plugin
# cache; re-point it after /plugin update so settings.json never changes. A
# regular file there is a hand-installed copy and is left alone. If nothing is
# wired up yet, nudge once (stdout lands in Claude's context).
set -u
src="${CLAUDE_PLUGIN_ROOT:-}/statusline-hud.sh"
dst="$HOME/.claude/statusline-hud.sh"
[ -f "$src" ] || exit 0
for name in statusline-hud.sh subagent-statusline.sh; do
  link="$HOME/.claude/$name"
  [ -L "$link" ] && [ "$(readlink "$link")" != "${CLAUDE_PLUGIN_ROOT:-}/$name" ] && ln -sfn "${CLAUDE_PLUGIN_ROOT:-}/$name" "$link"
done
[ -e "$dst" ] && exit 0
grep -qs statusline-hud "$HOME/.claude/settings.json" && exit 0
data="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/statusline-hud}"
mkdir -p "$data" 2>/dev/null
[ -e "$data/nudged" ] && exit 0
: > "$data/nudged"
echo "statusline-hud is installed but not wired up yet. Run /statusline-hud to set it up, or 'bash $src --demo' to preview it."
