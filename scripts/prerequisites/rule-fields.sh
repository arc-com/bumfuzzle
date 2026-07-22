#!/usr/bin/env bash
# rule-fields.sh — checks that every rules entry in TARGET (default
# .bumfuzzle/config.yml) has the fields its type requires: a group or a
# type, a known type (script_clean/script_reusable), the type-specific
# required field (command/script), and a name.
set -euo pipefail

SCRIPT_NAME="rule-fields.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

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
      printf 'rule-fields.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'rule-fields.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

TARGET="${TARGET:-.bumfuzzle/config.yml}"

_FINDINGS_STRUCTURAL=0
_FINDINGS_ERROR=0
_report_structural() {
  printf '[FAIL:structural] %s\n' "$1"
  _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1))
  _log DEBUG "structural finding: $1"
}
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "error finding: $1"
}
_lint_yq() { yq "$1" "$TARGET" 2>/dev/null || true; }

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

_log INFO "checking rule fields required by type in $TARGET"
_check

if [[ "$_FINDINGS_STRUCTURAL" -gt 0 || "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] all rules in %s have the fields their type requires\n' "$TARGET"
exit 0
