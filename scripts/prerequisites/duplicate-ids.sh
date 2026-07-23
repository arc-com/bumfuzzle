#!/usr/bin/env bash
# duplicate-ids.sh — checks that no two scripts, and no two enums, in TARGET
# (default .bumfuzzle/config.yml) share the same id. Duplicate ids make
# script_reusable/enum_ref resolution ambiguous.
set -euo pipefail

SCRIPT_NAME="duplicate-ids.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

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

parse_target_args "$@"

_FINDINGS_ERROR=0
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "Error finding: $1"
}

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

_log DEBUG "Target: $TARGET"
_log INFO "Checking duplicate ids in scripts/enums"
_check

if [[ "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] no duplicate script/enum ids in %s\n' "$TARGET"
exit 0
