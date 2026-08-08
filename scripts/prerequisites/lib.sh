#!/usr/bin/env bash
# lib.sh — shared helpers for the atomic prerequisite check scripts under
# scripts/prerequisites/ and their orchestrator, scripts/prerequisites.sh.
# Meant to be sourced, not executed directly. Callers must set SCRIPT_NAME
# before sourcing, and define a `usage` function before calling
# parse_target_args, which sources scripts/logging.sh itself once -v/
# --verbose is known — see its own comment below.
set -euo pipefail

_lint_yq() { yq "$1" "$TARGET" 2>/dev/null || true; }

_JSON_TMP_FILES=()
_cleanup_json_tmp() {
  if [[ ${#_JSON_TMP_FILES[@]} -gt 0 ]]; then
    rm -f "${_JSON_TMP_FILES[@]}"
  fi
  return 0
}
trap '_cleanup_json_tmp' EXIT
trap '_cleanup_json_tmp; exit 130' INT
trap '_cleanup_json_tmp; exit 143' TERM

# yaml_to_json_tmp SOURCE_YAML OUTVAR — converts SOURCE_YAML to a temp JSON
# file under $BUMFUZZLE_ROOT/tmp via yq and sets OUTVAR to its path. The temp
# file is tracked for cleanup on exit/SIGINT/SIGTERM by this file's own traps.
# Callers needing to validate structured YAML content faster than repeated
# per-query yq calls convert once here, then read the JSON with a single
# python3 (or other) pass instead.
yaml_to_json_tmp() {
  local _source="$1" _outvar="$2"
  local _tmp_dir="$BUMFUZZLE_ROOT/tmp"
  mkdir -p "$_tmp_dir"
  local _json_file
  # trailing XXXXXX with nothing after it: BSD mktemp (macOS) only
  # substitutes a run of X's at the very end of the template, silently
  # taking anything else (e.g. a ".json" suffix after the X's) literally.
  _json_file="$(mktemp "$_tmp_dir/$SCRIPT_NAME.XXXXXX")"
  yq -o=json '.' "$_source" > "$_json_file"
  _JSON_TMP_FILES+=("$_json_file")
  printf -v "$_outvar" '%s' "$_json_file"
}

# parse_target_args "$@" — parses the shared -h/--help, -v/--verbose, and a
# single optional TARGET positional every prerequisite script accepts.
# Prints the caller's own `usage` function and exits 2 on an unknown flag
# or extra positional, or exits 0 after printing usage on -h/--help,
# per the shared argument-validation contract. Sets TARGET (defaulting to
# .bumfuzzle/config.yml) for the caller. Once -v/--verbose is resolved,
# sources scripts/logging.sh with it — the log_*/log_data functions it
# exposes only exist in the caller's shell after this returns; nothing
# before this point in a caller may use them (usage/argument errors above
# print directly, before verbosity is even known, which is why those
# still use printf rather than a log_* call).
parse_target_args() {
  TARGET=""
  local _target_set=false _show_help=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        _show_help=true
        shift
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      -*)
        printf '%s: unknown flag: %s\n\n' "$SCRIPT_NAME" "$1" >&2
        usage >&2
        exit 2
        ;;
      *)
        if [[ "$_target_set" == true ]]; then
          printf '%s: unexpected extra argument: %s\n\n' "$SCRIPT_NAME" "$1" >&2
          usage >&2
          exit 2
        fi
        TARGET="$1"
        _target_set=true
        shift
        ;;
    esac
  done

  local _logging_flags=()
  [[ "${VERBOSE:-false}" == true ]] && _logging_flags+=(--verbose)
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logging.sh" ${_logging_flags[@]+"${_logging_flags[@]}"}

  if [[ "$_show_help" == true ]]; then
    usage
    exit 0
  fi

  TARGET="${TARGET:-.bumfuzzle/config.yml}"
}
