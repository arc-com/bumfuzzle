#!/usr/bin/env bash
# lib.sh — shared helpers for the atomic scripts under scripts/init/ and
# their orchestrator, scripts/init.sh. Meant to be sourced, not executed.
# Callers must set SCRIPT_NAME before sourcing. Sources scripts/lib.sh for
# the shared _log() helper rather than redefining it here.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

DRY_RUN=false
PRETTIFY=false

# parse_init_args "$@" — parses the shared -h/--help, -v/--verbose,
# --dry-run, and --prettify flags every scripts/init/*.sh script and
# scripts/init.sh itself accept. --prettify only has an effect in
# scripts/init.sh, the only one of these that ever emits a Banner or
# Section (per this project's opt-in rule for both) - the atomic scripts
# still parse it, for a consistent CLI shape, but their own usage() says so
# rather than silently accepting an undocumented flag. None of these
# scripts take a positional. Prints the caller's own `usage` function and
# exits 2 on an unrecognized argument, or exits 0 after printing usage on
# -h/--help.
parse_init_args() {
  local _show_help=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) _show_help=true; shift ;;
      -v|--verbose) VERBOSE=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --prettify) PRETTIFY=true; shift ;;
      *)
        printf '%s: unrecognized argument: %s\n\n' "$SCRIPT_NAME" "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
  if [[ "$_show_help" == true ]]; then
    usage
    exit 0
  fi
}

_banner_line() { printf '%*s' 71 '' | tr ' ' '-'; }

# _section_line LABEL — "-- Label " + '-' fill to a fixed 73-column total
# width, extending past 73 rather than truncating Label if fill would drop
# below 2 characters, per this project's Section formatting rule.
_section_line() {
  local _label="$1"
  local _prefix="-- $_label "
  local _fill=$(( 73 - ${#_prefix} ))
  [[ "$_fill" -lt 2 ]] && _fill=2
  printf '%s%s' "$_prefix" "$(printf '%*s' "$_fill" '' | tr ' ' '-')"
}

_INIT_TMP_FILES=()
_cleanup_init_tmp() {
  [[ ${#_INIT_TMP_FILES[@]} -gt 0 ]] && rm -f "${_INIT_TMP_FILES[@]}"
  return 0
}
trap '_cleanup_init_tmp' EXIT
trap '_cleanup_init_tmp; exit 130' INT
trap '_cleanup_init_tmp; exit 143' TERM

# init_tmp_file — creates a temp file under $BUMFUZZLE_ROOT/tmp (never the
# shared system /tmp), tracks it for cleanup on exit/SIGINT/SIGTERM via this
# file's own traps above, and prints its path.
init_tmp_file() {
  mkdir -p "$BUMFUZZLE_ROOT/tmp"
  local _f
  _f="$(mktemp "$BUMFUZZLE_ROOT/tmp/$SCRIPT_NAME.XXXXXX")"
  _INIT_TMP_FILES+=("$_f")
  printf '%s' "$_f"
}
