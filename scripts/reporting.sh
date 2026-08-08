#!/usr/bin/env bash
# reporting.sh — shared pass/fail state for `bumfuzzle run`. Not a
# standalone script: only defines state and functions, meant to be sourced
# into run.sh's shell (see run.sh's source line, after scripts/logging.sh
# — pass()/fail() below call straight into the log_*/log_section_flush
# functions it exposes, never printing anything themselves), where
# rule-runner.sh's rule execution then calls these same functions directly
# — that's why pass()/fail() still tag their output "[run.sh]": it
# identifies the `bumfuzzle run` output stream, not which file printed the
# line, same convention rule-runner.sh's own DEBUG lines already follow.

ERRORS=()
WARNINGS=()
_PASS_COUNT=0

is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }

# section LABEL — thin alias to logging.sh's own lazy-Section primitive,
# kept so call sites elsewhere in the `bumfuzzle run` pipeline read as
# "open a section" rather than the more generic log_section_pending name.
section() { log_section_pending "$1"; }

pass() {
  _PASS_COUNT=$((_PASS_COUNT + 1))
  log_section_flush
  if [[ "$VERBOSE" == true ]]; then
    log_debug "[PASS] $1"
  fi
}

fail() {
  local _sev="${2:-error}"
  local _details="${3:-}"
  case "$_sev" in
    warn)
      log_section_flush
      log_warn "[WARN] $1"
      [[ -n "$_details" ]] && ! log_quiet && log_data '%s\n' "$_details"
      WARNINGS+=("$1")
      ;;
    hard-stop)
      log_section_flush
      log_error "[FAIL] $1"
      [[ -n "$_details" ]] && ! log_quiet && log_data '%s\n' "$_details"
      log_error "[HARD-STOP] Aborting run"
      exit 1
      ;;
    *)
      log_section_flush
      log_error "[FAIL] $1"
      [[ -n "$_details" ]] && ! log_quiet && log_data '%s\n' "$_details"
      ERRORS+=("$1")
      ;;
  esac
}
