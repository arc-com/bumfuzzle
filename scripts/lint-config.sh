#!/usr/bin/env bash
# lint-config.sh — structural lint for a bumfuzzle config (default
# bumfuzzle.yml): duplicate script/enum ids, dangling script/enum_ref
# references, rules missing a required field for their type,
# script_reusable arg mismatches against the script's declared args, bash
# syntax errors in embedded commands, and (delegating to
# scripts/validate-schema.sh) severity/on_missing/argType conformance
# against schema.yml. Runs standalone (`bumfuzzle lint-config [file]`) or
# as the first step of `bumfuzzle run`'s Prerequisites phase (see
# scripts/eval-rules.sh's config_lint_check), which always runs it
# regardless of the enabled-rules gating that applies to user-defined
# rules.
#
# Findings are tiered, one line per finding on stdout:
#   [FAIL:structural] msg — makes rule evaluation unreliable
#   [FAIL:error] msg      — reported, does not block evaluation
#   [FAIL:warn] msg       — reported, never blocks
#   [PASS] msg            — a check found nothing to report
# config_lint_check parses this tiering to decide which findings hard-stop
# `bumfuzzle run` (structural) versus which are only reported (error/warn) —
# see its comment for the exact mapping.
set -euo pipefail

SCRIPT_NAME="lint-config.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: lint-config.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to lint (default: bumfuzzle.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Lints TARGET's structure: duplicate script/enum ids, dangling script/enum_ref
references, rules missing a required field for their type, script_reusable
arg mismatches, bash syntax errors in embedded commands, and (delegating to
validate-schema.sh) schema conformance.

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
      printf 'lint-config.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'lint-config.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

TARGET="${TARGET:-bumfuzzle.yml}"

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }

_FINDINGS_STRUCTURAL=0
_FINDINGS_ERROR=0
_FINDINGS_WARN=0

_report_structural() {
  printf '[FAIL:structural] %s\n' "$1"
  _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1))
  _log DEBUG "structural finding: $1"
}
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "error finding: $1"
}
_report_warn() {
  printf '[FAIL:warn] %s\n' "$1"
  _FINDINGS_WARN=$((_FINDINGS_WARN + 1))
  _log DEBUG "warn finding: $1"
}

_lint_yq() { yq "$1" "$TARGET" 2>/dev/null || true; }
_lint_sha256() { command -v sha256sum &>/dev/null && sha256sum "$@" || shasum -a 256 "$@"; }

_lint_duplicate_ids() {
  _log DEBUG "checking duplicate ids in scripts/enums"
  local _ns _list _d
  for _ns in scripts enums; do
    _list=$(_lint_yq ".\"${_ns}\" | .. | select(type == \"!!map\") | select(has(\"id\")) | .id")
    while IFS= read -r _d; do
      [[ -z "$_d" ]] && continue
      _report_error "duplicate id '$_d' in ${_ns}:"
    done < <(printf '%s\n' "$_list" | grep -v '^$' | sort | uniq -d)
  done
}

_lint_reference_integrity() {
  _log DEBUG "checking script/enum_ref reference integrity"
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

_lint_rule_fields() {
  _log DEBUG "checking rule fields required by type"
  local _p _msg
  while IFS= read -r _p; do
    [[ -z "$_p" ]] && continue
    _report_structural "rules entry at .$_p has neither 'group' nor 'type'"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select((has("group") or has("type")) | not) | path | join(".")' | grep -v 'args$')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _report_structural "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(has("type")) | select(.type != "script_clean" and .type != "script_reusable") | "rule " + (.name // "?") + " has unknown type " + (.type | tostring)')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _report_structural "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_clean") | select(has("command") | not) | "script_clean rule " + (.name // "?") + " is missing required field: command"')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _report_structural "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_reusable") | select(has("script") | not) | "script_reusable rule " + (.name // "?") + " is missing required field: script"')

  while IFS= read -r _p; do
    [[ -z "$_p" ]] && continue
    _report_error "rule at .$_p is missing required field: name"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(has("type")) | select(has("name") | not) | path | join(".")')
}

_lint_script_args() {
  _log DEBUG "checking script_reusable arg declarations against script args"
  local _rule_lines _sid
  # every script_reusable rule as "script|name|ARG1,ARG2" lines
  _rule_lines=$(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_reusable") | (.script // "") + "|" + (.name // "unnamed") + "|" + ((.args // {}) | keys | join(","))')

  while IFS= read -r _sid; do
    [[ -z "$_sid" ]] && continue
    local _script_args _declared="" _required=""
    _script_args=$(_lint_yq "\"$_sid\" as \$sid | .scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \$sid) | .args[] | (.key // \"?\") + \" \" + ((.required // false) | tostring)")
    local _al _ak _areq
    while IFS= read -r _al; do
      [[ -z "$_al" ]] && continue
      _ak="${_al%% *}"
      _areq="${_al##* }"
      _declared="$_declared $_ak"
      [[ "$_areq" == "true" ]] && _required="$_required $_ak"
    done <<< "$_script_args"

    local _rs _rn _rkeys _req _rk
    while IFS='|' read -r _rs _rn _rkeys; do
      [[ "$_rs" == "$_sid" ]] || continue
      for _req in $_required; do
        case ",$_rkeys," in
          *",$_req,"*) ;;
          *) _report_error "rule '$_rn' is missing required arg '$_req' of script '$_sid'" ;;
        esac
      done
      for _rk in ${_rkeys//,/ }; do
        case " $_declared " in
          *" $_rk "*) ;;
          *) _report_error "rule '$_rn' passes arg '$_rk' not declared by script '$_sid'" ;;
        esac
      done
    done <<< "$_rule_lines"
  done < <(_lint_yq '.scripts | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u)
}

