#!/usr/bin/env bash
# script-arg-types.sh — checks every script_reusable rule in TARGET (default
# .bumfuzzle/config.yml): every arg value it passes must actually conform to
# the type its referenced script declares for that arg key (int, double,
# bool, regex, path, or enum membership; string/glob accept anything). A
# list-typed arg's value is checked item by item. Key presence/matching is
# script-args.sh's job, not this one's.
#
# TARGET is converted to JSON once and handed to
# script_arg_types_validate.py, which does the actual per-rule/per-arg type
# matching in a single in-process pass — looping this in bash with one yq
# call per rule per arg was the dominant cost of `bumfuzzle run` on a config
# with many rules (each yq call re-parses the whole file from scratch).
set -euo pipefail

SCRIPT_NAME="script-arg-types.sh"
BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: script-arg-types.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks every script_reusable rule's arg values against the type their
script declares for that arg. Prints [FAIL:error]/[PASS] lines to stdout;
exits 0 if none found, 1 if any are, 2 on a usage error.
EOF
}

parse_target_args "$@"

if ! command -v python3 &>/dev/null; then
  _log ERROR "Python3 is not installed"
  printf '[FAIL:error] python3 is not installed - required to check arg types\n'
  exit 1
fi

_log DEBUG "Target: $TARGET"
_log INFO "Checking script_reusable arg values against their declared types"

_log DEBUG "Converting $TARGET to JSON"
yaml_to_json_tmp "$TARGET" _CONFIG_JSON
_log DEBUG "Temp file: $_CONFIG_JSON"

_VALIDATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/script_arg_types_validate.py"
_validator_args=("$_CONFIG_JSON")
[[ "$VERBOSE" == true ]] && _validator_args=(--verbose "${_validator_args[@]}")

_log DEBUG "Running $_VALIDATOR ${_validator_args[*]}"
_RC=0
_OUT=$(python3 "$_VALIDATOR" "${_validator_args[@]}") || _RC=$?
_log DEBUG "Validator exited $_RC"

if [[ "$_RC" -eq 2 ]]; then
  _log ERROR "Validator could not run (see above)"
  exit 1
fi

_FINDINGS_ERROR=0
while IFS= read -r _line; do
  [[ -z "$_line" ]] && continue
  printf '%s\n' "$_line"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
done <<< "$_OUT"

if [[ "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf "[PASS] all script_reusable arg values in %s match their declared types\n" "$TARGET"
exit 0
