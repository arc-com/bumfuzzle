#!/usr/bin/env bash
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT_NAME="run.sh"
source "$BUMFUZZLE_ROOT/scripts/lib.sh"

VERBOSE=false
PLAIN=false
PRETTIFY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -p|--plain)
      PLAIN=true
      shift
      ;;
    --prettify)
      PRETTIFY=true
      shift
      ;;
    *)
      printf '[FAIL] Unrecognized argument: %s\n' "$1" >&2
      printf 'Usage: bumfuzzle run [--verbose|-v] [--plain|-p] [--prettify]\n'
      exit 1
      ;;
  esac
done

# flags are fully resolved at this point (arg parsing above is complete),
# the earliest scripts/logging.sh may be sourced per its own contract. No
# export of PLAIN to subprocesses is needed: config_lint_check passes
# --verbose to prerequisites.sh explicitly (see rule-runner.sh), and every
# log_* call anywhere in that subtree is DEBUG-level, already suppressed
# by default with or without --plain.
_logging_flags=()
[[ "$VERBOSE" == true ]] && _logging_flags+=(--verbose)
[[ "$PLAIN" == true ]] && _logging_flags+=(--plain)
[[ "$PRETTIFY" == true ]] && _logging_flags+=(--prettify)
source "$BUMFUZZLE_ROOT/scripts/logging.sh" ${_logging_flags[@]+"${_logging_flags[@]}"}

# _now_ms/_HAS_NS_PRECISION come from scripts/lib.sh (sourced above), shared
# with scripts/prerequisites.sh and rule-runner.sh rather than reprobed here.
if [[ "$_HAS_NS_PRECISION" == true ]]; then
  log_debug "TAG::TIMER Date supports %N, using millisecond-precision timer"
else
  log_debug "TAG::TIMER Date does not support %N, falling back to whole-second timer precision"
fi

# captured immediately after arg parsing (the earliest point VERBOSE is known)
# so this is the earliest possible moment to both start and log the timer
_RUN_START=$(_now_ms)
log_debug "TAG::TIMER Timer started"

RUN_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"
PREFLIGHT_FILE=".bumfuzzle/config.yml"

. "$BUMFUZZLE_ROOT/scripts/reporting.sh"

log_debug "Starting bumfuzzle run v$RUN_VERSION"

log_debug "Starting prerequisites check"
section 'Prerequisites'

if [[ ! -f "$PREFLIGHT_FILE" ]]; then
  TEMPLATE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
  if [[ ! -f "$TEMPLATE" ]]; then
    log_section_flush
    log_error "[FAIL] $PREFLIGHT_FILE not found and template missing - cannot run validation"
    exit 1
  fi
  log_debug "Creating directory $(dirname "$PREFLIGHT_FILE")"
  mkdir -p "$(dirname "$PREFLIGHT_FILE")"
  log_debug "Copying $TEMPLATE to $PREFLIGHT_FILE"
  cp "$TEMPLATE" "$PREFLIGHT_FILE"
  log_section_flush
  log_debug "Config not found - scaffolded from template: $PREFLIGHT_FILE"
else
  log_debug "Using existing config, already present: $PREFLIGHT_FILE"
fi

pass "$PREFLIGHT_FILE is present"
pass "run v$RUN_VERSION"
log_debug "Prerequisites satisfied"

# PREFLIGHT_FILE becomes absolute below so checks work regardless of any cwd
# change; PREFLIGHT_FILE_DISPLAY keeps the plain relative name for messages,
# so [PASS]/[FAIL] lines never leak this machine's absolute path.
PREFLIGHT_FILE_DISPLAY="$PREFLIGHT_FILE"
PREFLIGHT_FILE="$(pwd)/$PREFLIGHT_FILE"

. "$BUMFUZZLE_ROOT/scripts/rule-runner.sh"

