# Creating rules

How to add a rule to `bumfuzzle-template.yml` — the catalog the wizard reads to build a project's `bumfuzzle.yml`.

## Vocabulary

- **Script** — a reusable check definition, listed under top-level `scripts:` and grouped by domain (e.g. `Claude Settings`, `Git`, `Python`). Defines the shell `command:` and the `args:` it accepts.
- **Rule** — an instance of a script, listed under top-level `rules:` and grouped the same way. Supplies concrete `args:` values plus `severity` and `instruction`. This is what actually ends up enabled/disabled in a project's `bumfuzzle.yml`.
- **Arg template** — a reusable arg definition, listed under top-level `arg-templates:`. A script references one via `arg_ref` instead of declaring `key`/`label`/`type`/etc. inline.
- **Enum** — a reusable list of named values, listed under top-level `enums:`. An enum-typed arg references one via `enum_ref`.

## Headers

### Script (`scripts:` → group → `scripts:`)

| field | required | notes |
|---|---|---|
| `id` | yes | kebab-case, unique across all scripts, locked after first save |
| `name` | yes | human-readable, shown in the wizard |
| `description` | yes | one sentence: what it checks, and the default it falls back to if relevant |
| `command` | yes | shell script; reads args as env vars |
| `args` | no | list of inline arg definitions and/or `- arg_ref: <id>` entries |

### Arg (inline, under a script's `args:`)

| field | required | notes |
|---|---|---|
| `key` | yes | UPPER_SNAKE_CASE env var name — see naming rule below |
| `label` | yes | shown in the wizard |
| `type` | yes | `string`, `int`, `double`, `regex`, `path`, `bool`, `enum` |
| `required` | yes | `true`/`false` |
| `enum_ref` | only if `type: enum` | id of an entry in `enums:` — see enum rule below |
| `description`, `placeholder`, `default`, `min`, `max`, `visible_when` | no | as applicable to the type |

### Arg template (`arg-templates:`)

Same fields as an inline arg, plus:

| field | required | notes |
|---|---|---|
| `id` | yes | kebab-case, referenced from scripts via `arg_ref` |

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
| `type` | yes | `script_reusable` |
| `name` | yes | human-readable, shown in the wizard and in `bumfuzzle run` output |
| `description` | yes | what this specific instance enforces |
| `script` | yes | `id` of the script being instantiated |
| `severity` | yes | `error` or `warn` |
| `instruction` | yes | what to tell the agent/dev to do on failure |
| `args` | no | map of `KEY: value` matching the script's arg keys |

## Rules for writing rules

### 1. Arg keys must be self-explanatory, not generic

An arg `key` that's local to one script must not be a bare, ambiguous shell-variable name like `MODE`, `RULE`, `TOOL`, `KEY`, `VALUE`, `SETTING`, `EVENT`, `MODEL`. Prefix it with the domain the script belongs to so it reads unambiguously wherever it's used — in the command body, in the wizard, and in a rule's `args:` map.

Bad: `MODE`, `SETTINGS_FILE`
Good: `CLAUDE_PERMISSION_MODE`, `CLAUDE_SETTINGS_FILE`

This applies to keys declared inline on a single script. It does **not** apply to arg templates that are genuinely shared across unrelated domains and are already descriptive on their own (e.g. `FROM`, `DEPTH`, `INCLUDE_FILES_GLOB`, `EXPECT`) — those stay as they are; renaming them to fit one caller's domain would make them misleading for every other caller.

### 2. Enum values are never declared inline — only via a reusable enum

An arg with `type: enum` must set `enum_ref` pointing at an entry under `enums:`. There is no inline-values escape hatch for enum args (the wizard UI enforces this too — it only exposes `enum_ref`, not a way to type literal option values into a script or arg template). Simple scalar types (`string`, `int`, `double`, `regex`, `path`, `bool`) are unaffected and keep their constraints (`placeholder`, `default`, `min`, `max`) declared inline as usual.

Bad: an enum arg with a hand-typed list of options on the script itself
Good: `enum_ref: claude-permission-mode`, with the values defined once under `enums:`
