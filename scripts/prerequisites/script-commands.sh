#!/usr/bin/env bash
# script-commands.sh — checks embedded shell commands in TARGET (default
# .bumfuzzle/config.yml): every scripts[].command and script_clean
# rules[].command must be non-empty and syntactically valid bash, and no
# two scripts should share byte-identical commands (a likely copy-paste
# that should probably be one script referenced twice instead).
#
# TARGET is converted to JSON once and handed to
# script_commands_validate.py, which does the actual per-script/per-rule
# syntax and duplicate checking in a single in-process pass — looping this
# in bash with one yq call per script/rule was a major cost of `bumfuzzle
# run` on a config with many scripts and rules (each yq call re-parses the
# whole file from scratch).
set -euo pipefail

SCRIPT_NAME="script-commands.sh"
BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: script-commands.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks embedded shell commands in TARGET for syntax errors and duplicates.
Prints [FAIL:structural]/[FAIL:error]/[FAIL:warn]/[PASS] lines to stdout;
exits 0 if no structural or error findings (warnings alone still exit 0),
1 if there are, 2 on a usage error.
EOF
}

parse_target_args "$@"

if ! command -v python3 &>/dev/null; then
  _log ERROR "Python3 is not installed"
  printf '[FAIL:error] python3 is not installed - required to check embedded commands\n'
  exit 1
fi

_log DEBUG "Target: $TARGET"
_log INFO "Checking embedded command bash syntax and duplicate script commands"

_log DEBUG "Converting $TARGET to JSON"
yaml_to_json_tmp "$TARGET" _CONFIG_JSON
_log DEBUG "Temp file: $_CONFIG_JSON"

_VALIDATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/script_commands_validate.py"
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

_FINDINGS_STRUCTURAL=0
_FINDINGS_ERROR=0
_FINDINGS_WARN=0
while IFS= read -r _line; do
  [[ -z "$_line" ]] && continue
  printf '%s\n' "$_line"
  case "$_line" in
    '[FAIL:structural] '*) _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1)) ;;
    '[FAIL:error] '*)      _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1)) ;;
    '[FAIL:warn] '*)       _FINDINGS_WARN=$((_FINDINGS_WARN + 1)) ;;
  esac
done <<< "$_OUT"

if [[ "$_FINDINGS_STRUCTURAL" -gt 0 || "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] all embedded commands in %s are syntactically valid\n' "$TARGET"
if [[ "$_FINDINGS_WARN" -gt 0 ]]; then
  _log INFO "Found $_FINDINGS_WARN warning(s)"
fi
exit 0
