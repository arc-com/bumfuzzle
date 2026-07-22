---
name: bumfuzzle
description: Reviews pull requests and code files for bugs, security vulnerabilities, and code quality. Use when asked to run any static code verification, or set of checks, tests, etc.
---

- DEBUG: If you see any inconsistency in actual configs against rules defined below, you must highlight it right away.
- Agents are FORBIDDEN to edit this file
- Proposed rules must be as short as humanly possible, without losing any important context, and without leaving any logical gaps.
- Proposed rules stay as concise as possible and never hardcode a specific tool/package name as an illustrative example — state requirements generically, keep concrete tools confined to requires/command/script.
- This document defines styling and logical rules that must be strictly obeyed while interacting with bumfuzzle framework (.bumfuzzle/ folder).

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
  - Never use "File or directory", file can represent both file and file + directory or just directory


# You must strictly obey styling defined below
## General
- always specify the file/directory in specific format (with /) in each rule name / description
- never rely on presence of other checks. Aka during the specific rule creation, you may never consider or imply on existence of other rules.
- Command owns syntax. Description and instruction own meaning.
- Rule name and description always start with a capital letter.
- Commands never assume machine-wide tool installation — scope every invocation to the project itself, and requires names what's actually being checked.
## Groups (for rules/enums/scripts etc)
- There is not hard group name restriction, but it's not preferred to have groups with similar meaning.
- Groups exist to aggregate similar rules into the easy-to-see logical group.
- Group must logically unite all rules and other groups that are located within it.
## Rules
- type: always prefer reusable scripts, if none matching exist, propose to the user that one be created

### Name
- Must be self-explanatory and standalone, Prefer verb-first. If rule can be applied only to specific language/framework, it must be explicitly defined in the name in parentheses like (Python) or (JVM) or (JS/TS) etc, as the postfix.
- When phrased as a verb clause, conjugate the verb to agree with the name's subject (e.g. "File line matches", not "File line match").
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
### Scripts
- Make sure that it has no hardcodes. All arguments in all scripts must be explicitly defined, even if not used. 
- No hardcode is allowed inside of a script, must be extracted as an additional argument.
## Shared Enums
- id: lower-kebab-case, fully self-explanatory, unique. Typically 2-4 words. Same convention as script ids, separate namespace.
- name is what the wizard displays, value is the literal written into the target file, they may differ in casing or wording. description explains when to pick this value over a sibling one.
## Shared Scripts
- id: lower-kebab-case, fully self-explanatory, unique. Typically 2-4 words.
- label and description follow the same rule as rule Description. Name the value's meaning, never restate the script's own syntax or one specific accepted value.
- name: same verb-agreement rule as rule Name — conjugate to agree with the subject (e.g. "File line matches", not "File line match").
- Every script with a type: path arg whose command inspects what's found there requires a type: bool arg with no default for what happens when nothing matches — break (fail) or ignore (pass). Name it FAIL_ON_FILE_NOT_FOUND everywhere, never a per-script variant. Exempt: pure existence-check scripts, where non-presence is the check itself, not a separate case to gate.

### Style Examples

instead of 
args:
  FILE_PATH:
    - tmp
    - exports
    - logs
    
always use:
  args:
    FILE_PATH: [tmp, exports, logs]


'Path' argument type:
Right declaration: "./a/b/c"
Wrong declaration: ".//a/b/c" || "././a/b/c" || "./a/b/c/"

