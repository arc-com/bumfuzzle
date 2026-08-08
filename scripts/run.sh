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
      _log ERROR "[FAIL] Unrecognized argument: $1"
      printf 'Usage: bumfuzzle run [--verbose|-v] [--plain|-p] [--prettify]\n'
      exit 1
      ;;
  esac
done

# exported so config_lint_check's prerequisites.sh subprocess (a separate
# process, not sourced) inherits the same narration-suppression via its own
# scripts/lib.sh source-time default (see lib.sh's `PLAIN="${PLAIN:-false}"`)
export PLAIN

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

_log DEBUG "Starting bumfuzzle run v$RUN_VERSION"

_log DEBUG "Starting prerequisites check"
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
  _log DEBUG "Config not found - scaffolded from template: $PREFLIGHT_FILE"
else
  _log DEBUG "Using existing config, already present: $PREFLIGHT_FILE"
fi

pass "$PREFLIGHT_FILE is present"
pass "run v$RUN_VERSION"
_log DEBUG "Prerequisites satisfied"

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
  _log DEBUG "Fingerprint.sh: $_fp_line"
done <<< "$_fp_out"

if [[ "$_fp_rc" -eq 0 ]]; then
  pass "config lint (skipped - fingerprint unchanged since last clean run)"
  _log INFO "Fingerprints are matching, skipping rules validation"
else
  _log INFO "Starting prerequisites checks"
  config_lint_check
  # fail-open on the write path too: a failed cache update must never fail
  # the user's actual validation run, only cost it a skip next time.
  _fp_update_out=$("$BUMFUZZLE_ROOT/scripts/fingerprint.sh" update "${_fp_args[@]}") || true
  _log DEBUG "Fingerprint.sh update: $(printf '%s' "$_fp_update_out" | tr '\n' ' ')"
fi

_log DEBUG "Starting rule evaluation"
_pre_rules_pass=$_PASS_COUNT
_pre_rules_err=${#ERRORS[@]}
_pre_rules_warn=${#WARNINGS[@]}
user_rules_check
_log DEBUG "Rule evaluation finished: $(( _PASS_COUNT - _pre_rules_pass )) passed, $(( ${#ERRORS[@]} - _pre_rules_err )) failed, $(( ${#WARNINGS[@]} - _pre_rules_warn )) warned"

_elapsed_ms=$(( $(_now_ms) - _RUN_START ))
_log DEBUG "TAG::TIMER Timer stopped: scripts finished in $(( _elapsed_ms / 1000 )).$(printf '%03d' $(( _elapsed_ms % 1000 )))s"

# --plain: a single Success/Failure token plus a flat issue list, meant for
# CI/scripted consumption (paired with --verbose it still gets the full log
# above, via lib.sh's _log — this block is the only thing PLAIN changes).
if [[ "$PLAIN" == true ]]; then
  if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
    printf 'Success\n'
    exit 0
  fi
  [[ ${#ERRORS[@]} -eq 0 ]] && printf 'Success\n' || printf 'Failure\n'
  for e in "${ERRORS[@]}"; do printf '  - %s\n' "$e"; done
  for w in "${WARNINGS[@]}"; do printf '  - %s\n' "$w"; done
  [[ ${#ERRORS[@]} -gt 0 ]] && exit 1 || exit 0
fi

if [[ ${#ERRORS[@]} -eq 0 ]]; then
  _log INFO "Bumfuzzle run: SUCCESS - $_PASS_COUNT passed, ${#ERRORS[@]} failed, ${#WARNINGS[@]} warned"
else
  _log INFO "Bumfuzzle run: FAILURE - $_PASS_COUNT passed, ${#ERRORS[@]} failed, ${#WARNINGS[@]} warned"
fi

[[ "$PRETTIFY" == true ]] && printf '%s\n' '-----------------------------------------------------------------------'
if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
  [[ "$PRETTIFY" == true ]] && printf '  All checks passed\n'
else
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf '%d check(s) failed:\n' "${#ERRORS[@]}"
    for e in "${ERRORS[@]}"; do
      printf '  - %s\n' "$e"
    done
  fi

  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '%d warning(s):\n' "${#WARNINGS[@]}"
    for w in "${WARNINGS[@]}"; do
      printf '  - %s\n' "$w"
    done
  fi
fi
[[ "$PRETTIFY" == true ]] && printf '%s\n' '-----------------------------------------------------------------------'

[[ ${#ERRORS[@]} -gt 0 ]] && exit 1 || exit 0
