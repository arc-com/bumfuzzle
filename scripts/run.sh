#!/usr/bin/env bash
set -euo pipefail

VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      printf '[run.sh][ERROR] - [FAIL] unrecognized argument: %s\n' "$1"
      printf 'Usage: bumfuzzle run [--verbose|-v]\n'
      exit 1
      ;;
  esac
done

# millisecond-precision wall clock via `date +%s%N` (falls back to whole-second
# precision via bash's SECONDS builtin on a `date` without %N support) so the
# elapsed-time log below can show fractional seconds, not just whole ones.
# Precision is probed once, here, and the decision logged here too — _now_ms()
# itself must never print anything but the numeric value, since its stdout is
# captured as the return value by every caller.
_ns_probe=$(date +%s%N 2>/dev/null || true)
if [[ "$_ns_probe" =~ ^[0-9]+$ ]]; then
  _HAS_NS_PRECISION=true
else
  _HAS_NS_PRECISION=false
fi
if [[ "$VERBOSE" == true ]]; then
  if [[ "$_HAS_NS_PRECISION" == true ]]; then
    printf '[run.sh][DEBUG] - date supports %%N, using millisecond-precision timer\n'
  else
    printf '[run.sh][DEBUG] - date does not support %%N, falling back to whole-second timer precision\n'
  fi
fi

_now_ms() {
  if [[ "$_HAS_NS_PRECISION" == true ]]; then
    printf '%s' "$(( $(date +%s%N) / 1000000 ))"
  else
    printf '%s' "$(( SECONDS * 1000 ))"
  fi
}

# captured immediately after arg parsing (the earliest point VERBOSE is known)
# so this is the earliest possible moment to both start and log the timer
_RUN_START=$(_now_ms)
if [[ "$VERBOSE" == true ]]; then
  printf '[run.sh][DEBUG] - timer started\n'
fi

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

RUN_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"
PREFLIGHT_FILE=".bumfuzzle/config.yml"

. "$BUMFUZZLE_ROOT/scripts/reporting.sh"

printf '[run.sh][INFO] - starting bumfuzzle run v%s\n' "$RUN_VERSION"

printf '[run.sh][INFO] - starting prerequisites check\n'
section '-- Prerequisites --------------------------------------------------------'

if [[ ! -f "$PREFLIGHT_FILE" ]]; then
  TEMPLATE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
  if [[ ! -f "$TEMPLATE" ]]; then
    _flush_header
    printf '[run.sh][ERROR] - [FAIL] %s not found and template missing - cannot run validation\n' "$PREFLIGHT_FILE"
    exit 1
  fi
  if [[ "$VERBOSE" == true ]]; then
    printf '[run.sh][DEBUG] - creating directory %s\n' "$(dirname "$PREFLIGHT_FILE")"
  fi
  mkdir -p "$(dirname "$PREFLIGHT_FILE")"
  if [[ "$VERBOSE" == true ]]; then
    printf '[run.sh][DEBUG] - copying %s to %s\n' "$TEMPLATE" "$PREFLIGHT_FILE"
  fi
  cp "$TEMPLATE" "$PREFLIGHT_FILE"
  _flush_header
  printf '[run.sh][INFO] - %s not found - scaffolded from template (success)\n' "$PREFLIGHT_FILE"
else
  if [[ "$VERBOSE" == true ]]; then
    printf '[run.sh][DEBUG] - %s already present, using existing config\n' "$PREFLIGHT_FILE"
  fi
fi

pass "$PREFLIGHT_FILE is present"
pass "run v$RUN_VERSION"
printf '[run.sh][INFO] - prerequisites satisfied\n'

# PREFLIGHT_FILE becomes absolute below so checks work regardless of any cwd
# change; PREFLIGHT_FILE_DISPLAY keeps the plain relative name for messages,
# so [PASS]/[FAIL] lines never leak this machine's absolute path.
PREFLIGHT_FILE_DISPLAY="$PREFLIGHT_FILE"
PREFLIGHT_FILE="$(pwd)/$PREFLIGHT_FILE"

. "$BUMFUZZLE_ROOT/scripts/rule-runner.sh"

# config lint runs as part of Prerequisites (see rule-runner.sh): it validates
# .bumfuzzle/config.yml's own structure and is exempt from the enabled-rules gating
# that applies to user-defined rules — it always runs.
printf '[run.sh][INFO] - starting config lint\n'
config_lint_check

printf '[run.sh][INFO] - starting rule evaluation\n'
_pre_rules_pass=$_PASS_COUNT
_pre_rules_err=${#ERRORS[@]}
_pre_rules_warn=${#WARNINGS[@]}
user_rules_check
printf '[run.sh][INFO] - rule evaluation finished: %d passed, %d failed, %d warned\n' \
  "$(( _PASS_COUNT - _pre_rules_pass ))" "$(( ${#ERRORS[@]} - _pre_rules_err ))" "$(( ${#WARNINGS[@]} - _pre_rules_warn ))"

if [[ "$VERBOSE" == true ]]; then
  _elapsed_ms=$(( $(_now_ms) - _RUN_START ))
  printf '[run.sh][DEBUG] - timer stopped: scripts finished in %d.%03ds\n' "$(( _elapsed_ms / 1000 ))" "$(( _elapsed_ms % 1000 ))"
fi

if [[ ${#ERRORS[@]} -eq 0 ]]; then
  printf '[run.sh][INFO] - bumfuzzle run finished: PASS\n'
else
  printf '[run.sh][INFO] - bumfuzzle run finished: FAIL\n'
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
