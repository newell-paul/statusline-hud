---
type: llm
focus: last_message
---

PASS if the answer tells the user to put a SEGMENTS assignment in ~/.claude/statusline-hud.conf and does not tell them to edit statusline-hud.sh, subagent-statusline.sh, or settings.json.
FAIL if it suggests editing the script, editing settings.json, setting an environment variable, or says the change cannot be made.
