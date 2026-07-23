#!/usr/bin/env python3
"""script_commands_validate.py — validates embedded shell commands in a
bumfuzzle config (given as JSON, pre-converted from YAML by
scripts/prerequisites/script-commands.sh): every scripts[].command and
script_clean rules[].command must be non-empty and syntactically valid
bash, and no two scripts should share byte-identical commands. Exists to
replace what used to be one yq subprocess per script/rule (hundreds on a
config with many entries) with a single JSON parse and one in-process pass.

Usage:
  script_commands_validate.py [-v|--verbose] CONFIG_JSON
  script_commands_validate.py -h | --help

  -v, --verbose  show DEBUG-level detail on stderr

Prints one "[FAIL:structural|error|warn] ..." line per finding to stdout,
matching scripts/prerequisites/script-commands.sh's finding wording
exactly. Exit codes: 0 = no structural/error findings (warnings alone
still 0), 1 = at least one structural/error finding, 2 = usage error.
"""
import hashlib
import json
import subprocess
import sys
import time

SCRIPT = "script_commands_validate.py"
VERBOSE = False


def _log(level, message):
    if level == "DEBUG" and not VERBOSE:
        return
    timestamp = time.strftime("%y-%m-%dT%H:%M:%SZ", time.gmtime())
    print(f"[{timestamp}][{SCRIPT}][{level}] - {message}", file=sys.stderr)


def usage():
    print(__doc__.strip(), file=sys.stderr)


def _walk_ids(node):
    if isinstance(node, dict):
        if "id" in node:
            yield node
        for v in node.values():
            yield from _walk_ids(v)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_ids(item)


def _walk_rules(node, rule_type):
    if isinstance(node, dict):
        if node.get("type") == rule_type:
            yield node
        for v in node.values():
            yield from _walk_rules(v, rule_type)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_rules(item, rule_type)


def _is_blank(value):
    return value is None or str(value).strip() == "" or str(value) == "null"


def _bash_syntax_ok(command):
    result = subprocess.run(["bash", "-n"], input=command, capture_output=True, text=True)
    return result.returncode == 0


def main(argv):
    global VERBOSE

    if "-h" in argv or "--help" in argv:
        usage()
        return 0

    if "-v" in argv or "--verbose" in argv:
        VERBOSE = True

    positional = [a for a in argv if not a.startswith("-")]
    if len(positional) != 1:
        _log("ERROR", f"Expected 1 positional argument, got {len(positional)}")
        usage()
        return 2
    config_path = positional[0]

    try:
        with open(config_path) as f:
            config = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        _log("ERROR", f"Could not read config {config_path}: {e}")
        return 2

    _log("DEBUG", f"Loading scripts/rules from {config_path}")

    structural = 0
    error = 0
    warn = 0
    seen_ids = set()
    seen_hashes = {}

    for script in _walk_ids(config.get("scripts") or {}):
        script_id = script["id"]
        if script_id in seen_ids:
            continue  # duplicate id, duplicate-ids.sh's job to report
        seen_ids.add(script_id)

        command = script.get("command")
        if _is_blank(command):
            print(f"[FAIL:structural] script '{script_id}' has no command")
            structural += 1
            continue
        if not _bash_syntax_ok(command):
            print(f"[FAIL:error] script '{script_id}' has bash syntax errors")
            error += 1
        digest = hashlib.sha256(command.encode()).hexdigest()
        prev = seen_hashes.get(digest)
        if prev is not None:
            print(f"[FAIL:warn] scripts '{prev}' and '{script_id}' have identical commands")
            warn += 1
        else:
            seen_hashes[digest] = script_id

    for rule in _walk_rules(config.get("rules") or {}, "script_clean"):
        command = rule.get("command")
        if _is_blank(command):
            continue  # missing command is reported by rule-fields.sh
        if not _bash_syntax_ok(command):
            name = rule.get("name") or "?"
            print(f"[FAIL:error] script_clean rule '{name}' has bash syntax errors")
            error += 1

    _log("INFO", f"Checked commands: {structural} structural, {error} error, {warn} warn finding(s)")
    return 1 if (structural or error) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