_lint_script_commands() {
  _log DEBUG "checking embedded command bash syntax and duplicate script commands"
  local _sid _cmd _sha _seen=""
  while IFS= read -r _sid; do
    [[ -z "$_sid" ]] && continue
    _cmd=$(_lint_yq "\"$_sid\" as \$sid | .scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \$sid) | .command // \"\"")
    if is_blank "$_cmd"; then
      _report_structural "script '$_sid' has no command"
      continue
    fi
    if ! printf '%s\n' "$_cmd" | bash -n 2>/dev/null; then
      _report_error "script '$_sid' has bash syntax errors"
    fi
    _sha=$(printf '%s' "$_cmd" | _lint_sha256 | awk '{print $1}')
    local _prev
    _prev=$(printf '%s\n' "$_seen" | grep "^$_sha " | head -1 | awk '{print $2}' || true)
    if [[ -n "$_prev" ]]; then
      _report_warn "scripts '$_prev' and '$_sid' have identical commands"
    else
      _seen="${_seen}${_sha} ${_sid}"$'\n'
    fi
  done < <(_lint_yq '.scripts | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u)

  local _rc_count _ri _rcmd _rname
  _rc_count=$(_lint_yq '[.rules | .. | select(type == "!!map") | select(.type == "script_clean")] | length')
  is_blank "$_rc_count" && _rc_count=0
  if [[ "$_rc_count" -gt 0 ]]; then
    for _ri in $(seq 0 $((_rc_count - 1))); do
      _rcmd=$(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_clean\")] | .[$_ri].command // \"\"")
      is_blank "$_rcmd" && continue # missing command is reported separately
      if ! printf '%s\n' "$_rcmd" | bash -n 2>/dev/null; then
        _rname=$(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_clean\")] | .[$_ri].name // \"?\"")
        _report_error "script_clean rule '$_rname' has bash syntax errors"
      fi
    done
  fi
}

# delegates to scripts/validate-schema.sh — the one place severity/on_missing/
# arg-type values are checked against schema.yml, so it behaves identically
# whether run standalone (`bumfuzzle validate-schema`) or here as part of
# config lint. Its findings are always structural: a config that doesn't
# conform to schema.yml can't be trusted to drive rule evaluation.
_lint_field_values() {
  _log DEBUG "checking field values against schema.yml (delegated to validate-schema.sh)"
  local _out _rc=0
  _out=$("$BUMFUZZLE_ROOT/scripts/validate-schema.sh" "$TARGET" 2>/dev/null) || _rc=$?
  [[ "$_rc" -eq 0 ]] && return 0
  while IFS= read -r _line; do
    [[ "$_line" == \[FAIL\]* ]] || continue
    _report_structural "${_line#"[FAIL] "}"
  done <<< "$_out"
}

if ! command -v yq &>/dev/null; then
  _report_structural "yq is not installed - required to lint $TARGET"
  _log ERROR "yq is not installed"
  exit 1
fi
if [[ ! -f "$TARGET" ]]; then
  _report_structural "$TARGET not found"
  _log ERROR "$TARGET not found"
  exit 1
fi

if ! yq '.' "$TARGET" > /dev/null 2>&1; then
  _report_structural "$TARGET is not parseable YAML"
  _log INFO "lint aborted - $TARGET is not parseable YAML"
  exit 1
fi
printf '[PASS] %s parses as YAML\n' "$TARGET"

_lint_duplicate_ids
_lint_reference_integrity
_lint_rule_fields
_lint_script_args
_lint_script_commands
_lint_field_values

if [[ "$_FINDINGS_STRUCTURAL" -gt 0 || "$_FINDINGS_ERROR" -gt 0 ]]; then
  _log INFO "lint failed: $_FINDINGS_STRUCTURAL structural, $_FINDINGS_ERROR error, $_FINDINGS_WARN warning finding(s)"
  exit 1
fi

printf '[PASS] %s is structurally clean\n' "$TARGET"
if [[ "$_FINDINGS_WARN" -gt 0 ]]; then
  _log INFO "lint passed with $_FINDINGS_WARN warning(s)"
else
  _log INFO "lint passed"
fi
exit 0
