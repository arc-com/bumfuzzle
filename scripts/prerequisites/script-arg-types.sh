#!/usr/bin/env bash
# script-arg-types.sh — checks every script_reusable rule in TARGET (default
# .bumfuzzle/config.yml): every arg value it passes must actually conform to
# the type its referenced script declares for that arg key (int, double,
# bool, regex, path, or enum membership; string/glob accept anything). A
# list-typed arg's value is checked item by item. Key presence/matching is
# script-args.sh's job, not this one's.
set -euo pipefail

SCRIPT_NAME="script-arg-types.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: script-arg-types.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks every script_reusable rule's arg values against the type their
script declares for that arg. Prints [FAIL:error]/[PASS] lines to stdout;
exits 0 if none found, 1 if any are, 2 on a usage error.
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
      printf 'script-arg-types.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'script-arg-types.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

_FINDINGS_ERROR=0
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "error finding: $1"
}
_lint_yq() { yq "$1" "$TARGET" 2>/dev/null || true; }

# mirrors the three wrong examples in SKILL.md's Style Examples: no .., no
# doubled slashes, no redundant repeated ./ prefix, no trailing slash
# (unless the whole path is just "/").
_valid_path() {
  local _p="$1"
  [[ "$_p" =~ \.\. ]] && return 1
  [[ "$_p" == *"//"* ]] && return 1
  [[ "$_p" == *"././"* ]] && return 1
  [[ "$_p" == */ && "$_p" != "/" ]] && return 1
  return 0
}

_value_matches_type() {
  local _val="$1" _type="$2" _enum_ref="$3"
  case "$_type" in
    int)
      [[ "$_val" =~ ^-?[0-9]+$ ]]
      ;;
    double)
      [[ "$_val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
      ;;
    bool)
      [[ "$_val" == "true" || "$_val" == "false" ]]
      ;;
    regex)
      grep -E -e "$_val" </dev/null > /dev/null 2>&1
      [[ $? -ne 2 ]]
      ;;
    path)
      _valid_path "$_val"
      ;;
    enum)
      [[ -z "$_enum_ref" ]] && return 0
      local _ev _match=false
      while IFS= read -r _ev; do
        [[ -z "$_ev" ]] && continue
        [[ "$_ev" == "$_val" ]] && _match=true
      done < <(_lint_yq "\"$_enum_ref\" as \$eref | .enums | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \$eref) | .values[].value")
      [[ "$_match" == true ]]
      ;;
    *)
      return 0
      ;;
  esac
}

_check() {
  local _rc_count _ri _rn _sid _ak
  _rc_count=$(_lint_yq '[.rules | .. | select(type == "!!map") | select(.type == "script_reusable")] | length')
  [[ -z "$_rc_count" ]] && _rc_count=0
  [[ "$_rc_count" -eq 0 ]] && return 0

  for _ri in $(seq 0 $((_rc_count - 1))); do
    _rn=$(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_reusable\")] | .[$_ri].name // \"unnamed\"")
    _sid=$(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_reusable\")] | .[$_ri].script // \"\"")
    [[ -z "$_sid" ]] && continue

    while IFS= read -r _ak; do
      [[ -z "$_ak" ]] && continue

      local _meta _atype _aenumref
      _meta=$(_lint_yq "\"$_sid\" as \$sid | \"$_ak\" as \$ak | .scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \$sid) | .args[] | select(.key == \$ak) | (.type // \"string\") + \"|\" + (.enum_ref // \"\")")
      [[ -z "$_meta" ]] && continue # unknown arg key, script-args.sh's job to report
      _atype="${_meta%%|*}"
      _aenumref="${_meta##*|}"
      [[ "$_atype" == "string" || "$_atype" == "glob" ]] && continue # accept anything

      local _atag
      _atag=$(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_reusable\")] | .[$_ri].args.$_ak | tag")

      local _av
      if [[ "$_atag" == "!!seq" ]]; then
        while IFS= read -r _av; do
          [[ -z "$_av" ]] && continue
          _value_matches_type "$_av" "$_atype" "$_aenumref" \
            || _report_error "rule '$_rn' passes '$_av' for arg '$_ak', not a valid $_atype"
        done < <(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_reusable\")] | .[$_ri].args.$_ak[]")
      else
        _av=$(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_reusable\")] | .[$_ri].args.$_ak")
        [[ -z "$_av" ]] && continue
        _value_matches_type "$_av" "$_atype" "$_aenumref" \
          || _report_error "rule '$_rn' passes '$_av' for arg '$_ak', not a valid $_atype"
      fi
    done < <(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_reusable\")] | .[$_ri].args // {} | keys | .[]")
  done
}

_log INFO "checking script_reusable arg values against their declared types in $TARGET"
_check

if [[ "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf "[PASS] all script_reusable arg values in %s match their declared types\n" "$TARGET"
exit 0
