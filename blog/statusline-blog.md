---
status: draft
type: blog
updated: 2026-08-29
---

# Claude Code, Without Leaving the Terminal

*Version 2 of my take on the statusline *


I kept losing focus. Over to GitLab to see MR status. Over to the pipeline page. Into `/usage` to see how much of the five-hour window I had eaten up. Each one a small interruption and each one is a chance to lose where I was at.

Claude Code does surface some of this info. But it is easy to dismiss them without reading.
---

**TL;DR**

```
/plugin marketplace add newell-paul/statusline-hud
/plugin install statusline-hud@statusline-hud
/statusline-hud
```

`bash statusline-hud.sh --demo` shows you the whole thing before you wire anything.

---

## The JSON Hiding in the Statusline

Claude Code's statusline is just a shell command. JSON in on stdin, one line of text out.

And that JSON is fat. Model, effort, context usage, both rate-limit windows, cost, prompt-cache stats. Since 2.1.234 it even carries the open pull request or merge request for your branch. All of it lands on every render.

There's just nothing showing it.

## What the Bar Shows

![The default bar: git branch, GitLab MR !23 mergeable, a green pipeline dot, Sonnet 5 at high effort with thinking on, and the context, 5h and 7d bars](images/statusline-hud.png)

The left half is where you are. The right half is what it's costing you. But you can have it in any order you want and comment out what you do not need in the `segments` array - more on that later

**Where you are**

- Git: branch, `↑N↓N` ahead/behind, `✗` if dirty, then `+156 −23` lines changed this session
- MR/PR badge: `🦊 !23 ✓` or `🐙 #42 ✓`. Green tick when it's mergeable, red cross for conflicts, bare yellow while checks run, `✎` draft, `⇄` merged. Click it and the MR opens
- Pipeline dot: 🟢 🔴 🟡 for the latest run on your branch. ⚪ if that run is for an older commit than your HEAD, so you never trust a green that isn't about your code

**What it's costing you**

- Model, coloured by tier, with the effort badge (`⚡Lo` through `⚡Max`), 🚀 for `/fast`, 💭 for extended thinking
- Context-window bar
- 5-hour and 7-day rate-limit bars, with a reset countdown (`↺2h14m`) on whichever is more constrained once it passes 60%

The bars are five cells drawn in eighths, so they visibly move within a tier. Context flips colour earlier than the rate limits on purpose: a full context degrades Claude's answers long before it blocks you. 

**Off by default, one line to turn on**

- Cache hit ratio `↩97%`. Cyan `❄` when the cached prefix has gone cold; `❄4m` while it's warm but about to lapse. Send a message before then and Claude Code reuses the prefix instead of rewriting it, which on a long session is tens of thousands of tokens
- Session name and `⎇ worktree`, for when you run several sessions or a subagent wanders off
- The flame: `🔥 $5.64 ($3.20/h)`. More on that below

## Why not use claude-hud or ccstatusline instead?

I wrote the first version of this before I found out about other solutions. Both are good, and both have more GitHub stars than this will ever get. If you want to see which tools and subagents are running right now, claude-hud does that and I don't. If you want powerline arrows, gradients and a TUI to configure it, ccstatusline does that and I don't.

Here's what I wanted instead, and why I kept iterating on this one instead of adopting one of the others.

**One line.** Both of them default to more. claude-hud opens on two rows and grows; ccstatusline's showcase is a multi-row powerline. I hate a busy status. The bar sits under every prompt I type for the whole session, and if it needs a second row it has stopped being a status and become a dashboard. Everything in this HUD had to earn its place on one line.

**Forge links.** Neither shows your pipeline. claude-hud shows no PR at all; ccstatusline has a GitHub-only check count. This one shows the MR or PR state and the latest pipeline for GitLab and GitHub, and both are clickable so you go straight to the page.

**Footprint.** One 30 KB bash script.  No Node, no Bun, no `npx` cold start on every render, no call home to a usage API. It runs the same on a locked-down server, a colleague's laptop and a container. About 60ms a render.

The plugin install symlinks the script into `~/.claude/`, writes a starter conf, patches `settings.json`, and re-points itself after `/plugin update`. Add `"refreshInterval": 30` while you're there so the git and MR segments don't go stale while the session idles.

## The Whole Extension API

Every setting is a plain bash assignment in the `CONFIG` block, and the conf file overrides any of them. `SEGMENTS` is the control panel:

```bash
SEGMENTS=(dir git lines mr ci model ctx rl5 rl7 cache turn)   # everything on
SEGMENTS=(git model ctx rl5)                                  # minimal
```

That's it. A function and a name in a list. No runtime, no plugin API, no rebuild.

## The Flame, If You Want It

`🔥 $5.64 ($3.20/h)` is cumulative session spend from `cost.total_cost_usd`, with the burn rate alongside once the session is 30 seconds old. The total is what this session has cost. The rate is what the next hour will cost if you carry on as you are. Green under $5, amber to $20, red above, tuned for Max users. PAYG users paying list price should dial it down.

It's off by default. On Pro and Max the number is an estimate, not your bill, and I found the rate-limit bars answer the question I was actually asking.

But a dollar figure does something a percentage doesn't. You tend to notice when it goes into the red.

## Acting on What You See

- When the context bar goes amber start thinking about /compact unless you have compact set to auto.
- When the 5h bar goes amber, ask whether this task still needs Fable or Opus.
- Pin routine slash commands to `model: haiku`. Commit, lint, review-diff. None of these need Opus.
- Use subagents for delegation. They get a fresh context window, not your full history.
- When the `❄` countdown appears, send the next message rather than going for a coffee.
- When a session has done its job, `/clear` before the next task. `/compact` if you want to keep the thread.

---

The data was always there. Now you can see it.

---

The repo is at **[github.com/newell-paul/statusline-hud](https://github.com/newell-paul/statusline-hud)**. Issues and PRs welcome.
