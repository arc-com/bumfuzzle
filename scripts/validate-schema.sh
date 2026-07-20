#!/usr/bin/env bash
# validate-schema.sh — validates a bumfuzzle config (default bumfuzzle.yml)
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
# INVARIANT: this script and json_schema_validate.py must work against any
# arbitrary SCHEMA_FILE/TARGET pair — never hardcode a field name, $defs id,
# or structural shape from schema.yml's content here or in the validator.
# The only bumfuzzle-specific knowledge allowed in this file is file
# conventions (default paths, YAML-to-JSON conversion, [PASS]/[FAIL]
# reporting) — every actual constraint must keep coming from the schema
# file's own content, read generically.
set -euo pipefail

SCRIPT_NAME="validate-schema.sh"
_log() { printf '[%s][%s] %s\n' "$SCRIPT_NAME" "$1" "$2" >&2; }

usage() {
  cat <<'EOF'
Usage: validate-schema.sh [-h|--help] [TARGET]

  TARGET   path to the bumfuzzle config to validate (default: bumfuzzle.yml)

Validates TARGET against schema.yml. Prints [PASS]/[FAIL] lines to stdout;
exits 0 if TARGET conforms, 1 if it doesn't, 2 on a usage error.
EOF
}

for _arg in "$@"; do
  case "$_arg" in
    -h|--help) usage; exit 0 ;;
  esac
done
if [[ $# -gt 1 ]]; then
  _log ERROR "expected at most 1 argument, got $#"
  usage >&2
  exit 2
fi

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCHEMA_FILE="$BUMFUZZLE_ROOT/schema.yml"
VALIDATOR="$BUMFUZZLE_ROOT/scripts/json_schema_validate.py"
TARGET="${1:-bumfuzzle.yml}"

if ! command -v yq &>/dev/null; then
  printf '[FAIL] yq is not installed - required to validate %s\n' "$TARGET"
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  printf '[FAIL] python3 is not installed - required to validate %s\n' "$TARGET"
  exit 1
fi
if [[ ! -f "$TARGET" ]]; then
  printf '[FAIL] %s not found\n' "$TARGET"
  exit 1
fi
if [[ ! -f "$SCHEMA_FILE" ]]; then
  printf '[FAIL] schema not found: %s\n' "$SCHEMA_FILE"
  exit 1
fi
if [[ ! -f "$VALIDATOR" ]]; then
  printf '[FAIL] validator not found: %s\n' "$VALIDATOR"
  exit 1
fi

TMP_DIR="$BUMFUZZLE_ROOT/tmp"
mkdir -p "$TMP_DIR"
SCHEMA_JSON="$(mktemp "$TMP_DIR/validate-schema.schema.XXXXXX.json")"
TARGET_JSON="$(mktemp "$TMP_DIR/validate-schema.target.XXXXXX.json")"
_cleanup() { rm -f "$SCHEMA_JSON" "$TARGET_JSON"; }
trap '_cleanup' EXIT
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM

_log DEBUG "converting $SCHEMA_FILE and $TARGET to JSON"
yq -o=json '.' "$SCHEMA_FILE" > "$SCHEMA_JSON"
yq -o=json '.' "$TARGET" > "$TARGET_JSON"

_ERRORS=$(python3 "$VALIDATOR" "$SCHEMA_JSON" "$TARGET_JSON") && _RC=0 || _RC=$?

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

_log INFO "validation passed"
printf '[PASS] %s matches %s\n' "$TARGET" "$SCHEMA_FILE"
