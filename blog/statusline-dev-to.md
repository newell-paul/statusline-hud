---
title: "Claude Code Has a Head-Up Display. You Just Have to Wire It Up"
published: false
description: "One bash script. Branch, merge request, pipeline, context and both rate limits on one line. Stop tabbing away to check things your terminal already knows."
tags: claude, cli, bash, productivity
---

*One bash script. Branch, merge request, pipeline, context and both rate limits on one line. Stop tabbing away to check things your terminal already knows.*

<!-- UPLOAD: blog/images/statusline-hud.png — alt: "Statusline HUD with the default segments" -->

I'll be honest, I was alt-tabbing a lot. Over to GitLab to see if the MR had gone green. Over to the pipeline page. Into `/usage` to see how much of the five-hour window I'd chewed through. Each one is a small interruption. Each one is a chance to lose the thread.

Claude Code does surface some of this. But the notices flash past and you dismiss them without reading. Attention loses to a number you can't see.

---

**TL;DR**

```
/plugin marketplace add newell-paul/statusline-hud
/plugin install statusline-hud@statusline-hud
/statusline-hud
```

Needs `jq`, a 256-colour terminal, macOS or Linux. `bash statusline-hud.sh --demo` shows you the whole thing before you wire anything. Manual install and every setting are in the **[README](https://github.com/newell-paul/statusline-hud)**.

---

## The JSON Hiding in the Statusline

Claude Code's statusline is just a shell command. JSON in on stdin, one line of text out.

And that JSON is fat. Model, effort, context usage, both rate-limit windows, cost, prompt-cache stats. Since 2.1.234 it even carries the open pull request or merge request for your branch. All of it lands on every render.

Nothing's missing. There's just nothing showing it.

## What the Bar Shows

Read it left to right. The left half is where you are. The right half is what it's costing you.

**Where you are**

- Directory and git: branch, `↑N↓N` ahead/behind, `✗` if dirty
- MR/PR badge: `🦊 !23 ✓` or `🐙 #42 ✓`. Green tick when it's mergeable, red cross for conflicts, bare yellow while checks run, `✎` draft, `⇄` merged. Cmd-click it and the MR opens
- Pipeline dot: 🟢 🔴 🟡 for the latest run on your branch. ⚪ if that run is for an older commit than your HEAD, so you never trust a green that isn't about your code

**What it's costing you**

- Model, coloured by tier, with the effort badge (`⚡Lo` through `⚡Max`), 🚀 for `/fast`, 💭 for extended thinking
- Context-window bar
- 5-hour and 7-day rate-limit bars, with a reset countdown (`↺2h14m`) on whichever is more constrained once it passes 60%
- Lines changed this session: `+156 −23`

The bars are five cells drawn in eighths, so they visibly move within a tier. Context flips colour earlier than the rate limits on purpose: a full context degrades Claude's answers long before it blocks you. A rate limit only bites at 100%.

**Off by default, one line to turn on**

- Cache hit ratio `↩97%`. Cyan `❄` when the cached prefix has gone cold; `❄4m` while it's warm but about to lapse. Send a message before then and Claude Code reuses the prefix instead of rewriting it, which on a long session is tens of thousands of tokens
- Session name and `⎇ worktree`, for when you run several sessions or a subagent wanders off
- The flame: `🔥 $5.64 ($3.20/h)`. More on that below

## Why Not claude-hud or ccstatusline?

Both are good, and both have more stars than this will ever get. If you want to see which tools and subagents are running right now, claude-hud does that and I don't. If you want powerline arrows, gradients and a TUI to configure it, ccstatusline does that and I don't.

Here's what I wanted instead, and why I wrote a third one.

**One line.** Both of them default to more. claude-hud opens on two rows and grows; ccstatusline's showcase is a multi-row powerline. I hate a busy status. The bar sits under every prompt I type for the whole session, and if it needs a second row it has stopped being a status and become a dashboard. Everything in this HUD had to earn its place on one line, and the cut list is longer than the segment list.

**Forge links.** Neither shows your pipeline. claude-hud shows no PR at all; ccstatusline has a GitHub-only check count. This one shows the MR or PR state and the latest pipeline for GitLab and GitHub, and both are Cmd-clickable. That's the whole "stop alt-tabbing" argument, and it's the half of the bar the others don't have.

**Footprint.** One 30 KB bash script and `jq`. No Node, no Bun, no `npx` cold start on every render, no call home to a usage API. It runs the same on a locked-down server, a colleague's laptop and a container. About 60ms a render, and 178 bats tests behind it.

The plugin install does what you'd expect: symlinks the script into `~/.claude/`, writes a starter conf, patches `settings.json`, and re-points itself after `/plugin update`. Add `"refreshInterval": 30` while you're there so the git and MR segments don't go stale while the session idles.

## The Whole Extension API

Every setting is a plain bash assignment in the `CONFIG` block, and the conf file overrides any of them. `SEGMENTS` is the control panel:

```bash
SEGMENTS=(dir git mr ci model ctx rl5 rl7 lines cache turn)   # everything on
SEGMENTS=(git model ctx rl5)                                  # minimal
```

And because the conf is sourced bash, a function in it is a segment:

```bash
seg_k8s() { printf "\033[38;5;39m⎈ %s\033[0m" "$(kubectl config current-context 2>/dev/null)"; }
SEGMENTS=(dir git k8s model ctx rl5 rl7)
```

That's it. A function and a name in a list. No runtime, no plugin API, no rebuild.

## The Flame, If You Want It

`🔥 $5.64 ($3.20/h)` is cumulative session spend from `cost.total_cost_usd`, with the burn rate alongside once the session is 30 seconds old. The total is what this session has cost. The rate is what the next hour will cost if you carry on as you are. Green under $5, amber to $20, red above, tuned for Max users. PAYG users paying list price should dial it down.

It's off by default. On Pro and Max the number is an estimate, not your bill, and I found the rate-limit bars answer the question I was actually asking.

But a dollar figure does something a percentage doesn't. You don't read it. You notice when it pegs into the red. The discomfort isn't financial, it's visible. Red doesn't mean stop. It means the next routine task is the one to drop to Sonnet for, or `/clear` and start fresh.

## Acting on What You See

Opus for architecture, complex debugging, ugly refactors. Sonnet for most everyday work. Haiku for routine commands.

- When the 5h bar goes amber, ask whether this task still needs Opus.
- Pin routine slash commands to `model: haiku`. Commit, lint, review-diff. None of these need Opus.
- Use subagents for delegation. They get a fresh context window, not your full history.
- When the `❄` countdown appears, send the next message rather than going for a coffee.
- When a session has done its job, `/clear` before the next task. `/compact` if you want to keep the thread.

---

The data was always there. Now you can see it.

---

The repo is at **[github.com/newell-paul/statusline-hud](https://github.com/newell-paul/statusline-hud)**. Issues and PRs welcome.
