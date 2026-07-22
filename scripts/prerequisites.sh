#!/usr/bin/env bash
# prerequisites.sh — runs every prerequisite check against a bumfuzzle
# config (default .bumfuzzle/config.yml): each check lives in its own
# atomic script under scripts/prerequisites/. Runs standalone (`bumfuzzle
# prerequisites [file]`) or as the first step of `bumfuzzle run` (see
# scripts/rule-runner.sh's config_lint_check), which always runs it
# regardless of the enabled-rules gating that applies to user-defined rules.
#
# Two phases:
#   1. Gates (yq-installed, target-exists, target-parses-yaml): every other
#      check queries TARGET's content with yq, which fails silently rather
#      than loudly on missing/unparseable input — so these three run
#      first, in order, and stop the whole run immediately on the first
#      failure since nothing after them can produce a meaningful result.
#   2. Checks (duplicate-ids, reference-integrity, rule-fields, script-args,
#      script-arg-types, script-commands, no-redundant-enabled-false,
#      validate-schema): each runs regardless of whether an earlier one
#      found something, so a single run surfaces every finding at once.
#
# Findings are tiered, one line per finding on stdout:
#   [FAIL:structural] msg — makes rule evaluation unreliable
#   [FAIL:error] msg      — reported, does not block evaluation
#   [FAIL:warn] msg       — reported, never blocks
#   [PASS] msg            — a check found nothing to report
# config_lint_check (scripts/rule-runner.sh) parses this tiering to decide
# which findings hard-stop `bumfuzzle run` (structural) versus which are
# only reported (error/warn) — see its comment for the exact mapping.
set -euo pipefail

SCRIPT_NAME="prerequisites.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: prerequisites.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Runs every check under scripts/prerequisites/ against TARGET.

Prints one line per finding to stdout:
  [FAIL:structural] message   — makes rule evaluation unreliable
  [FAIL:error] message        — reported, does not block evaluation
  [FAIL:warn] message         — reported, never blocks
  [PASS] message               — a check found nothing to report

Exits 0 if TARGET has no structural or error findings (warnings alone still
exit 0), 1 if it does, 2 on a usage error.
EOF
}

TARGET=""
_TARGET_SET=false
_SHOW_HELP=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      _SHOW_HELP=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -*)
      printf 'prerequisites.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'prerequisites.sh: unexpected extra argument: %s\n\n' "$1" >&2
        usage >&2
        exit 2
      fi
      TARGET="$1"
      _TARGET_SET=true
      shift
      ;;
  esac
done

if [[ "$_SHOW_HELP" == true ]]; then
  usage
  exit 0
fi

TARGET="${TARGET:-.bumfuzzle/config.yml}"
BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PREREQ_DIR="$BUMFUZZLE_ROOT/scripts/prerequisites"

_FINDINGS_STRUCTURAL=0
_FINDINGS_ERROR=0
_FINDINGS_WARN=0

_run_args=("$TARGET")
[[ "$VERBOSE" == true ]] && _run_args=(--verbose "$TARGET")

# _run_gate runs a gate script and, on failure, passes through its findings
# and stops the whole run immediately — nothing after it can produce a
# meaningful result once yq is missing or TARGET can't be read as YAML.
_run_gate() {
  local _script="$1" _out _rc=0
  _out=$("$PREREQ_DIR/$_script" "${_run_args[@]}") || _rc=$?
  if [[ "$_rc" -eq 2 ]]; then
    printf '%s\n' "$_out" >&2
    exit 2
  fi
  if [[ "$_rc" -ne 0 ]]; then
    while IFS= read -r _line; do
      [[ -z "$_line" ]] && continue
      printf '%s\n' "$_line"
      case "$_line" in
        '[FAIL:structural] '*) _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1)) ;;
      esac
    done <<< "$_out"
    _log INFO "$_script failed - stopping before the remaining checks"
    exit 1
  fi
  _log DEBUG "$_script: $_out"
}

# _run_check runs a non-gate check and passes through its tiered findings,
# but always continues to the next check regardless of the outcome.
_run_check() {
  local _script="$1" _out _rc=0
  _out=$("$PREREQ_DIR/$_script" "${_run_args[@]}") || _rc=$?
  while IFS= read -r _line; do
    case "$_line" in
      '[FAIL:structural] '*) printf '%s\n' "$_line"; _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1)) ;;
      '[FAIL:error] '*)      printf '%s\n' "$_line"; _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1)) ;;
      '[FAIL:warn] '*)       printf '%s\n' "$_line"; _FINDINGS_WARN=$((_FINDINGS_WARN + 1)) ;;
      '[PASS] '*)            printf '%s\n' "$_line" ;;
      '') ;;
      *) _log DEBUG "$_script: $_line" ;;
    esac
  done <<< "$_out"
}

# validate-schema.sh predates the tiered convention and is also a public
# command in its own right (`bumfuzzle validate-schema`), so it keeps its
# simpler [PASS]/[FAIL] contract; every finding it reports is structural (a
# config that doesn't conform to schema.yml can't be trusted to drive rule
# evaluation), and a passing run has nothing worth surfacing here since its
# own [PASS] line describes a narrower check ("matches schema.yml") than
# this script's own final summary.
_run_schema_check() {
  local _out _rc=0
  _out=$("$PREREQ_DIR/validate-schema.sh" "${_run_args[@]}") || _rc=$?
  [[ "$_rc" -eq 0 ]] && return 0
  while IFS= read -r _line; do
    [[ "$_line" == \[FAIL\]* ]] || continue
    printf '[FAIL:structural] %s\n' "${_line#"[FAIL] "}"
    _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1))
  done <<< "$_out"
}

_log INFO "starting prerequisites check of $TARGET"

_run_gate yq-installed.sh
_run_gate target-exists.sh
_run_gate target-parses-yaml.sh

_run_check duplicate-ids.sh
_run_check reference-integrity.sh
_run_check rule-fields.sh
_run_check script-args.sh
_run_check script-arg-types.sh
_run_check script-commands.sh
_run_check no-redundant-enabled-false.sh
_run_schema_check

if [[ "$_FINDINGS_STRUCTURAL" -gt 0 || "$_FINDINGS_ERROR" -gt 0 ]]; then
  _log INFO "prerequisites failed: $_FINDINGS_STRUCTURAL structural, $_FINDINGS_ERROR error, $_FINDINGS_WARN warning finding(s)"
  exit 1
fi

printf '[PASS] %s is structurally clean\n' "$TARGET"
if [[ "$_FINDINGS_WARN" -gt 0 ]]; then
  _log INFO "prerequisites passed with $_FINDINGS_WARN warning(s)"
else
  _log INFO "prerequisites passed"
fi
exit 0
