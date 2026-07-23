#!/usr/bin/env bash
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT_NAME="run.sh"
source "$BUMFUZZLE_ROOT/scripts/lib.sh"

VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      _log ERROR "[FAIL] Unrecognized argument: $1"
      printf 'Usage: bumfuzzle run [--verbose|-v]\n'
      exit 1
      ;;
  esac
done

# _now_ms/_HAS_NS_PRECISION come from scripts/lib.sh (sourced above), shared
# with scripts/prerequisites.sh and rule-runner.sh rather than reprobed here.
if [[ "$_HAS_NS_PRECISION" == true ]]; then
  _log DEBUG "TAG::TIMER Date supports %N, using millisecond-precision timer"
else
  _log DEBUG "TAG::TIMER Date does not support %N, falling back to whole-second timer precision"
fi

# captured immediately after arg parsing (the earliest point VERBOSE is known)
# so this is the earliest possible moment to both start and log the timer
_RUN_START=$(_now_ms)
_log DEBUG "TAG::TIMER Timer started"

RUN_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"
PREFLIGHT_FILE=".bumfuzzle/config.yml"

. "$BUMFUZZLE_ROOT/scripts/reporting.sh"

_log INFO "Starting bumfuzzle run v$RUN_VERSION"

_log INFO "Starting prerequisites check"
section '-- Prerequisites --------------------------------------------------------'

if [[ ! -f "$PREFLIGHT_FILE" ]]; then
  TEMPLATE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
  if [[ ! -f "$TEMPLATE" ]]; then
    _flush_header
    _log ERROR "[FAIL] $PREFLIGHT_FILE not found and template missing - cannot run validation"
    exit 1
  fi
  _log DEBUG "Creating directory $(dirname "$PREFLIGHT_FILE")"
  mkdir -p "$(dirname "$PREFLIGHT_FILE")"
  _log DEBUG "Copying $TEMPLATE to $PREFLIGHT_FILE"
  cp "$TEMPLATE" "$PREFLIGHT_FILE"
  _flush_header
  _log INFO "Config not found - scaffolded from template: $PREFLIGHT_FILE"
else
  _log DEBUG "Using existing config, already present: $PREFLIGHT_FILE"
fi

pass "$PREFLIGHT_FILE is present"
pass "run v$RUN_VERSION"
_log INFO "Prerequisites satisfied"

# PREFLIGHT_FILE becomes absolute below so checks work regardless of any cwd
# change; PREFLIGHT_FILE_DISPLAY keeps the plain relative name for messages,
# so [PASS]/[FAIL] lines never leak this machine's absolute path.
PREFLIGHT_FILE_DISPLAY="$PREFLIGHT_FILE"
PREFLIGHT_FILE="$(pwd)/$PREFLIGHT_FILE"

. "$BUMFUZZLE_ROOT/scripts/rule-runner.sh"

# config lint runs as part of Prerequisites (see rule-runner.sh): it validates
# .bumfuzzle/config.yml's own structure and is exempt from the enabled-rules gating
# that applies to user-defined rules — it always runs.
_log INFO "Starting config lint"
config_lint_check

_log INFO "Starting rule evaluation"
_pre_rules_pass=$_PASS_COUNT
_pre_rules_err=${#ERRORS[@]}
_pre_rules_warn=${#WARNINGS[@]}
user_rules_check
_log INFO "Rule evaluation finished: $(( _PASS_COUNT - _pre_rules_pass )) passed, $(( ${#ERRORS[@]} - _pre_rules_err )) failed, $(( ${#WARNINGS[@]} - _pre_rules_warn )) warned"

_elapsed_ms=$(( $(_now_ms) - _RUN_START ))
_log DEBUG "TAG::TIMER Timer stopped: scripts finished in $(( _elapsed_ms / 1000 )).$(printf '%03d' $(( _elapsed_ms % 1000 )))s"

if [[ ${#ERRORS[@]} -eq 0 ]]; then
  _log INFO "Bumfuzzle run finished: PASS"
else
  _log INFO "Bumfuzzle run finished: FAIL"
fi

printf '%s\n' '-----------------------------------------------------------------------'
if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
  printf '  All checks passed\n'
  printf '%s\n' '-----------------------------------------------------------------------'
  exit 0
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  printf '  %d check(s) failed:\n' "${#ERRORS[@]}"
  for e in "${ERRORS[@]}"; do
    printf '    - %s\n' "$e"
  done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  printf '  %d warning(s):\n' "${#WARNINGS[@]}"
  for w in "${WARNINGS[@]}"; do
    printf '    - %s\n' "$w"
  done
fi

printf '%s\n' '-----------------------------------------------------------------------'
[[ ${#ERRORS[@]} -gt 0 ]] && exit 1 || exit 0
