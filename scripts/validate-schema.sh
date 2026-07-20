#!/usr/bin/env bash
# validate-schema.sh — validates a bumfuzzle config (default .bumfuzzle/config.yml)
# against this project's schema.yml. Runs standalone (`bumfuzzle
# validate-schema [file]`) or as a step of `bumfuzzle run`'s config lint
# phase (see scripts/eval-rules.sh).
#
# Every structural rule — required fields, additionalProperties, if/then/else,
# enum membership — lives entirely in schema.yml and is enforced by
# scripts/json_schema_validate.py, a generic JSON Schema validator with no
# bumfuzzle-specific knowledge. This script's only job is bumfuzzle's own
# file conventions: resolving schema.yml's location, converting YAML to JSON,
# defaulting TARGET, and reporting in this project's [PASS]/[FAIL] convention
# (scripts/lint-config.sh's _lint_field_values parses this script's stdout for
# lines starting with "[FAIL] "). Renaming a field or a $defs entry in
# schema.yml needs no change here.
#
# Relational/cross-node checks JSON Schema cannot express at all (duplicate
# ids, dangling id references) are NOT schema conformance and are not run
# here — see scripts/lint-config.sh's _lint_duplicate_ids / _lint_reference_integrity.
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
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: validate-schema.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to validate (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Validates TARGET against schema.yml. Prints [PASS]/[FAIL] lines to stdout;
exits 0 if TARGET conforms, 1 if it doesn't, 2 on a usage error.
EOF
}

TARGET=""
_TARGET_SET=false
_SHOW_HELP=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      _SHOW_HELP=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -*)
      printf 'validate-schema.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'validate-schema.sh: unexpected extra argument: %s\n\n' "$1" >&2
        usage >&2
        exit 2
      fi
      TARGET="$1"
      _TARGET_SET=true
      shift
      ;;
  esac
done

if [[ "$_SHOW_HELP" == true ]]; then
  usage
  exit 0
fi

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCHEMA_FILE="$BUMFUZZLE_ROOT/schema.yml"
SCHEMA_FILE_DISPLAY="schema.yml"
VALIDATOR="$BUMFUZZLE_ROOT/scripts/json_schema_validate.py"
VALIDATOR_DISPLAY="scripts/json_schema_validate.py"
TARGET="${TARGET:-.bumfuzzle/config.yml}"

if ! command -v yq &>/dev/null; then
  _log ERROR "yq is not installed"
  printf '[FAIL] yq is not installed - required to validate %s\n' "$TARGET"
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  _log ERROR "python3 is not installed"
  printf '[FAIL] python3 is not installed - required to validate %s\n' "$TARGET"
  exit 1
fi
if [[ ! -f "$TARGET" ]]; then
  _log ERROR "$TARGET not found"
  printf '[FAIL] %s not found\n' "$TARGET"
  exit 1
fi
if [[ ! -f "$SCHEMA_FILE" ]]; then
  _log ERROR "schema not found: $SCHEMA_FILE_DISPLAY"
  printf '[FAIL] schema not found: %s\n' "$SCHEMA_FILE_DISPLAY"
  exit 1
fi
if [[ ! -f "$VALIDATOR" ]]; then
  _log ERROR "validator not found: $VALIDATOR_DISPLAY"
  printf '[FAIL] validator not found: %s\n' "$VALIDATOR_DISPLAY"
  exit 1
fi
_log INFO "starting schema validation of $TARGET"

TMP_DIR="$BUMFUZZLE_ROOT/tmp"
_log DEBUG "creating temp dir $TMP_DIR"
mkdir -p "$TMP_DIR"
SCHEMA_JSON="$(mktemp "$TMP_DIR/validate-schema.schema.XXXXXX.json")"
TARGET_JSON="$(mktemp "$TMP_DIR/validate-schema.target.XXXXXX.json")"
_log DEBUG "temp files: $SCHEMA_JSON, $TARGET_JSON"
_cleanup() { rm -f "$SCHEMA_JSON" "$TARGET_JSON"; }
trap '_cleanup' EXIT
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM

_log DEBUG "converting $SCHEMA_FILE and $TARGET to JSON"
yq -o=json '.' "$SCHEMA_FILE" > "$SCHEMA_JSON"
yq -o=json '.' "$TARGET" > "$TARGET_JSON"

_log DEBUG "running $VALIDATOR $SCHEMA_JSON $TARGET_JSON"
_ERRORS=$(python3 "$VALIDATOR" "$SCHEMA_JSON" "$TARGET_JSON") && _RC=0 || _RC=$?
_log DEBUG "$VALIDATOR exited $_RC"

if [[ "$_RC" -eq 2 ]]; then
  _log ERROR "validator could not run (see above)"
  printf '[FAIL] could not validate %s — see stderr for details\n' "$TARGET"
  exit 1
fi

if [[ "$_RC" -eq 1 ]]; then
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    printf '[FAIL] %s %s\n' "$TARGET" "$_line"
  done <<< "$_ERRORS"
  _log INFO "validation failed"
  exit 1
fi

# JSON Schema can require the field but can't compare its value against the
# schema's own — that cross-document check has to happen here.
_SCHEMA_VERSION=$(yq '.schema_version' "$SCHEMA_FILE")
_TARGET_VERSION=$(yq '.schema_version' "$TARGET")
if [[ "$_TARGET_VERSION" != "$_SCHEMA_VERSION" ]]; then
  _log INFO "schema_version mismatch: $TARGET=$_TARGET_VERSION $SCHEMA_FILE_DISPLAY=$_SCHEMA_VERSION"
  printf '[FAIL] %s schema_version (%s) does not match %s schema_version (%s)\n' "$TARGET" "$_TARGET_VERSION" "$SCHEMA_FILE_DISPLAY" "$_SCHEMA_VERSION"
  exit 1
fi

_log INFO "validation passed"
printf '[PASS] %s matches %s\n' "$TARGET" "$SCHEMA_FILE_DISPLAY"
