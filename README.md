<div align="center">

# 🦝 Bumfuzzle: Starting Point for Every Project

<p align="center">
    <picture>
        <img src="./public/bumfuzzle.png" alt="Bumfuzzle" width="500">
    </picture>
</p>

<p align="center">
  <strong>Complete Rules Engine for enforcing conventions.</strong>
</p>

<p align="center">
  <a href="https://github.com/arc-com/bumfuzzle/actions/workflows/ci.yml?branch=main"><img src="https://img.shields.io/github/actions/workflow/status/arc-com/bumfuzzle/ci.yml?branch=main&style=for-the-badge" alt="CI status"></a>
  <a href="https://github.com/arc-com/bumfuzzle/releases"><img src="https://img.shields.io/github/v/release/arc-com/bumfuzzle?include_prereleases&style=for-the-badge" alt="GitHub release"></a>
  <a href="https://discord.gg/REPLACE_ME"><img src="https://img.shields.io/badge/-Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/arc-com/bumfuzzle?style=for-the-badge" alt="License"></a>
</p>

<!-- DEMO: replace with asciinema cast or GIF -->

</div>

---

> [!CAUTION]
> Now you can bash the soul out of your coding agent.<br>
> And it will never break a rule again.

---

## Summary

- `bumfuzzle` is a single self-contained HTML file served by a lightweight local Python server. It shuts down when you close the tab. Nothing leaves your machine.
- `bumfuzzle.yml` is the only config file created in your project. One file, all rules.
- `bumfuzzle run` runs every check marked `enabled` in `bumfuzzle.yml`. The file itself is created on demand from the wizard's "Create config" button.

---

## Working with AI coding agents

It works perfectly with **Cursor**, **Claude Code**, **Codex**, and many more.

Models: Opus 4.8, Sonnet 5, Fable 5, GPT 5.5, GLM 5.2, and many more.

When a check fails, `bumfuzzle run` prints exactly what broke and how to fix it. The agent reads the hint, resolves the issue, and reruns, in a loop, until the board is clean.

---

## Table of contents

- [Features](#features)
- [Install](#install)
- [How to use](#how-to-use)
- [Roadmap](#roadmap)
- [Comparison](#comparison)
- [Contributing](#contributing)

---

## Features

- **Closes the agentic verification loop:** custom instructions tell the model exactly what to do next.
- **Extremely fast, ridiculously simple, and lightweight:** zero external dependencies.
- **Works with any language, any OS, any project:** from a personal website to the Linux kernel.
- **You pick the rules yourself:** linters, hooks, and virtually anything else.
- **One config to rule them all:** a single `bumfuzzle.yml` stores every configuration.
- **One entry point for every check:** the `bumfuzzle` command runs it all.
- **Visual Wizard:** set up every check you want in seconds.
- **Zero prod footprint:** Bumfuzzle is never included in your build.
- **Batteries included:** ships with most of the common presets, so you just pick what you need.

---

## Install

```bash
# Homebrew
brew install arc-com/tools/bumfuzzle

# Package managers
pnpm add -D bumfuzzle
npm install -D bumfuzzle
yarn add -D bumfuzzle

pip install bumfuzzle
uv add --dev bumfuzzle
poetry add --group dev bumfuzzle

# From source
git clone https://github.com/arc-com/bumfuzzle ~/.local/share/bumfuzzle
bash ~/.local/share/bumfuzzle/scripts/install.sh
```

Installing from source adds `bumfuzzle` and `bf` to `~/.local/bin`. Run `scripts/uninstall.sh` to remove them.

---

## How to use

```bash
cd my-project

bumfuzzle
# opens web wizard in browser
# click "Create config" to write bumfuzzle.yml from the template
# configure checks, environments, stacks, rules; autosaves as you edit

# Every subsequent run
bumfuzzle run              # run every check marked enabled in bumfuzzle.yml
bumfuzzle run --verbose    # show passing checks too
```

Manage your rules two ways: run `bumfuzzle` for the visual wizard, or edit `bumfuzzle.yml` directly. `bumfuzzle run` never takes a target — it runs whatever is `enabled`. A check may self-label `readonly: true` in `bumfuzzle.yml` as a hint to whoever's reading the config; the framework doesn't verify or enforce it.

---

## Roadmap

### Bug fixes
- [ ] Fix drag-and-drop crash when dropping a rule into an empty group

### Planned improvements
- [ ] Standardize argument-passing and argument-expectation conventions across shared scripts
- [ ] Support user-defined arguments in custom `command_checks` scripts
- [ ] Reduce `bumfuzzle.yml` size by extracting reusable rule sets into importable modules

---

## Comparison

How Bumfuzzle compares to other tools in the AI-agent-guardrail space:

| | Bumfuzzle | [agentlint](https://github.com/mauhpr/agentlint) | [agent-governance-toolkit](https://github.com/microsoft/agent-governance-toolkit) | [drift-guard](https://dev.to/hwaninet/how-i-built-drift-guard-a-cli-to-stop-ai-agents-from-destroying-your-design-3egc) | Plain `pre-commit` |
|---|---|---|---|---|---|
| Enforcement point | Git commit (pre-commit hook) | Real-time, tool-call time | Git commit (hook templates) | Git commit / CLI | Git commit |
| Config format | Single `bumfuzzle.yml` | Rule packs (JS/JSON config) | Docs + hook templates, no single schema | Zero-config | `.pre-commit-config.yaml` + per-hook config |
| Structural checks (files, dirs, env drift) | ✅ built-in | Partial (code-quality/security focus) | Governance/process focus, not file structure | Design/UI drift only | Only if you write custom hooks |
| Visual setup wizard | ✅ | ❌ | ❌ | ❌ | ❌ |
| Zero prod footprint | ✅ (dev dependency only) | ✅ | ✅ (docs/process, not shipped) | ✅ | ✅ |

_Comparisons above reflect public information about these projects as of July 2026 and may not capture every capability. Verify directly with each project before relying on this table._

---

## Contributing

Open an issue: [github.com/arc-com/bumfuzzle/issues](https://github.com/arc-com/bumfuzzle/issues)