# config lint runs as part of Prerequisites (see rule-runner.sh): it validates
# .bumfuzzle/config.yml's own structure and is exempt from the enabled-rules gating
# that applies to user-defined rules - it always runs, unless scripts/fingerprint.sh
# shows none of its inputs (PREFLIGHT_FILE, schema.yml, every bumfuzzle-template*.yml)
# have changed since the last clean run, in which case re-running it would only
# reproduce the same findings against the same inputs.
_fp_args=("$PREFLIGHT_FILE")
[[ "$VERBOSE" == true ]] && _fp_args=(--verbose "$PREFLIGHT_FILE")

_fp_rc=0
_fp_out=$("$BUMFUZZLE_ROOT/scripts/fingerprint.sh" check "${_fp_args[@]}") || _fp_rc=$?
while IFS= read -r _fp_line; do
  [[ -z "$_fp_line" ]] && continue
  log_debug "Fingerprint.sh: $_fp_line"
done <<< "$_fp_out"

if [[ "$_fp_rc" -eq 0 ]]; then
  pass "config lint (skipped - fingerprint unchanged since last clean run)"
  log_info "Fingerprints are matching, skipping rules validation"
else
  log_info "Starting prerequisites checks"
  config_lint_check
  # fail-open on the write path too: a failed cache update must never fail
  # the user's actual validation run, only cost it a skip next time.
  _fp_update_out=$("$BUMFUZZLE_ROOT/scripts/fingerprint.sh" update "${_fp_args[@]}") || true
  log_debug "Fingerprint.sh update: $(printf '%s' "$_fp_update_out" | tr '\n' ' ')"
fi

log_debug "Starting rule evaluation"
_pre_rules_pass=$_PASS_COUNT
_pre_rules_err=${#ERRORS[@]}
_pre_rules_warn=${#WARNINGS[@]}
user_rules_check
log_debug "Rule evaluation finished: $(( _PASS_COUNT - _pre_rules_pass )) passed, $(( ${#ERRORS[@]} - _pre_rules_err )) failed, $(( ${#WARNINGS[@]} - _pre_rules_warn )) warned"

_elapsed_ms=$(( $(_now_ms) - _RUN_START ))
log_debug "TAG::TIMER Timer stopped: scripts finished in $(( _elapsed_ms / 1000 )).$(printf '%03d' $(( _elapsed_ms % 1000 )))s"

# --plain: a single Success/Failure token plus a flat issue list, meant for
# CI/scripted consumption (paired with --verbose it still gets the full log
# above, via scripts/logging.sh's log_* functions — this block is the only
# thing PLAIN changes).
if [[ "$PLAIN" == true ]]; then
  if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
    log_data 'Success\n'
    exit 0
  fi
  [[ ${#ERRORS[@]} -eq 0 ]] && log_data 'Success\n' || log_data 'Failure\n'
  for e in "${ERRORS[@]}"; do log_data '  - %s\n' "$e"; done
  for w in "${WARNINGS[@]}"; do log_data '  - %s\n' "$w"; done
  [[ ${#ERRORS[@]} -gt 0 ]] && exit 1 || exit 0
fi

if [[ ${#ERRORS[@]} -eq 0 ]]; then
  log_info "Bumfuzzle run: SUCCESS - $_PASS_COUNT passed, ${#ERRORS[@]} failed, ${#WARNINGS[@]} warned"
else
  log_info "Bumfuzzle run: FAILURE - $_PASS_COUNT passed, ${#ERRORS[@]} failed, ${#WARNINGS[@]} warned"
fi

if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
  log_banner '  All checks passed'
else
  log_banner_delim
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    log_data '%d check(s) failed:\n' "${#ERRORS[@]}"
    for e in "${ERRORS[@]}"; do
      log_data '  - %s\n' "$e"
    done
  fi

  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    log_data '%d warning(s):\n' "${#WARNINGS[@]}"
    for w in "${WARNINGS[@]}"; do
      log_data '  - %s\n' "$w"
    done
  fi
  log_banner_delim
fi

[[ ${#ERRORS[@]} -gt 0 ]] && exit 1 || exit 0
