# eval-rules — walk the rules: tree from bumfuzzle.yml and run each check

# ruleType is read from the shared schema (schema.yml, $defs.ruleType)
# — the single source of truth also read by the wizard (index.html) — instead
# of being hardcoded here too. severity/onMissing/argType are likewise
# schema-driven but validated by scripts/validate-schema.sh, not duplicated
# here — see _lint_field_values below.
_URULE_VALID_TYPES=$(yq '.["$defs"].ruleType.enum | join(" ")' "$BUMFUZZLE_ROOT/schema.yml")

_urule_pass() {
  if [[ "$VERBOSE" == true ]]; then
    _flush_header
    printf '[PASS] %s\n' "$1"
  fi
}

_urule_instruction() {
  local _path="$1"
  local _instr
  _instr=$(yq "${_path}.instruction // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  is_blank "$_instr" && return
  printf '    → %s\n' "$_instr"
}


_urule_process_rule() {
  local _path="$1"

  local _type _name _desc _command _sev _enabled
  _enabled=$(yq "${_path}.enabled | tostring"         "$PREFLIGHT_FILE" 2>/dev/null || echo null)
  if [[ "$_enabled" != "true" ]]; then return; fi
  _type=$(yq    "${_path}.type              // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _name=$(yq    "${_path}.name              // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _desc=$(yq    "${_path}.description       // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _command=$(yq "${_path}.command           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _sev=$(yq     "${_path}.severity // \"error\""     "$PREFLIGHT_FILE" 2>/dev/null || echo error)

  is_blank "$_type" && { fail "${_path}: missing required field 'type'" error; return; }

  local _known=false _t
  for _t in $_URULE_VALID_TYPES; do [[ "$_t" == "$_type" ]] && _known=true && break; done
  [[ "$_known" == false ]] && { fail "${_path}: unknown type '$_type'" error; return; }

  local _label="${_name:-${_desc:-${_path} ($_type)}}"

  # requires: <binary> gates the rule on an external tool being installed;
  # on_missing decides what happens when it is not: skip | warn (default) | fail
  local _requires
  _requires=$(yq "${_path}.requires // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  if ! is_blank "$_requires" && ! command -v "$_requires" &>/dev/null; then
    local _on_missing
    _on_missing=$(yq "${_path}.on_missing // \"warn\"" "$PREFLIGHT_FILE" 2>/dev/null || echo warn)
    case "$_on_missing" in
      skip)
        if [[ "$VERBOSE" == true ]]; then
          _flush_header
          printf '[SKIP] %s (%s not installed)\n' "$_label" "$_requires"
        fi
        ;;
      fail)
        _flush_header
        _urule_instruction "$_path"
        fail "$_label: required tool '$_requires' is not installed" "$_sev"
        ;;
      *)
        fail "$_label: skipped — required tool '$_requires' is not installed" warn
        ;;
    esac
    return
  fi

  case "$_type" in
    script_clean)
      is_blank "$_command" && { fail "$_label: 'command' is required" error; return; }
      local _out _ec=0
      _out=$(eval "$_command" 2>&1) || _ec=$?
      if [[ "$_ec" -eq 0 ]]; then
        _urule_pass "$_label"
      else
        # print instruction/output before fail(), since fail() exits immediately
        # for severity: hard-stop and would otherwise swallow both.
        # flush the section header first so it still appears before them.
        _flush_header
        _urule_instruction "$_path"
        if [[ "$VERBOSE" == true && -n "$_out" ]]; then
          printf '%s\n' "$_out" | sed 's/^/    /' >&2
        fi
        fail "$_label: command exited $_ec" "$_sev"
      fi
      ;;

    script_reusable)
      local _script_id _script_cmd
      _script_id=$(yq "${_path}.script // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
      is_blank "$_script_id" && { fail "$_label: 'script' id is required" error; return; }
      _script_cmd=$(yq ".scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \"$_script_id\") | .command // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
      is_blank "$_script_cmd" && { fail "$_label: reusable script '$_script_id' not found or has no command" error; return; }

      # unset all vars declared by this script so optional args not provided by the
      # rule don't inherit stale values from a previous rule execution.
      local _script_base="\"$_script_id\" as \$sid | .scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \$sid)"
      local _sk
      while IFS= read -r _sk; do
        is_blank "$_sk" && continue
        unset "$_sk" 2>/dev/null || true
      done < <(yq "${_script_base} | .args[]?.key // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)

      # export each arg provided by the rule as an env var; arrays are joined
      # newline-separated so entries (e.g. regexes) may contain spaces —
      # scripts consume them with `while IFS= read -r`.
      local _arg_keys _ak _av _av_type
      _arg_keys=$(yq "${_path}.args | keys | .[]" "$PREFLIGHT_FILE" 2>/dev/null || true)
      while IFS= read -r _ak; do
        is_blank "$_ak" && continue
        _av_type=$(yq "${_path}.args.${_ak} | tag" "$PREFLIGHT_FILE" 2>/dev/null || true)
        if [[ "$_av_type" == "!!seq" ]]; then
          _av=$(yq "${_path}.args.${_ak}[]" "$PREFLIGHT_FILE" 2>/dev/null || true)
        else
          _av=$(yq "${_path}.args.${_ak} // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
        fi
        export "${_ak}=${_av}"
      done <<< "$_arg_keys"

      local _out _ec=0
      _out=$(eval "$_script_cmd" 2>&1) || _ec=$?
      if [[ "$_ec" -eq 0 ]]; then
        _urule_pass "$_label"
      else
        # print instruction/output before fail(), since fail() exits immediately
        # for severity: hard-stop and would otherwise swallow both.
        # flush the section header first so it still appears before them.
        _flush_header
        _urule_instruction "$_path"
        if [[ "$VERBOSE" == true && -n "$_out" ]]; then
          printf '%s\n' "$_out" | sed 's/^/    /' >&2
        fi
        fail "$_label: command exited $_ec" "$_sev"
      fi
      ;;
  esac
}

_urule_walk() {
  local _base="$1"
  local _count
  _count=$(yq "${_base} | length" "$PREFLIGHT_FILE" 2>/dev/null || echo 0)
  [[ "$_count" -eq 0 ]] && return 0

  local _i
  for _i in $(seq 0 $((_count - 1))); do
    local _path="${_base}[${_i}]"
    local _group_name
    _group_name=$(yq "${_path}.group // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
    if ! is_blank "$_group_name"; then
      section "-- ${_group_name} $(printf '%0.s-' {1..40})" 2>/dev/null || \
        printf '\n-- %s\n' "$_group_name"
      _urule_walk "${_path}.rules"
    else
      _urule_process_rule "$_path"
    fi
  done
}

user_rules_check() {
  local _count
  _count=$(yq '.rules | length' "$PREFLIGHT_FILE" 2>/dev/null || echo 0)
  [[ "$_count" -eq 0 ]] && return 0

  section '-- Rules ----------------------------------------------------------------'
  _urule_walk '.rules'
}

# config lint — validate the structure of bumfuzzle.yml itself before any rule
# runs. Structural problems (broken references, malformed rules) make rule
# evaluation unreliable, so they abort preflight after all of them are printed.

_LINT_STRUCTURAL=0

_lint_yq() { yq "$1" "$PREFLIGHT_FILE" 2>/dev/null || true; }

_lint_structural_fail() {
  _flush_header
  printf '[FAIL] %s\n' "$1"
  _LINT_STRUCTURAL=$((_LINT_STRUCTURAL + 1))
}

_lint_sha256() { command -v sha256sum &>/dev/null && sha256sum "$@" || shasum -a 256 "$@"; }

_lint_duplicate_ids() {
  local _ns _list _d
  for _ns in scripts enums; do
    _list=$(_lint_yq ".\"${_ns}\" | .. | select(type == \"!!map\") | select(has(\"id\")) | .id")
    while IFS= read -r _d; do
      [[ -z "$_d" ]] && continue
      fail "duplicate id '$_d' in ${_ns}:" error
    done < <(printf '%s\n' "$_list" | grep -v '^$' | sort | uniq -d)
  done
}

_lint_reference_integrity() {
  local _miss
  while IFS= read -r _miss; do
    [[ -z "$_miss" ]] && continue
    _lint_structural_fail "rule references unknown script '$_miss'"
  done < <(comm -23 \
    <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_reusable") | .script // ""' | grep -v '^$' | sort -u) \
    <(_lint_yq '.scripts | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u))

  # enum refs don't affect rule execution (wizard-only), so broken ones are
  # errors rather than structural aborts
  while IFS= read -r _miss; do
    [[ -z "$_miss" ]] && continue
    fail "unknown enum_ref '$_miss'" error
  done < <(comm -23 \
    <(_lint_yq '.. | select(type == "!!map") | select(has("enum_ref")) | .enum_ref' | grep -v '^$' | sort -u) \
    <(_lint_yq '.enums | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u))
}

_lint_rule_fields() {
  local _p _msg
  while IFS= read -r _p; do
    [[ -z "$_p" ]] && continue
    _lint_structural_fail "rules entry at .$_p has neither 'group' nor 'type'"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select((has("group") or has("type")) | not) | path | join(".")' | grep -v 'args$')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _lint_structural_fail "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(has("type")) | select(.type != "script_clean" and .type != "script_reusable") | "rule " + (.name // "?") + " has unknown type " + (.type | tostring)')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _lint_structural_fail "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_clean") | select(has("command") | not) | "script_clean rule " + (.name // "?") + " is missing required field: command"')

  while IFS= read -r _msg; do
    [[ -z "$_msg" ]] && continue
    _lint_structural_fail "$_msg"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_reusable") | select(has("script") | not) | "script_reusable rule " + (.name // "?") + " is missing required field: script"')

  while IFS= read -r _p; do
    [[ -z "$_p" ]] && continue
    fail "rule at .$_p is missing required field: name" error
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(has("type")) | select(has("name") | not) | path | join(".")')
}

_lint_script_args() {
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
          *) fail "rule '$_rn' is missing required arg '$_req' of script '$_sid'" error ;;
        esac
      done
      for _rk in ${_rkeys//,/ }; do
        case " $_declared " in
          *" $_rk "*) ;;
          *) fail "rule '$_rn' passes arg '$_rk' not declared by script '$_sid'" error ;;
        esac
      done
    done <<< "$_rule_lines"
  done < <(_lint_yq '.scripts | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u)
}

_lint_script_commands() {
  local _sid _cmd _sha _seen=""
  while IFS= read -r _sid; do
    [[ -z "$_sid" ]] && continue
    _cmd=$(_lint_yq "\"$_sid\" as \$sid | .scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \$sid) | .command // \"\"")
    if is_blank "$_cmd"; then
      _lint_structural_fail "script '$_sid' has no command"
      continue
    fi
    if ! printf '%s\n' "$_cmd" | bash -n 2>/dev/null; then
      fail "script '$_sid' has bash syntax errors" error
    fi
    _sha=$(printf '%s' "$_cmd" | _lint_sha256 | awk '{print $1}')
    local _prev
    _prev=$(printf '%s\n' "$_seen" | grep "^$_sha " | head -1 | awk '{print $2}' || true)
    if [[ -n "$_prev" ]]; then
      fail "scripts '$_prev' and '$_sid' have identical commands" warn
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
        fail "script_clean rule '$_rname' has bash syntax errors" error
      fi
    done
  fi
}

# delegates to scripts/validate-schema.sh — the one place severity/on_missing/
# arg-type values are checked against schema.yml, so it behaves
# identically whether run standalone (`bumfuzzle validate-schema`) or here as
# part of config lint.
_lint_field_values() {
  local _out _rc=0
  _out=$("$BUMFUZZLE_ROOT/scripts/validate-schema.sh" "$PREFLIGHT_FILE") || _rc=$?
  [[ "$_rc" -eq 0 ]] && return 0
  while IFS= read -r _line; do
    [[ "$_line" == \[FAIL\]* ]] || continue
    _lint_structural_fail "${_line#"[FAIL] "}"
  done <<< "$_out"
}

# part of run.sh's Prerequisites phase (see the comment at its call site) —
# no section() call here so its [PASS]/[FAIL] lines group under the same
# '-- Prerequisites --' banner rather than opening a separate one.
config_lint_check() {
  _LINT_STRUCTURAL=0

  if ! yq '.' "$PREFLIGHT_FILE" > /dev/null 2>&1; then
    fail "$PREFLIGHT_FILE is not parseable YAML" hard-stop
  fi
  pass "$PREFLIGHT_FILE parses as YAML"

  _lint_duplicate_ids
  _lint_reference_integrity
  _lint_rule_fields
  _lint_script_args
  _lint_script_commands
  _lint_field_values

  if [[ "$_LINT_STRUCTURAL" -gt 0 ]]; then
    fail "config lint found $_LINT_STRUCTURAL structural error(s) in $PREFLIGHT_FILE — rules were not evaluated" hard-stop
  fi
  pass "config lint"
}
