---
name: bumfuzzle
description: Load it when working with Bumfuzzle, or when project has Bumfuzzle import. When you asked to create new rule, or trigger any validation or verification after task is done.
---

- DEBUG: If you see any inconsistency in actual configs against rules defined below, you must highlight it right away.
- Agents are FORBIDDEN to edit this file, except a specific line/section the user has explicitly named for edit in the current message.
- Proposed rules must be as short as humanly possible, without losing any important context, and without leaving any logical gaps.
- Proposed rules stay as concise as possible and never hardcode a specific tool/package name as an illustrative example. State requirements generically, keep concrete tools confined to requires/command/script.
- This document's own instructions never illustrate with a hardcoded example. State each rule generically, exactly like it requires of proposed rules.
- This document defines styling and logical rules that must be strictly obeyed while interacting with bumfuzzle framework (.bumfuzzle/ folder).
- When a convention applies to more than one field block below, duplicate it into every relevant block instead of centralizing it once. Each block must stay sophisticated and self-contained on its own.
- A convention about a specific field lives inside that field's own subsection, never as a top-level bullet framed as a condition on the field's name.
- Never use a dash, semicolon, or colon mid-sentence in any instruction or rule text authored in this document. Split into separate sentences instead.

# DICTIONARY
- Always instruction: an instruction written inside a SKILL.md file. Never call it a rule or anything else.
- Rule: an entity defined within bumfuzzle. Never call it anything else.

# WHEN TO USE BUMFUZZLE?
- Whenever the static check/validation has to run.
- When a task finishes, as its validation stage.

# HOW TO USE BUMFUZZLE?
- Scaffold with bumfuzzle init, configure with bumfuzzle wizard, verify with bumfuzzle run, wire run into pre-commit so it happens automatically.

# WHEN TO PROPOSE CRUD FOR BUMFUZZLE RULE?
- Whenever you find a gap, staleness, or duplication, and never leave it for later.

# HOW TO CRUD BUMFUZZLE RULES?
- Check for reuse first, obey every styling rule in this document for every field touched, and route the change through a proposal, never a direct edit.


- Naming conventions:
  - GROUP: names what its contents share in common. Prefer a specific label over a catch-all, a broad General group is fine when nothing narrower fits.
  - Description: never enumerate selected options
  - Never say "directory" or "dir". Say "folder" instead. A path value declares its own kind. Trailing / means folder, no trailing / means file. Never start a path with ./ or /. A real leading . (dotfile) is fine.


# You must strictly obey styling defined below
## General
- never rely on presence of other checks. Aka during the specific rule creation, you may never consider or imply on existence of other rules.
- Command owns syntax. Description and instruction own meaning.
- Rule name and description always start with a capital letter.
- Commands never assume machine-wide tool installation. Scope every invocation to the project itself, and requires names what's actually being checked.
## Groups (for rules/enums/scripts etc)
- There is not hard group name restriction, but it's not preferred to have groups with similar meaning.
- Groups exist to aggregate similar rules into the easy-to-see logical group.
- Group must logically unite all rules and other groups that are located within it.
- A rule/enum/script's name, format, and content must fall into exactly one group, its own, and no other. When it doesn't: propose a new group if none fits; propose merging groups if more than one fits equally; propose editing or removing a group if it no longer describes its own contents; propose moving the item if a better group already exists; propose editing or moving the rule/enum/script itself if the mismatch is its own scope, not the group's.
## Rules
- type: always prefer reusable scripts, if none matching exist, propose to the user that one be created

