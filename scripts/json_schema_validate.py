#!/usr/bin/env python3
"""json_schema_validate.py — validates a JSON instance file against a JSON
Schema file, generically. Carries no project-specific knowledge: every
constraint enforced (required fields, additionalProperties, if/then/else,
enum membership, pattern, etc.) comes entirely from the schema file's own
content, via the real json-schema-validator applicable to whatever draft
the schema declares (falls back to Draft 2020-12 if the schema omits
"$schema"). Works against any JSON Schema, not just this project's.

Usage:
  json_schema_validate.py SCHEMA_JSON INSTANCE_JSON
  json_schema_validate.py -h | --help

Prints one "<json-path>: <message>" line per validation error to stdout,
sorted by path — the data this script exists to produce. Diagnostics go to
stderr. Exit codes: 0 = instance is valid, 1 = instance is invalid
(errors printed to stdout), 2 = usage or dependency error.
"""
import json
import sys

SCRIPT = "json_schema_validate.py"


def _log(level, message):
    print(f"[{SCRIPT}][{level}] {message}", file=sys.stderr)


def usage():
    print(__doc__.strip(), file=sys.stderr)


def main(argv):
    if "-h" in argv or "--help" in argv:
        usage()
        return 0

    positional = [a for a in argv if not a.startswith("-")]
    if len(positional) != 2:
        _log("ERROR", f"expected 2 positional arguments, got {len(positional)}")
        usage()
        return 2
    schema_path, instance_path = positional

    try:
        import jsonschema
    except ImportError:
        _log("ERROR", "the 'jsonschema' Python package is required (pip install jsonschema)")
        return 2

    try:
        with open(schema_path) as f:
            schema = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        _log("ERROR", f"could not read schema {schema_path}: {e}")
        return 2

    try:
        with open(instance_path) as f:
            instance = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        _log("ERROR", f"could not read instance {instance_path}: {e}")
        return 2

    validator_cls = jsonschema.validators.validator_for(schema, default=jsonschema.Draft202012Validator)
    try:
        validator_cls.check_schema(schema)
    except jsonschema.exceptions.SchemaError as e:
        _log("ERROR", f"{schema_path} is not a valid JSON Schema: {e.message}")
        return 2
    validator = validator_cls(schema)

    errors = sorted(validator.iter_errors(instance), key=lambda e: [str(p) for p in e.path])
    if not errors:
        _log("INFO", f"{instance_path} is valid against {schema_path}")
        return 0

    _log("INFO", f"{instance_path} has {len(errors)} validation error(s) against {schema_path}")
    for e in errors:
        path = e.json_path
        print(f"{path}: {e.message}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
