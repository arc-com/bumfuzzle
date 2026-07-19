# Creating rules

How to add a rule to `bumfuzzle-template.yml` — the catalog the wizard reads to build a project's `bumfuzzle.yml`.

`schema.yml` is the full structural definition of this format — every node shape, every property, required-ness, and nesting — written in JSON Schema vocabulary. Every enumerated value referenced below (arg `type` → `$defs.argType.enum`, rule `type` → `$defs.ruleType.enum`, `severity` → `$defs.severity.enum`, `on_missing` → `$defs.onMissing.enum`, multi-select `separator` → `$defs.separator.enum`) is defined once there and read from there by the wizard (`index.html`) and the runner (`scripts/eval-rules.sh` / `scripts/validate-schema.sh`) — never hardcode one of these lists anywhere else. `bumfuzzle validate-schema` (and `bumfuzzle run`'s config lint phase) rejects any value not present in that file.

## Vocabulary

- **Script** — a reusable check definition, listed under top-level `scripts:` and grouped by domain (e.g. `Claude Settings`, `Git`, `Python`). Defines the shell `command:` and the `args:` it accepts.
- **Rule** — an instance of a script, listed under top-level `rules:` and grouped the same way. Supplies concrete `args:` values plus `severity` and `instruction`. This is what actually ends up enabled/disabled in a project's `bumfuzzle.yml`.
- **Enum** — a reusable list of named values, listed under top-level `enums:`. An enum-typed arg references one via `enum_ref`.

## Headers

### Script (`scripts:` → group → `scripts:`)

| field | required | notes |
|---|---|---|
| `id` | yes | kebab-case, unique across all scripts, locked after first save |
| `name` | yes | human-readable, shown in the wizard |
| `description` | yes | one sentence: what it checks, and the default it falls back to if relevant |
| `command` | yes | shell script; reads args as env vars |
| `args` | no | list of arg definitions — see below |

### Arg — an `args[]` entry has exactly one shape (`$defs.arg` in `schema.yml`)

| field | required | notes |
|---|---|---|
| `key` | yes | UPPER_SNAKE_CASE env var name — see naming rule below |
| `label` | yes | shown in the wizard |
| `type` | yes | one of `$defs.argType.enum` in `schema.yml` |
| `required` | yes | `true`/`false` |
| `enum_ref` | only if `type: enum` | id of an entry in `enums:` — see enum rule below |
| `description`, `placeholder`, `default`, `min`, `max`, `visible_when` | no | as applicable to the type |

Always declared fully inline on the script that uses it, even when another script needs the exact same shape — there is no shared/reusable arg-type mechanism, so a repeated shape (e.g. `FILE_PATH`, `REGEX_PATTERN`, `CLAUDE_SETTINGS_FILE`) is simply repeated at every call site.

### Enum (`enums:` → group → `enums:`)

| field | required | notes |
|---|---|---|
| `id` | yes | kebab-case, referenced from args via `enum_ref` |
| `name` | yes | human-readable |
| `description` | yes | what the values mean / where they come from |
| `values` | yes | list of `{ name, value, description }` |

### Rule (`rules:` → group → `rules:`)

| field | required | notes |
|---|---|---|
| `type` | yes | one of `$defs.ruleType.enum` in `schema.yml` (`script_reusable` to instantiate a catalog script via `script:`, or `script_clean` for a one-off inline `command:`) |
| `name` | yes | human-readable, shown in the wizard and in `bumfuzzle run` output |
| `description` | yes | what this specific instance enforces |
| `script` | only if `type: script_reusable` | `id` of the script being instantiated |
| `command` | only if `type: script_clean` | inline shell command, not shared with any script |
| `severity` | no, default `error` | one of `$defs.severity.enum` in `schema.yml` |
| `instruction` | no | what to tell the agent/dev to do on failure |
| `enabled` | no | gates whether `bumfuzzle run` evaluates this rule at all |
| `requires` | no | name of a binary that must be installed for this rule to run |
| `on_missing` | only if `requires` is set | one of `$defs.onMissing.enum` in `schema.yml`, default `warn` |
| `args` | no | map of `KEY: value` matching the script's arg keys (`script_reusable` only) |

A multi-value arg is always written flow-style, `KEY: [a, b, c]` — never as a multi-line `KEY:` block with `-` items. This is a formatting convention only (both parse to the same list, and the wizard always emits flow-style), not something `schema.yml`/`validate-schema.sh` can check — YAML surface syntax is gone by the time a document is parsed into JSON, so a schema-level rule structurally cannot see the difference.

## Rules for writing rules

### 1. Arg keys must be self-explanatory, not generic

An arg `key` used by only one script must not be a bare, ambiguous shell-variable name like `MODE`, `RULE`, `TOOL`, `KEY`, `VALUE`, `SETTING`, `EVENT`, `MODEL`. Prefix it with the domain the script belongs to so it reads unambiguously wherever it's used — in the command body, in the wizard, and in a rule's `args:` map.

Bad: `MODE`, `SETTINGS_FILE`
Good: `CLAUDE_PERMISSION_MODE`, `CLAUDE_SETTINGS_FILE`

This applies to args that are genuinely domain-specific to one script. It does **not** apply to a handful of names that recur across unrelated scripts and are already descriptive on their own (e.g. `FILE_PATH`, `REGEX_PATTERN`, `INCLUDE_FILES_GLOB`/`EXCLUDE_FILES_GLOB`, `CLAUDE_SETTINGS_FILE`) — keep those names as-is everywhere they're repeated; renaming one copy to fit its script's domain would make it inconsistent with every other copy of the same shape.

### 2. Enum values are never declared inline — only via a reusable enum

An arg with `type: enum` must set `enum_ref` pointing at an entry under `enums:`. There is no inline-values escape hatch for enum args (the wizard UI enforces this too — it only exposes `enum_ref`, not a way to type literal option values into an arg, inline or shared). Simple scalar types (`string`, `int`, `double`, `regex`, `path`, `bool`) are unaffected and keep their constraints (`placeholder`, `default`, `min`, `max`) declared inline as usual.

Bad: an enum arg with a hand-typed list of options on it
Good: `enum_ref: claude-permission-mode`, with the values defined once under `enums:`

### 3. Model a genuinely two-state choice as `type: bool`, not a two-value enum

If an arg's only job is to flip between two opposite behaviors (present/absent, match/no-match, fail/pass), make it a `bool` with a `description` spelling out what `true` and `false` each mean — not an `enum` with two named values. A two-value enum here is indirection with no payoff: there's no third value ever coming, and `enum_ref` adds a whole extra `enums:` entry to maintain for something a `default: true`/`false` says just as clearly.

Bad: `type: enum, enum_ref: match-value` with values `match`/`no_match`
Good: `key: FAIL_ON_VALUE_MISMATCH, type: bool, default: true, description: "true = fail when the value does not equal CLAUDE_SETTING_VALUE; false = fail when it does (forbidden)"`

Give each of these booleans its own key tailored to what that specific script checks — never reuse one generic match/presence name across multiple scripts (rule 1). Compare `FAIL_ON_ABSENCE` (`file-or-dir-existence`), `FAIL_ON_KEY_ABSENCE` (`json-path-exists`), `FAIL_ON_PATTERN_NOT_FOUND` (`file-line-contains`), `FAIL_ON_HOOK_MISMATCH` (`claude-hook-command`) — same underlying true/false shape, fifteen different names, one per script.
