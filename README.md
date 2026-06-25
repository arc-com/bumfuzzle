<div align="center">

# 🌀 Bumfuzzle

**Constitutional linter for your codebase and AI agents.**  
Structure as law, not vibes.

[![Version](https://img.shields.io/badge/version-1.0-blue)](https://github.com/arc-com/bumfuzzle/releases)
[![License](https://img.shields.io/github/license/arc-com/bumfuzzle)](LICENSE)
[![Stars](https://img.shields.io/github/stars/arc-com/bumfuzzle?style=flat)](https://github.com/arc-com/bumfuzzle/stargazers)

<!-- DEMO: replace with asciinema cast or GIF -->

</div>

---

> Your AI agent forgot its instructions and nuked important files — again.  
> A half-finished refactor left a prod landmine in the codebase.  
> `.env.template` drifted from `.env` three commits ago, and the agent ignored it.  
> Config broke because of yet another hardcoded value.

**Bumfuzzle won't allow it. Your project structure will never drift again.**

---

## Working with AI coding agents

Add one line to your `AGENTS.md`:

```
After finishing each feature, run: preflight
```

Or reference `BUMFUZZLE_SKILL.md` from your `AGENTS.md` for a full agent-facing instruction set.

When a check fails, preflight prints exactly what broke and how to fix it. The agent reads the hint, resolves the issue, and reruns — in a loop — until the board is clean.

---

## Table of contents

- [Why Bumfuzzle](#why-bumfuzzle)
- [Features](#features)
- [Install](#install)
- [How to use](#how-to-use)
- [How it works](#how-it-works)
- [Contributing](#contributing)

---

## Why Bumfuzzle

- **One config file for everything.** A single `bumfuzzle.yml` at your project root declares all rules. No fragmented configs across tools.
- **Wizard setup in seconds.** Run `bumfuzzle` in any project and configure every check visually — no YAML hand-editing required.
- **Zero prod footprint.** Bumfuzzle is a dev dependency. It is never included in your build.
- **Works everywhere.** Any language, any framework, any OS. Any project size.

---

## Features

- **Out-of-the-box integrations.** Whatever stack you use, bumfuzzle validates the structural invariants that are universal: config drift, missing files, stale hooks, undeclared env vars.
- **Deterministic and side-effect-free.** `preflight` reads and checks. It never writes, installs, or modifies state. Same inputs, same output, every time.
- **Fast, simple, universal.** One YAML file. Three commands. No pipeline integration required. Works with any IDE, terminal, or agent harness.
- **Pre-configured presets, fully customizable.** Choose a preset (`backend`, `node`, `python`, `web`, and more) that enables the right checks for your project type. Disable anything, extend with your own rules via `command_checks`.
- **File and directory presence checks.** Ensure required files exist — or don't. Hooks, `AGENTS.md`, config files, any artifact your project depends on.
- **Env file consistency.** Catches `.env` ↔ `.env.template` drift: missing keys, undeclared keys, blank values, vars used in configs but never declared in template.
- **Custom grep checks.** Use `command_checks` to flag hardcoded IP addresses, API keys, or any pattern that doesn't belong outside your config files.

---

## Install

### Homebrew

```bash
brew install bumfuzzle
```

### Package managers

```bash
pnpm add -D bumfuzzle
npm install -D bumfuzzle
yarn add -D bumfuzzle

pip install bumfuzzle
uv add --dev bumfuzzle
poetry add --group dev bumfuzzle
```

### From source

```bash
git clone https://github.com/arc-com/bumfuzzle ~/.local/share/bumfuzzle
bash ~/.local/share/bumfuzzle/setup.sh
```

Adds `kickstart`, `bumfuzzle`, and `preflight` to `~/.local/bin`.

---

## How to use

### Path A — visual (`bumfuzzle`)

```bash
cd my-project
bumfuzzle
# → opens web wizard in browser; configure checks, environments, stacks, rules
# → save → bumfuzzle.yml written to project root
preflight
# → runs all checks; exits 0 or 1
```

### Path B — fast (`kickstart`)

```bash
cd my-project
kickstart
# → detects project type from manifests; scaffolds files and dirs; writes bumfuzzle.yml
# → edit bumfuzzle.yml directly, or run bumfuzzle to open the wizard later
preflight
# → runs all checks; exits 0 or 1
```

### Every subsequent run

```bash
preflight              # run all checks
preflight --verbose    # show passing checks too
preflight --env prod   # scope to one environment
```

`preflight` also runs automatically on every `git commit` via the pre-commit hook installed by `kickstart`.

Manage your rules two ways: run `bumfuzzle` for the visual wizard, or edit `bumfuzzle.yml` directly. `kickstart` is safe to rerun — it never deletes or overwrites. `preflight` is read-only. Both are idempotent.

---

## How it works

`bumfuzzle` is a single self-contained HTML file served by a lightweight local Python server. It shuts down when you close the tab. Nothing leaves your machine.

`bumfuzzle.yml` is the only config file created in your project. One file, all rules.

`preflight` only reads, never writes. `kickstart` only creates, never overwrites. They are symmetric: if you declare a file as expected, `kickstart` creates it and `preflight` checks it.

---

## Contributing

Open an issue: [github.com/arc-com/bumfuzzle/issues](https://github.com/arc-com/bumfuzzle/issues)
