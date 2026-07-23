#!/usr/bin/env python3
"""script_arg_types_validate.py — validates every script_reusable rule's arg
values in a bumfuzzle config (given as JSON, pre-converted from YAML by
scripts/prerequisites/script-arg-types.sh) against the type each arg
declares on its referenced script (int, double, bool, regex, path, or enum
membership; string/glob accept anything). Exists to replace what used to be
one yq subprocess per rule per arg (hundreds to thousands of calls on a
config with many rules) with a single JSON parse and one in-process pass.

Usage:
  script_arg_types_validate.py [-v|--verbose] CONFIG_JSON
  script_arg_types_validate.py -h | --help

  -v, --verbose  show DEBUG-level detail on stderr

Prints one "[FAIL:error] ..." line per invalid value to stdout, matching
scripts/prerequisites/script-arg-types.sh's finding wording exactly. Exit
codes: 0 = no findings, 1 = at least one finding, 2 = usage error.
"""
import json
import re
import subprocess
import sys
import time

SCRIPT = "script_arg_types_validate.py"
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


def _walk_rules(node):
    if isinstance(node, dict):
        if node.get("type") == "script_reusable":
            yield node
        for v in node.values():
            yield from _walk_rules(v)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_rules(item)


def _scalar_str(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _valid_path(value):
    if ".." in value:
        return False
    if "//" in value:
        return False
    if "././" in value:
        return False
    if value.endswith("/") and value != "/":
        return False
    return True


def _valid_regex(value):
    result = subprocess.run(["grep", "-E", "-e", value], input="", capture_output=True, text=True)
    return result.returncode != 2


def _value_matches_type(value, arg_type, enum_values):
    if arg_type == "int":
        return bool(re.fullmatch(r"-?[0-9]+", value))
    if arg_type == "double":
        return bool(re.fullmatch(r"-?[0-9]+(\.[0-9]+)?", value))
    if arg_type == "bool":
        return value in ("true", "false")
    if arg_type == "regex":
        return _valid_regex(value)
    if arg_type == "path":
        return _valid_path(value)
    if arg_type == "enum":
        return not enum_values or value in enum_values
    return True  # string/glob/unknown: accept anything


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

    _log("DEBUG", f"Loading script/enum declarations from {config_path}")

    script_args = {}
    for script in _walk_ids(config.get("scripts") or {}):
        arg_meta = {}
        for arg in script.get("args") or []:
            key = arg.get("key")
            if key is None:
                continue
            arg_meta[key] = (arg.get("type") or "string", arg.get("enum_ref") or "")
        script_args[script["id"]] = arg_meta

    enum_values = {}
    for enum in _walk_ids(config.get("enums") or {}):
        enum_values[enum["id"]] = {v.get("value") for v in enum.get("values") or []}

    findings = 0
    for rule in _walk_rules(config.get("rules") or {}):
        name = rule.get("name") or "unnamed"
        script_id = rule.get("script") or ""
        arg_meta = script_args.get(script_id)
        if arg_meta is None:
            continue  # unknown script id, script-args.sh's job to report

        for key, value in (rule.get("args") or {}).items():
            meta = arg_meta.get(key)
            if meta is None:
                continue  # unknown arg key, script-args.sh's job to report
            arg_type, enum_ref = meta
            if arg_type in ("string", "glob"):
                continue

            values = value if isinstance(value, list) else [value]
            for item in values:
                item_str = _scalar_str(item)
                if not _value_matches_type(item_str, arg_type, enum_values.get(enum_ref, set())):
                    print(f"[FAIL:error] rule '{name}' passes '{item_str}' for arg '{key}', not a valid {arg_type}")
                    findings += 1

    _log("INFO", f"Checked args, found {findings} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
