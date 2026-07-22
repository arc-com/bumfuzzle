#!/usr/bin/env bash
# duplicate-ids.sh — checks that no two scripts, and no two enums, in TARGET
# (default .bumfuzzle/config.yml) share the same id. Duplicate ids make
# script_reusable/enum_ref resolution ambiguous.
set -euo pipefail

SCRIPT_NAME="duplicate-ids.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: duplicate-ids.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks that no two scripts, and no two enums, in TARGET share the same id.
Prints [FAIL:error]/[PASS] lines to stdout; exits 0 if none found, 1 if any
are, 2 on a usage error.
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
      printf 'duplicate-ids.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'duplicate-ids.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

_FINDINGS_ERROR=0
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "error finding: $1"
}
_lint_yq() { yq "$1" "$TARGET" 2>/dev/null || true; }

_check() {
  local _ns _list _d
  for _ns in scripts enums; do
    _list=$(_lint_yq ".\"${_ns}\" | .. | select(type == \"!!map\") | select(has(\"id\")) | .id")
    while IFS= read -r _d; do
      [[ -z "$_d" ]] && continue
      _report_error "duplicate id '$_d' in ${_ns}:"
    done < <(printf '%s\n' "$_list" | grep -v '^$' | sort | uniq -d)
  done
}

_log INFO "checking duplicate ids in scripts/enums of $TARGET"
_check

if [[ "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] no duplicate script/enum ids in %s\n' "$TARGET"
exit 0
