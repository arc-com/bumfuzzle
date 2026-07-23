#!/usr/bin/env bash
# reporting.sh — shared pass/fail/section state for `bumfuzzle run`. Not a
# standalone script: only defines state and functions, meant to be sourced
# into run.sh's shell (see run.sh's source line), where rule-runner.sh's
# rule execution then calls these same functions directly — that's why
# pass()/fail() still tag their output "[run.sh]": it identifies the
# `bumfuzzle run` output stream, not which file printed the line, same
# convention rule-runner.sh's own DEBUG lines already follow.

ERRORS=()
WARNINGS=()
_PASS_COUNT=0
_PENDING_HEADER=""

is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }

section() { _PENDING_HEADER="$1"; }

_flush_header() {
  if [[ -n "$_PENDING_HEADER" ]]; then
    printf '\n%s\n' "$_PENDING_HEADER"
    _PENDING_HEADER=""
  fi
}

pass() {
  _PASS_COUNT=$((_PASS_COUNT + 1))
  _flush_header
  if [[ "$VERBOSE" == true ]]; then
    _log DEBUG "[PASS] $1"
  fi
}

fail() {
  local _sev="${2:-error}"
  local _details="${3:-}"
  case "$_sev" in
    warn)
      _flush_header
      _log WARN "[WARN] $1"
      [[ -n "$_details" ]] && printf '%s\n' "$_details"
      WARNINGS+=("$1")
      ;;
    hard-stop)
      _flush_header
      _log ERROR "[FAIL] $1"
      [[ -n "$_details" ]] && printf '%s\n' "$_details"
      _log ERROR "[HARD-STOP] Aborting run"
      exit 1
      ;;
    *)
      _flush_header
      _log ERROR "[FAIL] $1"
      [[ -n "$_details" ]] && printf '%s\n' "$_details"
      ERRORS+=("$1")
      ;;
  esac
}
