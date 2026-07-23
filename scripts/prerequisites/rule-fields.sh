#!/usr/bin/env bash
# rule-fields.sh — checks that every rules entry in TARGET (default
# .bumfuzzle/config.yml) has the fields its type requires: a group or a
# type, a known type (script_clean/script_reusable), the type-specific
# required field (command/script), and a name.
set -euo pipefail

SCRIPT_NAME="rule-fields.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: rule-fields.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks that every rules entry in TARGET has the fields its type requires.
Prints [FAIL:structural]/[FAIL:error]/[PASS] lines to stdout; exits 0 if
none found, 1 if any are, 2 on a usage error.
EOF
}

parse_target_args "$@"

_FINDINGS_STRUCTURAL=0
_FINDINGS_ERROR=0
_report_structural() {
  printf '[FAIL:structural] %s\n' "$1"
  _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1))
  _log DEBUG "Structural finding: $1"
}
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "Error finding: $1"
}

_check() {
  local _p _msg
  while IFS= read -r _p; do
    [[ -z "$_p" ]] && continue
    _report_structural "rules entry at .$_p has neither 'group' nor 'type'"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select((has("group") or has("type")) | not) | path | join(".")' | grep -v 'args$')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _report_structural "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(has("type")) | select(.type != "script_clean" and .type != "script_reusable") | "rule " + (.name // "?") + " has unknown type " + (.type | tostring)')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _report_structural "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_clean") | select(has("command") | not) | "script_clean rule " + (.name // "?") + " is missing required field: command"')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _report_structural "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_reusable") | select(has("script") | not) | "script_reusable rule " + (.name // "?") + " is missing required field: script"')

  while IFS= read -r _p; do
    [[ -z "$_p" ]] && continue
    _report_error "rule at .$_p is missing required field: name"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(has("type")) | select(has("name") | not) | path | join(".")')
}

_log DEBUG "Target: $TARGET"
_log INFO "Checking rule fields required by type"
_check

if [[ "$_FINDINGS_STRUCTURAL" -gt 0 || "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] all rules in %s have the fields their type requires\n' "$TARGET"
exit 0
