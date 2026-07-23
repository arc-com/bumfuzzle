#!/usr/bin/env bash
# validate-schema.sh — validates a bumfuzzle config (default .bumfuzzle/config.yml)
# against this project's schema.yml. Runs standalone (`bumfuzzle
# validate-schema [file]`) or as one of the checks in scripts/prerequisites.sh.
#
# Every structural rule — required fields, additionalProperties, if/then/else,
# enum membership — lives entirely in schema.yml and is enforced by
# scripts/json_schema_validate.py, a generic JSON Schema validator with no
# bumfuzzle-specific knowledge. This script's only job is bumfuzzle's own
# file conventions: resolving schema.yml's location, converting YAML to JSON,
# defaulting TARGET, and reporting in this project's [PASS]/[FAIL] convention
# (scripts/prerequisites.sh parses this script's stdout for lines starting
# with "[FAIL] "). Renaming a field or a $defs entry in schema.yml needs no
# change here.
#
# Relational/cross-node checks JSON Schema cannot express at all (duplicate
# ids, dangling id references) are NOT schema conformance and are not run
# here — see scripts/prerequisites/duplicate-ids.sh and
# scripts/prerequisites/reference-integrity.sh.
#
# ONE DOCUMENTED EXCEPTION to the genericity below: the schema_version check
# near the end of this file hardcodes the field name "schema_version". JSON
# Schema can require the field and type-check it, but has no keyword for
# comparing an instance value against a value living in the schema document
# itself — a schema validates data, it cannot be queried as data against its
# own vocabulary. That comparison is structurally outside what schema.yml
# can express, so it's the one piece of schema.yml content-knowledge that
# has to live here instead of there.
#
# INVARIANT: apart from that one exception, this script and
# json_schema_validate.py must work against any arbitrary SCHEMA_FILE/TARGET
# pair — never hardcode a field name, $defs id, or structural shape from
# schema.yml's content here or in the validator. The only bumfuzzle-specific
# knowledge allowed in this file is file conventions (default paths,
# YAML-to-JSON conversion, [PASS]/[FAIL] reporting) plus the schema_version
# exception above — every other constraint must keep coming from the schema
# file's own content, read generically.
set -euo pipefail

SCRIPT_NAME="validate-schema.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: validate-schema.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to validate (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Validates TARGET against schema.yml. Prints [PASS]/[FAIL] lines to stdout;
exits 0 if TARGET conforms, 1 if it doesn't, 2 on a usage error.
EOF
}

parse_target_args "$@"

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SCHEMA_FILE="$BUMFUZZLE_ROOT/schema.yml"
SCHEMA_FILE_DISPLAY="schema.yml"
VALIDATOR="$BUMFUZZLE_ROOT/scripts/json_schema_validate.py"
VALIDATOR_DISPLAY="scripts/json_schema_validate.py"

if ! command -v yq &>/dev/null; then
  _log ERROR "Yq is not installed"
  printf '[FAIL] yq is not installed - required to validate %s\n' "$TARGET"
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  _log ERROR "Python3 is not installed"
  printf '[FAIL] python3 is not installed - required to validate %s\n' "$TARGET"
  exit 1
fi
if [[ ! -f "$TARGET" ]]; then
  _log ERROR "Target not found: $TARGET"
  printf '[FAIL] %s not found\n' "$TARGET"
  exit 1
fi
if [[ ! -f "$SCHEMA_FILE" ]]; then
  _log ERROR "Schema not found: $SCHEMA_FILE_DISPLAY"
  printf '[FAIL] schema not found: %s\n' "$SCHEMA_FILE_DISPLAY"
  exit 1
fi
if [[ ! -f "$VALIDATOR" ]]; then
  _log ERROR "Validator not found: $VALIDATOR_DISPLAY"
  printf '[FAIL] validator not found: %s\n' "$VALIDATOR_DISPLAY"
  exit 1
fi
_log DEBUG "Target: $TARGET"
_log INFO "Starting schema validation"

_log DEBUG "Converting $SCHEMA_FILE and $TARGET to JSON"
yaml_to_json_tmp "$SCHEMA_FILE" SCHEMA_JSON
yaml_to_json_tmp "$TARGET" TARGET_JSON
_log DEBUG "Temp files: $SCHEMA_JSON, $TARGET_JSON"

_validator_args=("$SCHEMA_JSON" "$TARGET_JSON")
[[ "$VERBOSE" == true ]] && _validator_args=(--verbose "${_validator_args[@]}")

_log DEBUG "Running $VALIDATOR ${_validator_args[*]}"
_ERRORS=$(python3 "$VALIDATOR" "${_validator_args[@]}") && _RC=0 || _RC=$?
_log DEBUG "Validator exited $_RC"

if [[ "$_RC" -eq 2 ]]; then
  _log ERROR "Validator could not run (see above)"
  printf '[FAIL] could not validate %s — see stderr for details\n' "$TARGET"
  exit 1
fi

if [[ "$_RC" -eq 1 ]]; then
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    printf '[FAIL] %s %s\n' "$TARGET" "$_line"
  done <<< "$_ERRORS"
  _log INFO "Validation failed"
  exit 1
fi

# JSON Schema can require the field but can't compare its value against the
# schema's own — that cross-document check has to happen here.
_SCHEMA_VERSION=$(yq '.schema_version' "$SCHEMA_FILE")
_TARGET_VERSION=$(yq '.schema_version' "$TARGET")
if [[ "$_TARGET_VERSION" != "$_SCHEMA_VERSION" ]]; then
  _log DEBUG "Schema_version mismatch detail: $TARGET=$_TARGET_VERSION $SCHEMA_FILE_DISPLAY=$_SCHEMA_VERSION"
  _log INFO "Schema_version mismatch between target and schema"
  printf '[FAIL] %s schema_version (%s) does not match %s schema_version (%s)\n' "$TARGET" "$_TARGET_VERSION" "$SCHEMA_FILE_DISPLAY" "$_SCHEMA_VERSION"
  exit 1
fi

_log INFO "Validation passed"
printf '[PASS] %s matches %s\n' "$TARGET" "$SCHEMA_FILE_DISPLAY"
