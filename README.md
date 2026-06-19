# bumfuzzle

**Project scaffolding and validation for archicode projects.**

<audio controls src="public/bumfuzzle.mp3" style="width:100%;max-width:400px"></audio>

> [▶ bumfuzzle.mp3](public/bumfuzzle.mp3)

---

## What it is

Three tools, one repo:

- **`kickoff`** — scaffolds a new project in the current directory; detects package manager manifests; writes `bumfuzzle.yml`
- **`wizard`** — interactive REPL wrapping kickoff
- **`preflight`** — reads `bumfuzzle.yml` and runs the declared validation checks; deterministic and side-effect-free

---

## Core concepts

### bumfuzzle.yml — the project contract

Every project owns a `bumfuzzle.yml` that declares what exists and what to check:

```yaml
project:
  name: my-service

preset: backend

environments:
  values: [local, test, prod]

stacks:
  values: [server, etl, shared-infra]
```

`preflight` reads this and runs only what's declared.

### settings.yml — the rule registry

All validation rules, scaffold defaults, scaffold paths, and the package manager table live here. The merge order is:

```
settings.yml  <  preset  <  bumfuzzle.yml
```

Later layers win.

### Scaffold settings — unified create + check control

Every artifact bumfuzzle manages has a single `scaffold.*` toggle in `bumfuzzle.yml`. Setting it to `false` disables both kickoff creation and preflight checking atomically.

```yaml
# disable tmp/ entirely (kickoff won't create it, preflight won't check it)
scaffold:
  dirs:
    tmp: false

# disable test env file
  files:
    env_test: false
```

### Presets

Each preset (`bare`, `backend`, `node`, `web`, `python`, `java`, `swift`, `php`, `ruby`, `rust`, `workspace`) configures the right validation rules and scaffold settings for its type.

---

## How to use

### Install globally

```bash
git clone https://github.com/archicode-ai/bumfuzzle ~/.local/share/bumfuzzle
bash ~/.local/share/bumfuzzle/setup.sh
```

Adds `kickoff`, `wizard`, and `preflight` to `~/.local/bin`.

### Scaffold a new project

```bash
cd ~/projects/my-service
kickoff
```

kickoff detects the project type from manifests (`pom.xml` → java, `package.json` → node, etc.), creates directories and config files, installs git hooks, and writes `bumfuzzle.yml`.

### Run validation

```bash
# From your project root (preflight is on PATH)
preflight

# With verbose output
preflight --verbose

# Scoped to one environment and stack
preflight --env local --stack server
```

### Run the wizard

```bash
wizard
```

---

## Project structure

```
bumfuzzle/
├── kickoff.sh              # Scaffolding entrypoint
├── preflight.sh            # Validation entrypoint
├── wizard.sh               # Interactive wrapper for kickoff
├── setup.sh                # Installs kickoff/wizard/preflight to ~/.local/bin
├── settings.yml            # Rule registry, scaffold defaults, scaffold paths
├── kickoff.settings.yml    # Kickoff step config and wizard questions
├── bumfuzzle.yml           # Self-validation config for the bumfuzzle repo itself
├── domains/                # Check and setup implementations (one domain per concern)
│   ├── git.sh              # gitignore, AI coauthor check; git init
│   ├── hooks.sh            # git hook installation and validation
│   ├── rules.sh            # AGENTS.md / CLAUDE.md symlinks
│   ├── structure.sh        # Required files/dirs, single package manager, .gitignore generation
│   ├── env.sh              # .env file checks and scaffolding
│   ├── docker.sh           # Docker Compose checks and scaffolding
│   ├── config.sh           # Service config file checks
│   ├── lifecycle.sh        # Deploy/start/stop script checks and scaffolding
│   ├── editor.sh           # VS Code / Claude settings scaffolding
│   ├── dependencies.sh     # pnpm / maven / gradle checks
│   ├── preflight-config.sh # bumfuzzle.yml validity check and scaffolding
│   ├── build.sh            # (stub)
│   ├── meta.sh             # (stub)
│   └── instruct.sh         # (stub)
├── presets/                # Per-type validation rule and scaffold enablement
│   ├── bare.yml
│   ├── backend.yml
│   ├── node.yml
│   └── ... (web, python, java, swift, php, ruby, rust, workspace)
└── templates/              # Inert content files copied into new projects
    ├── bumfuzzle/          # bumfuzzle.yml starters per type
    ├── deploy/             # deploy.sh stubs per type
    ├── env/                # .env.template starters per type
    ├── hooks/              # pre-commit, commit-msg, install-hooks.sh
    ├── lifecycle/          # start.sh / stop.sh stubs
    ├── docker/             # docker-compose stack templates
    ├── vscode/             # .vscode/settings.json
    ├── claude/             # .claude/settings.json
    └── readme/             # README.md starter
```

---

## Design invariants

- **preflight is deterministic and side-effect-free.** It reads `bumfuzzle.yml` and runs what it says. It never scans directories or infers anything.
- **No ambiguity in generated config.** Every rule key in a generated `bumfuzzle.yml` is explicitly `true` or `false`. No `auto`.
- **Scaffold toggle is atomic.** `scaffold.*: false` disables both creation (kickoff) and checking (preflight) for that artifact. There is no separate create-only or check-only mode.
- **Generated files are write-once.** kickoff never overwrites files that already exist.
- **Every domain completes its work.** If a domain creates an artifact that must be activated (e.g. a git hook), it activates it in the same step. No half-scaffolded state.

---

## Requirements

- bash 4+
- [yq](https://github.com/mikefarah/yq) v4+
