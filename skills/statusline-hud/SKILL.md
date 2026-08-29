---
name: statusline-hud
description: Install, configure, preview, or uninstall the statusline-hud status line for Claude Code — one line with git, MR/PR badge, pipeline dot, model + effort, context / 5h / 7d bars. Triggers on "install statusline", "set up statusline", "configure statusline", "preview statusline", "uninstall statusline", "/statusline-hud".
---

# statusline-hud

The script lives at `${CLAUDE_PLUGIN_ROOT}/statusline-hud.sh`. Plugins cannot set `statusLine`, and `${CLAUDE_PLUGIN_ROOT}` is not expanded in `statusLine.command`, so this skill symlinks `~/.claude/statusline-hud.sh` to the plugin copy and points `settings.json` at the symlink. A SessionStart hook re-points the symlink after `/plugin update`. User settings go in `~/.claude/statusline-hud.conf`, which the script sources after its CONFIG block.

- "preview" / "what does it look like" → run `bash "${CLAUDE_PLUGIN_ROOT}/statusline-hud.sh" --demo` and show the output. No install needed.
- "uninstall" → [Uninstall](#uninstall)
- "configure" / "change colours" / "hide a segment" / "nerd font" → [Configure](#configure)

## Install

### 1. Preflight

```
command -v jq >/dev/null && echo OK || echo MISSING
```
If `MISSING`, offer to install it: `brew install jq` (macOS), `sudo apt install jq` (Debian/Ubuntu), `sudo dnf install jq` (Fedora). Ask before running; stop if declined.

If `~/.claude/settings.json` does not exist, stop — Claude Code hasn't been initialised; don't create it.

### 2. Link the script

```
[ -f ~/.claude/statusline-hud.sh ] && [ ! -L ~/.claude/statusline-hud.sh ] && mv ~/.claude/statusline-hud.sh ~/.claude/statusline-hud.sh.bak.$(date +%s)
ln -sfn "${CLAUDE_PLUGIN_ROOT}/statusline-hud.sh" ~/.claude/statusline-hud.sh
```

If a backup was made from a pre-plugin install, show `diff <(sed -n '/─── CONFIG/,/^# ────/p' ~/.claude/statusline-hud.sh.bak.*) <(sed -n '/─── CONFIG/,/^# ────/p' ~/.claude/statusline-hud.sh)` and offer to carry any changed assignments into the conf file in step 3.

### 3. Create the conf file (if absent)

```
[ -f ~/.claude/statusline-hud.conf ] || cat > ~/.claude/statusline-hud.conf <<'EOC'
# statusline-hud overrides — sourced after the CONFIG block in
# ~/.claude/statusline-hud.sh. Any assignment from that block works here.
# SEGMENTS=(dir git mr ci model ctx rl5 rl7 lines)
# NERD_FONT=1
# TURN_UNIT=tokens
EOC
```

### 4. Check settings.json

```
jq empty ~/.claude/settings.json
```
If that fails, stop — don't edit a broken file.

```
jq -e '.statusLine.command == "~/.claude/statusline-hud.sh"' ~/.claude/settings.json >/dev/null
```
Exit 0 → skip step 5, report "settings already correct".

If `.statusLine` exists but points elsewhere, show `jq '.statusLine' ~/.claude/settings.json` and ask before overwriting. Stop if declined.

### 5. Wire it in

```
cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%s)
jq '.statusLine = {type: "command", command: "~/.claude/statusline-hud.sh", refreshInterval: 30}' \
  ~/.claude/settings.json > ~/.claude/settings.json.tmp \
  && jq empty ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

`refreshInterval: 30` re-renders on a timer so the git and MR/PR segments don't go stale while the session idles. Drop it if the user prefers event-only refresh.

### 6. Report

```
✓ ~/.claude/statusline-hud.sh   → plugin (symlink)
✓ ~/.claude/statusline-hud.conf [created / kept]
✓ settings.json                 [updated / already correct]
→ Open a new Claude Code session to see the bar.
```

Mention: the `ci` segment needs `glab` (GitLab) or `gh` (GitHub) on PATH and hides itself otherwise; plugin updates apply at the next session start with no action needed.

## Configure

Never edit `~/.claude/statusline-hud.sh` — it's a symlink into the plugin. Edit `~/.claude/statusline-hud.conf`. To find a setting, read the CONFIG block:

```
sed -n '/─── CONFIG/,/^# ────/p' ~/.claude/statusline-hud.sh
```

Append the assignment to the conf file with its new value. Common requests:

| Request | Assignment |
|---|---|
| hide / reorder segments | `SEGMENTS=(dir git mr ci model ctx rl5 rl7 lines session worktree cache turn)` — omit names to hide |
| show the 🔥 spend | add `turn` to `SEGMENTS`; `TURN_UNIT=usd` or `tokens`; `TURN_RATE=0` drops the `($/h)` burn rate |
| show the cache ratio | add `cache` to `SEGMENTS` |
| session name / worktree | add `session` and/or `worktree` to `SEGMENTS` |
| Nerd Font glyphs instead of emoji | `NERD_FONT=1` (Octocat / tanuki prefixes, coloured pipeline icons) |
| cache expiry countdown | `CACHE_EXPIRY_WARN_MIN=10` — minutes; `0` hides |
| separator | `SEP_CHAR=" | "` |
| bare MR/PR numbers | `MR_PREFIX_GITLAB="!"` `MR_PREFIX_GITHUB="#"` |
| underline MR links | `MR_LINK_STYLE=4` |
| bar colour tiers | `BAR_CTX=(30 50 60)` `BAR_LINEAR=(60 80 95)` `TIER_COLOR=(46 226 214 196)` |
| a custom segment | define `seg_<name>() { printf "..."; }` in the conf and add `<name>` to `SEGMENTS` |

Custom segments are plain bash functions; the conf is sourced, so anything goes:

```bash
seg_k8s() { printf "\033[38;5;39m⎈ %s\033[0m" "$(kubectl config current-context 2>/dev/null)"; }
SEGMENTS=(dir git k8s model ctx rl5)
```

Colours are xterm-256 indices except `C_TURN_*` / `C_CACHE_*`, which are 16-colour SGR codes. Verify with `bash ~/.claude/statusline-hud.sh --demo` — a non-zero exit or an error line means a syntax error in the conf.

## Uninstall

```
rm -f ~/.claude/statusline-hud.sh ~/.claude/statusline-hud.conf
cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%s)
jq 'del(.statusLine)' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
  && jq empty ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

Ask before removing the conf file if it has uncommented lines. Then `/plugin uninstall statusline-hud@statusline-hud` if they also want the plugin gone.

## If the bar goes blank or shows wrong values

The jq extraction uses fallback paths for renamed fields, but the payload schema does change between Claude Code versions.

1. Capture a live payload: set `statusLine.command` to `bash -c 'cat > /tmp/sl.json'`, send one message, then `jq . /tmp/sl.json`.
2. Compare against the fields below and open an issue at https://github.com/newell-paul/statusline-hud with the diff.

Fields consumed:

| Segment | JSON path |
|---|---|
| dir | `.workspace.current_dir` (fallback `.cwd`) |
| model | `.model.display_name` (fallback `.model.name`), `.effort.level`, `.fast_mode`, `.thinking.enabled` |
| ctx | `.context_window.used_percentage` |
| rl5 / rl7 | `.rate_limits.five_hour.*` / `.rate_limits.seven_day.*` — `used_percentage`, `resets_at` |
| lines | `.cost.total_lines_added`, `.cost.total_lines_removed` |
| session | `.session_name` |
| worktree | `.workspace.git_worktree` (fallback `.worktree.name`) |
| cache | `.prompt_cache.hit_ratio`, `.prompt_cache.warm`, `.prompt_cache.expires_at` (fallback: `.context_window.current_usage.cache_read_input_tokens` ÷ `.context_window.total_input_tokens`) |
| turn | `.cost.total_cost_usd`, `.cost.total_duration_ms`, or `.context_window.total_input_tokens` |
| mr | `.pr.number`, `.pr.url`, `.pr.review_state`, `.pr.kind` (≥ 2.1.234); falls back to `glab`/`gh` when absent |
| git / ci | not from stdin — `git`, `glab`, `gh` against `.workspace.current_dir` |
