#!/usr/bin/env bash
# reference-integrity.sh — checks that every script_reusable rule's `script`
# value resolves to a declared script id, and every `enum_ref` resolves to a
# declared enum id, in TARGET (default .bumfuzzle/config.yml). A dangling
# script reference makes rule evaluation unreliable (structural); a dangling
# enum_ref only affects the wizard's dropdown, not rule evaluation (error).
set -euo pipefail

SCRIPT_NAME="reference-integrity.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: reference-integrity.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks that every script_reusable rule's script reference, and every
enum_ref, resolves to a declared id in TARGET. Prints
[FAIL:structural]/[FAIL:error]/[PASS] lines to stdout; exits 0 if none
found, 1 if any are, 2 on a usage error.
EOF
}

parse_target_args "$@"

_FINDINGS_STRUCTURAL=0
_FINDINGS_ERROR=0
_report_structural() {
  printf '[FAIL:structural] %s\n' "$1"
  _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1))
  _log DEBUG "Structural finding: $1"
}
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "Error finding: $1"
}

_check() {
  local _miss
  while IFS= read -r _miss; do
    [[ -z "$_miss" ]] && continue
    _report_structural "rule references unknown script '$_miss'"
  done < <(comm -23 \
    <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_reusable") | .script // ""' | grep -v '^$' | sort -u) \
    <(_lint_yq '.scripts | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u))

  # enum refs don't affect rule execution (wizard-only), so broken ones are
  # errors rather than structural aborts
  while IFS= read -r _miss; do
    [[ -z "$_miss" ]] && continue
    _report_error "unknown enum_ref '$_miss'"
  done < <(comm -23 \
    <(_lint_yq '.. | select(type == "!!map") | select(has("enum_ref")) | .enum_ref' | grep -v '^$' | sort -u) \
    <(_lint_yq '.enums | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u))
}

_log DEBUG "Target: $TARGET"
_log INFO "Checking script/enum_ref reference integrity"
_check

if [[ "$_FINDINGS_STRUCTURAL" -gt 0 || "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] all script/enum_ref references in %s resolve\n' "$TARGET"
exit 0
