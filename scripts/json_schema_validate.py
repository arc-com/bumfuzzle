#!/usr/bin/env python3
"""json_schema_validate.py — validates a JSON instance file against a JSON
Schema file, generically. Carries no project-specific knowledge: every
constraint enforced (required fields, additionalProperties, if/then/else,
enum membership, pattern, etc.) comes entirely from the schema file's own
content, via the real json-schema-validator applicable to whatever draft
the schema declares (falls back to Draft 2020-12 if the schema omits
"$schema"). Works against any JSON Schema, not just this project's.

Usage:
  json_schema_validate.py [-v|--verbose] SCHEMA_JSON INSTANCE_JSON
  json_schema_validate.py -h | --help

  -v, --verbose  show DEBUG-level detail on stderr

Prints one "<json-path>: <message>" line per validation error to stdout,
sorted by path — the data this script exists to produce. Diagnostics go to
stderr. Exit codes: 0 = instance is valid, 1 = instance is invalid
(errors printed to stdout), 2 = usage or dependency error.
"""
import json
import sys
import time

SCRIPT = "json_schema_validate.py"
VERBOSE = False


def _log(level, message):
    if level == "DEBUG" and not VERBOSE:
        return
    timestamp = time.strftime("%y-%m-%dT%H:%M:%SZ", time.gmtime())
    print(f"[{timestamp}][{SCRIPT}][{level}] - {message}", file=sys.stderr)


def usage():
    print(__doc__.strip(), file=sys.stderr)


def main(argv):
    global VERBOSE

    if "-h" in argv or "--help" in argv:
        usage()
        return 0

    if "-v" in argv or "--verbose" in argv:
        VERBOSE = True

    positional = [a for a in argv if not a.startswith("-")]
    if len(positional) != 2:
        _log("ERROR", f"Expected 2 positional arguments, got {len(positional)}")
        usage()
        return 2
    schema_path, instance_path = positional

    try:
        import jsonschema
    except ImportError:
        _log("ERROR", "The 'jsonschema' Python package is required (pip install jsonschema)")
        return 2

    try:
        with open(schema_path) as f:
            schema = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        _log("ERROR", f"Could not read schema {schema_path}: {e}")
        return 2

    try:
        with open(instance_path) as f:
            instance = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        _log("ERROR", f"Could not read instance {instance_path}: {e}")
        return 2

    validator_cls = jsonschema.validators.validator_for(schema, default=jsonschema.Draft202012Validator)
    try:
        validator_cls.check_schema(schema)
    except jsonschema.exceptions.SchemaError as e:
        _log("ERROR", f"Invalid JSON Schema in {schema_path}: {e.message}")
        return 2
    validator = validator_cls(schema)

    _log("DEBUG", f"Validating {instance_path} against {schema_path}")
    errors = sorted(validator.iter_errors(instance), key=lambda e: [str(p) for p in e.path])
    if not errors:
        _log("INFO", "Instance is valid against schema")
        return 0

    _log("INFO", f"Instance has {len(errors)} validation error(s) against schema")
    for e in errors:
        path = e.json_path
        print(f"{path}: {e.message}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