### Name
- Must be self-explanatory and standalone, Prefer verb-first. If rule can be applied only to specific language/framework, it must be explicitly defined in the name in parentheses naming that language/framework, as the postfix.
- Prefer the verb-first form starting with "Enforces", naming what the rule guarantees rather than a bare noun phrase or state description.
- When phrased as a verb clause, conjugate the verb to agree with the name's subject.
- If it scans a folder, recursively or flat, to find matching files, the rule's name must end with the "(SCAN)" postfix.
### Description
- If a flag change breaks this sentence, rewrite it.
- Never state in words what only command should own.
- Tool plus result. No paths, no flags, no syntax.
- Keep descriptions short and concise. Never use hardcoding on specific examples. Never justify or explain accepted arguments.
### Severity
- Severity lives in one field. Never restate urgency in words.
- Don't describe how bad a failure is. Severity already says so.
### Instructions
- Name the fix. Never the exact invocation.
- Point at the tool, not its flags.
- Say what to fix, not what to type.
### Requires
- requires names the exact binary checked with command -v, never a package name or a version string.
### On Missing
- on_missing chooses what happens when requires is absent. skip when the check is optional tooling, warn when it should nudge without blocking, fail when its absence should itself fail the rule at its declared severity.
### Mutative
- mutative marks a rule whose command edits or writes files instead of only checking them.
- The name must already make the mutation obvious on its own, mutative is a flag for tooling, not a substitute for a clear name.
- A mutative rule is only ever an alternative alongside its check-only counterpart, never the only way to run that tool.
### Args
- An arg value never hardcodes this project's own name, path, or identity as a stand-in for a requirement meant to hold for any project.
- Exempt is a rule whose entire subject is confirming this specific project's own tool is present or wired in, where naming it is the actual requirement, not an illustrative stand-in.
### Scripts
- Make sure that it has no hardcodes. All arguments in all scripts must be explicitly defined, even if not used. 
- No hardcode is allowed inside of a script, must be extracted as an additional argument.
- A command must never re-check a shape its arg's declared type already guarantees. That guarantee is enforced once, by the runner, as a run prerequisite before any command executes. Restating it inside a command is the hardcode this section forbids. It's a second copy of the same check that silently drifts out of sync the day the convention changes. See Argument Types for what each type already guarantees.
## Shared Enums
- id: lower-kebab-case, fully self-explanatory, unique. Typically 2-4 words. Same convention as script ids, separate namespace.
- name is what the wizard displays, value is the literal written into the target file, they may differ in casing or wording. description explains when to pick this value over a sibling one.
## Shared Scripts
- id: lower-kebab-case, fully self-explanatory, unique. Typically 2-4 words.
- label and description follow the same rule as rule Description. Name the value's meaning, never restate the script's own syntax or one specific accepted value.
- placeholder is UI hint text shown in an empty input, never an implicit default the command can rely on. It must itself be a value that passes the arg's own type validation, never an example the type forbids.
- name: same verb-agreement rule as rule Name. Conjugate to agree with the subject.
- Every script with a type: path arg whose command inspects what's found there requires a type: bool arg with no default for what happens when nothing matches. Name it FAIL_ON_FILE_NOT_FOUND everywhere, never a per-script variant, using break (fail) or ignore (pass) as its two outcomes. Pure existence-check scripts are exempt, where non-presence is the check itself, not a separate case to gate.
- An arg matching a concept declared in Shared Arg Names uses that exact key everywhere, never a per-script variant.

### Command
- If it scans a folder, recursively or flat, to find matching files, the script's name must end with the "(SCAN)" postfix. id stays lower-kebab-case and never carries this postfix.

## Shared Arg Names
- A recurring arg concept is the same kind of value, gated the same way, across more than one script. It gets exactly one canonical key, declared here once. Every script needing that concept reuses it verbatim, never a per-script variant.
- key: SCREAMING_SNAKE_CASE, same convention as any arg key.
- description: names the concept precisely enough that a script author recognizes their arg is this recurring concept, not something new.

## Argument Types
Every arg's type is declared, never inferred. Each type below is a complete, self-contained contract for a single value of that type. A command may only add checks that are specific to what it does, never restate what the type already covers.
- list: true is a cardinality modifier, not a type and not part of any type's contract below. It accepts a YAML list of whatever the declared type is instead of one, values OR'd together where the command matches against them.
### Path
- Folder: trailing /. File: no trailing /.
- Never starts with ./ or /. A literal leading . (dotfile) is fine.
- Always resolves to one exact folder or file, never an abstract stand-in for "current" or "any" location. Glob and regex are the only types allowed to express that kind of abstract or pattern-based location. A bare "." or a bare "/" is invalid for the same reason, on top of "/" already failing the leading-/ rule above.
- Declaring type: path is the enforcement. The runner rejects a leading ./ or / value, a bare ".", and confirms the trailing-/ shape, as a run prerequisite before the script's command ever executes. A command must never re-check or restate this itself.
- A command may still add checks of its own that this shape doesn't cover. Those stay in the command because they are specific to that script, not to the type.
### Glob
- Matched against a file's basename only, never its full path.
### Bool
- required: true, no default field. Every rule using it states its own answer, never inherits one.
- description states both outcomes verbatim, using "true = <effect>; false = <effect>".
### Int
- A bare non-negative integer, no unit suffix. description names what changes at its boundary values, if any.
### String
- An opaque, free-form value the schema does not interpret. description names its shape without restating the placeholder's exact syntax.
### Enum
- Never inline values on the arg itself. Always use enum_ref pointing at a Shared Enum id.
### Regex
- Passed to the matching engine as-is, unescaped by the schema.

## Formatting
- Write a multi-value YAML field as an inline bracketed list, never a multi-line block list.
