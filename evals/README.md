# Evals

Behavioural tests for the `statusline-hud` skill, run with `claude plugin eval` (Claude Code ≥ 2.1.269). The bats suite in `tests/` proves the scripts render; these prove that a user's request reaches the skill and that the skill does the right thing.

| Case | Tag | Asserts |
|---|---|---|
| `preview-no-install` | smoke, preview | skill fires, runs `statusline-hud.sh --demo`, never touches settings.json, the conf, or the symlinks |
| `agent-rows-preview` | preview | skill fires, runs `subagent-statusline.sh --demo`, same no-side-effects check |
| `configure-hide-segment` | configure | answer is a `SEGMENTS=(…)` line with `cache` and without `rl7`, pointed at the conf file, not the script (LLM-judged) |
| `unrelated-plugin-request` | negative | an unrelated plugin request does **not** fire the skill |

The `preview` cases grant Bash so the demo can run. The eval sandbox refuses to grant Bash on a machine whose `~/.docker` contains symlinks (Docker Desktop's `cli-plugins/` and `bin/lib/` do), so on such a machine run the other cases only:

```sh
claude plugin eval . --tag configure --tag negative --runs 1 --ablation none
```

Full suite, with the no-plugin baseline arm, on a machine or CI runner without that constraint:

```sh
claude plugin eval . --allow-tools "Bash(bash:*)"
```

Iterating on a grader:

```sh
claude plugin eval . --case configure-hide-segment --runs 1 --ablation none --keep-temp
```

Results land in `evals/results/<timestamp>/` (gitignored): `aggregate-result.json` and a self-contained `report.html`.
