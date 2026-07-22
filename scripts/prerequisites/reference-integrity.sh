#!/usr/bin/env bash
# reference-integrity.sh — checks that every script_reusable rule's `script`
# value resolves to a declared script id, and every `enum_ref` resolves to a
# declared enum id, in TARGET (default .bumfuzzle/config.yml). A dangling
# script reference makes rule evaluation unreliable (structural); a dangling
# enum_ref only affects the wizard's dropdown, not rule evaluation (error).
set -euo pipefail

SCRIPT_NAME="reference-integrity.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: reference-integrity.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks that every script_reusable rule's script reference, and every
enum_ref, resolves to a declared id in TARGET. Prints
[FAIL:structural]/[FAIL:error]/[PASS] lines to stdout; exits 0 if none
found, 1 if any are, 2 on a usage error.
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
      printf 'reference-integrity.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'reference-integrity.sh: unexpected extra argument: %s\n\n' "$1" >&2
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
  local _miss
  while IFS= read -r _miss; do
    [[ -z "$_miss" ]] && continue
    _report_structural "rule references unknown script '$_miss'"
  done < <(comm -23 \
    <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_reusable") | .script // ""' | grep -v '^$' | sort -u) \
    <(_lint_yq '.scripts | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u))

  # enum refs don't affect rule execution (wizard-only), so broken ones are
  # errors rather than structural aborts
  while IFS= read -r _miss; do
    [[ -z "$_miss" ]] && continue
    _report_error "unknown enum_ref '$_miss'"
  done < <(comm -23 \
    <(_lint_yq '.. | select(type == "!!map") | select(has("enum_ref")) | .enum_ref' | grep -v '^$' | sort -u) \
    <(_lint_yq '.enums | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u))
}

_log INFO "checking script/enum_ref reference integrity in $TARGET"
_check

if [[ "$_FINDINGS_STRUCTURAL" -gt 0 || "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] all script/enum_ref references in %s resolve\n' "$TARGET"
exit 0
