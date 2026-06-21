# Conventions

## Package Manager

Each client project root must declare exactly one package manager. Multiple package manager manifests in the same project root are not allowed.

Supported package managers:

| Manifest file(s) | gitignore fragment |
|---|---|
| `Package.swift` | — |
| `composer.json` | — |
| `Gemfile` | — |
| `Cargo.toml` | rust |
| `pyproject.toml` / `requirements.txt` | python |
| `package.json` | node |
| `pom.xml` / `build.gradle` / `build.gradle.kts` | java |

The `single_package_manager` preflight check enforces this invariant with `severity: hard-stop`. kickstart detects the same condition at scaffold time and warns + falls back to bare.

## Git Hooks

The `commit-msg` hook rejects any commit whose message contains a `Co-Authored-By: Claude` line (case-insensitive). The `pre-commit` hook gates config/YAML, Markdown, dotenv, and script changes behind explicit approval env vars, then runs `scripts/preflight.sh` (which reads `bumfuzzle.yml`).

## Domain Convention

Every discrete lifecycle concern (file creation, validation, teardown) must be implemented as a `domains/*.sh` file exporting `*_check()` and `*_setup()`. No lifecycle logic may live in template files or root scripts. Template files are inert content only — they contain no branching, no env reads, no conditionals. If a concern does not have both a creation side and a check side, the unused function must call `NOT_SUPPORTED`. Package manager detection intentionally exists in both `kickstart.sh` (sets project purpose, continues on multi-PM) and `domains/structure.sh` (hard-stops on multi-PM) — these behaviors differ by design and are not duplicates.

## Kickstart–Preflight Symmetry

If kickstart creates an artifact for a given project type, preflight must have a corresponding enabled check for it. If kickstart does not create an artifact, the corresponding rule must be explicitly disabled.

The `bumfuzzle.yml` template for each project type is the contract that makes this concrete: it must enable every rule whose artifact kickstart creates, and explicitly disable every rule whose artifact kickstart does not create. Disabled rules in a template are not noise — they are an explicit declaration that the artifact was not scaffolded.

A scaffold step must produce complete, immediately valid state. If a rule validates something kickstart creates, the scaffold step must finish the job — no manual step (running an install script, creating a stub file) should be needed before preflight passes on a freshly scaffolded project.

## Agent Interaction Convention

Never restate information the user provided in the current message. Do not describe back to the user what something does when they just told you what it does.

## No Destructive Commands

`rm`, `rmdir`, `mv`, `unlink`, `truncate`, and all other destructive shell commands are banned from every script in this repo. Temp files created via `mktemp` live in `/tmp` and are reclaimed by the OS — no explicit cleanup is needed or permitted.

## Framework Content Must Be Generic

No stack names, service names, or domain concepts that belong to a specific project may appear in `settings.yml`, templates, or domain scripts. A concept is project-specific if knowing what it is requires knowing what the project does — not merely what type it is (backend/frontend/workspace). Framework templates must be minimal and universally applicable.

## No Writes Outside `$PROJECT_DIR`

All scaffolding operations (`_setup()` functions, kickstart, wizard) must write exclusively within `$PROJECT_DIR`. `install-global-bumfuzzle.sh` is the sole named exception: it writes symlinks into `$HOME/.local/bin` by design and carries an explicit comment at the top stating this.

## One Source of Truth

Any value used by more than one component — valid preset names, lifecycle script names, exempt docker stacks, environment defaults, package manager definitions — must live in `settings.yml`. Duplicating it in domain scripts, templates, or wizard code is a bug. Domain code reads; `settings.yml` declares.

Concretely: preset names are derived from `presets/purpose/` filenames; lifecycle scripts from `settings.yml lifecycle.scripts`; exempt docker stacks from `settings.yml docker.config_exempt_stacks`; manifest→purpose mapping from `settings.yml project.package_managers[].purpose`; wizard choices from `settings.yml wizard.questions[].choices`. None of these values appear in domain code.

## Manifest-first, Label-free

Build capabilities are identified by manifest file presence only. Language and runtime names (java, python, node) are display-only hints in wizard output. They must never appear in logic paths, preset filenames, check conditions, or template selection. The manifest IS the type.

## Presets Only Enable

Files under `presets/manifest/` and `presets/purpose/` may only contain `enabled: true`. Non-universal checks default to `false` in `settings.yml`. No preset file may contain `enabled: false`.

## Kickstart is the Sole Detection Layer

Manifest scanning, package manager identification, environment enumeration, and project structure decisions are exclusively kickstart's responsibility. kickstart writes the result as explicit validated config into the generated `bumfuzzle.yml`. `preflight.sh` receives that output and runs it — it never performs detection.

## Purpose Drives Scaffolding; Manifests Drive Checks

kickstart uses purpose (`backend` / `frontend` / `workspace`) to select which template files to copy. kickstart uses detected manifests to decide which validation checks to pre-enable in the generated `bumfuzzle.yml`. These are separate, non-overlapping concerns that must never be conflated.

## Generated Files are Write-once

kickstart skips any file that already exists. After initial scaffold, files are owned entirely by the client project. The framework never re-generates, patches, or enforces file content.

## deploy.sh is a Purpose-typed TODO Scaffold

kickstart generates `scripts/deploy.sh` from `templates/deploy/<purpose>.sh`. The template contains inline TODO instructions appropriate to that purpose. No config injection. The client edits it directly.

## preflight.sh is Deterministic and Side-Effect-Free

`preflight.sh` reads `bumfuzzle.yml` and executes the declared checks. It never scans directories, probes manifests, detects environments, or writes files. Detection and config generation are kickstart's exclusive responsibility. Any logic that decides what checks to run must live in kickstart, not in preflight.

## No Ambiguity in Generated Config

Every validation rule key in a generated `bumfuzzle.yml` must be explicitly `true` or `false`. No `auto`, no conditional values, no runtime inference. If a rule's state cannot be determined at kickstart time, it must be set to `false`.
