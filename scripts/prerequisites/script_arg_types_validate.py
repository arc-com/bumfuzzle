#!/usr/bin/env python3
"""script_arg_types_validate.py — validates every script_reusable rule's arg
values in a bumfuzzle config (given as JSON, pre-converted from YAML by
scripts/prerequisites/script-arg-types.sh) against the type each arg
declares on its referenced script (int, double, bool, regex, path-file,
path-folder; string/glob accept anything). Any arg whose script definition
pins enum_ref is additionally restricted to that enum's declared members,
regardless of base type. A list: true arg may instead receive { enum_ref:
id } in place of a literal list, resolved against every current value of
that enums: entry (which must equal the arg's own pinned enum_ref, if any,
or otherwise just match the arg's type). Exists to replace what used to be
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


def _valid_path_common(value):
    if value in (".", "./", "/"):
        return False
    if ".." in value or "//" in value or "././" in value:
        return False
    if not value.startswith("./"):
        return False
    if any(c in value for c in "*?[]"):
        return False
    return True


def _valid_path_file(value):
    return _valid_path_common(value) and not value.endswith("/")


def _valid_path_folder(value):
    return _valid_path_common(value) and value.endswith("/")


def _valid_regex(value):
    result = subprocess.run(["grep", "-E", "-e", value], input="", capture_output=True, text=True)
    return result.returncode != 2


def _value_matches_type(value, arg_type):
    if arg_type == "int":
        return bool(re.fullmatch(r"-?[0-9]+", value))
    if arg_type == "double":
        return bool(re.fullmatch(r"-?[0-9]+(\.[0-9]+)?", value))
    if arg_type == "bool":
        return value in ("true", "false")
    if arg_type == "regex":
        return _valid_regex(value)
    if arg_type == "path-file":
        return _valid_path_file(value)
    if arg_type == "path-folder":
        return _valid_path_folder(value)
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
            arg_meta[key] = (arg.get("type") or "string", arg.get("enum_ref") or "", bool(arg.get("list")))
        script_args[script["id"]] = arg_meta

    enums = {}
    for enum in _walk_ids(config.get("enums") or {}):
        enums[enum["id"]] = (enum.get("type") or "", {v.get("value") for v in enum.get("values") or []})

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
            arg_type, pinned_enum, is_list = meta

            if isinstance(value, dict):
                ref_id = value.get("enum_ref")
                if not ref_id:
                    print(f"[FAIL:error] rule '{name}' passes a mapping for arg '{key}' without 'enum_ref'")
                    findings += 1
                    continue
                if not is_list:
                    print(f"[FAIL:error] rule '{name}' uses enum_ref for arg '{key}', only valid when the arg is list: true")
                    findings += 1
                    continue
                if pinned_enum and ref_id != pinned_enum:
                    print(f"[FAIL:error] rule '{name}' arg '{key}' is pinned to enum '{pinned_enum}', cannot reference '{ref_id}' instead")
                    findings += 1
                    continue
                ref = enums.get(ref_id)
                if ref is None:
                    continue  # dangling enum_ref, reference-integrity.sh's job to report
                ref_type, ref_values = ref
                if ref_type != arg_type:
                    print(f"[FAIL:error] rule '{name}' arg '{key}' references enum '{ref_id}' declared as type '{ref_type}', expected '{arg_type}'")
                    findings += 1
                    continue
                for item_str in ref_values:
                    if not _value_matches_type(item_str, arg_type):
                        print(f"[FAIL:error] rule '{name}' arg '{key}' via enum '{ref_id}' carries '{item_str}', not a valid {arg_type}")
                        findings += 1
                continue

            if arg_type in ("string", "glob") and not pinned_enum:
                continue
            pinned_values = enums.get(pinned_enum, ("", set()))[1] if pinned_enum else None

            values = value if isinstance(value, list) else [value]
            for item in values:
                item_str = _scalar_str(item)
                if pinned_values and item_str not in pinned_values:
                    print(f"[FAIL:error] rule '{name}' passes '{item_str}' for arg '{key}', not a member of enum '{pinned_enum}'")
                    findings += 1
                    continue
                if not _value_matches_type(item_str, arg_type):
                    print(f"[FAIL:error] rule '{name}' passes '{item_str}' for arg '{key}', not a valid {arg_type}")
                    findings += 1

    _log("DEBUG", f"Checked args, found {findings} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
