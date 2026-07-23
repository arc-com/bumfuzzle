#!/usr/bin/env bash
# lib.sh — shared logging helper for every bumfuzzle script. Meant to be
# sourced, not executed directly. Callers must set SCRIPT_NAME before
# sourcing, and VERBOSE before the first _log call (defaults to false).
set -euo pipefail

VERBOSE="${VERBOSE:-false}"

# _log LEVEL MESSAGE — writes "[YY-MM-DDTHH:mm:ssZ][SCRIPT_NAME][LEVEL] -
# MESSAGE" to stderr. DEBUG is suppressed unless VERBOSE is true. MESSAGE
# must start with a capital letter and may optionally lead or be prefixed
# with a literal TAG::WORD marker (one uppercase word) for grep-based log
# navigation.
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s][%s] - %s\n' "$(date -u +'%y-%m-%dT%H:%M:%SZ')" "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

# millisecond-precision wall clock via `date +%s%N` (falls back to
# whole-second precision via bash's SECONDS builtin on a `date` without %N
# support). Precision is probed once, here, at source time. _now_ms() itself
# must never print anything but the numeric value, since its stdout is
# captured as the return value by every caller.
_ns_probe=$(date +%s%N 2>/dev/null || true)
if [[ "$_ns_probe" =~ ^[0-9]+$ ]]; then
  _HAS_NS_PRECISION=true
else
  _HAS_NS_PRECISION=false
fi

_now_ms() {
  if [[ "$_HAS_NS_PRECISION" == true ]]; then
    printf '%s' "$(( $(date +%s%N) / 1000000 ))"
  else
    printf '%s' "$(( SECONDS * 1000 ))"
  fi
}
