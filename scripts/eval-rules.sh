# eval-rules — walk the rules: tree from .bumfuzzle/config.yml and run each check

# ruleType is read from the shared schema (schema.yml, $defs.ruleType)
# — the single source of truth also read by the wizard (index.html) — instead
# of being hardcoded here too. severity/onMissing/argType are likewise
# schema-driven but validated by scripts/validate-schema.sh, not duplicated
# here — see scripts/lint-config.sh's _lint_field_values.
_URULE_VALID_TYPES=$(yq '.["$defs"].ruleType.enum | join(" ")' "$BUMFUZZLE_ROOT/schema.yml")

_urule_pass() {
  _PASS_COUNT=$((_PASS_COUNT + 1))
  if [[ "$VERBOSE" == true ]]; then
    _flush_header
    printf '[run.sh][DEBUG] - [PASS] %s\n' "$1"
  fi
}

_urule_instruction() {
  local _path="$1"
  local _instr
  _instr=$(yq "${_path}.instruction // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  is_blank "$_instr" && return
  printf '    → %s\n' "$_instr"
}


# shared by script_clean/script_reusable failure paths: builds the
# instruction + (verbose) command output as fail()'s details block, so
# it prints after the [WARN]/[FAIL] tag but still ahead of a hard-stop exit.
_urule_report_failure() {
  local _label="$1" _ec="$2" _sev="$3" _path="$4" _out="$5"
  local _details
  _details=$(_urule_instruction "$_path")
  if [[ "$VERBOSE" == true && -n "$_out" ]]; then
    local _out_indented
    _out_indented=$(printf '%s\n' "$_out" | sed 's/^/    /')
    _details="${_details:+$_details$'\n'}${_out_indented}"
  fi
  fail "$_label: command exited $_ec" "$_sev" "$_details"
}

_urule_process_rule() {
  local _path="$1"

  local _type _name _desc _command _sev _enabled
  _name=$(yq    "${_path}.name              // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _enabled=$(yq "${_path}.enabled | tostring"         "$PREFLIGHT_FILE" 2>/dev/null || echo null)
  if [[ "$_enabled" != "true" ]]; then
    if [[ "$VERBOSE" == true ]]; then
      _flush_header
      printf '[run.sh][DEBUG] - [SKIP] %s (disabled)\n' "${_name:-$_path}"
    fi
    return
  fi
  if [[ "$VERBOSE" == true ]]; then
    printf '[run.sh][DEBUG] - %s is enabled, proceeding\n' "${_name:-$_path}"
  fi
  _type=$(yq    "${_path}.type              // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _desc=$(yq    "${_path}.description       // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _command=$(yq "${_path}.command           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _sev=$(yq     "${_path}.severity // \"error\""     "$PREFLIGHT_FILE" 2>/dev/null || echo error)

  is_blank "$_type" && { fail "${_path}: missing required field 'type'" error; return; }

  local _known=false _t
  for _t in $_URULE_VALID_TYPES; do [[ "$_t" == "$_type" ]] && _known=true && break; done
  [[ "$_known" == false ]] && { fail "${_path}: unknown type '$_type'" error; return; }

  local _label="${_name:-${_desc:-${_path} ($_type)}}"
  if [[ "$VERBOSE" == true ]]; then
    printf '[run.sh][DEBUG] - %s has known type '\''%s'\''\n' "$_label" "$_type"
  fi

  # requires: <binary> gates the rule on an external tool being installed;
  # on_missing decides what happens when it is not: skip | warn (default) | fail
  local _requires
  _requires=$(yq "${_path}.requires // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  if ! is_blank "$_requires"; then
    if ! command -v "$_requires" &>/dev/null; then
      local _on_missing
      _on_missing=$(yq "${_path}.on_missing // \"warn\"" "$PREFLIGHT_FILE" 2>/dev/null || echo warn)
      case "$_on_missing" in
        skip)
          if [[ "$VERBOSE" == true ]]; then
            _flush_header
            printf '[run.sh][DEBUG] - [SKIP] %s (%s not installed)\n' "$_label" "$_requires"
          fi
          ;;
        fail)
          local _details
          _details=$(_urule_instruction "$_path")
          fail "$_label: required tool '$_requires' is not installed" "$_sev" "$_details"
          ;;
        *)
          fail "$_label: skipped — required tool '$_requires' is not installed" warn
          ;;
      esac
      return
    elif [[ "$VERBOSE" == true ]]; then
      printf '[run.sh][DEBUG] - required tool '\''%s'\'' found for %s\n' "$_requires" "$_label"
    fi
  fi

  case "$_type" in
    script_clean)
      is_blank "$_command" && { fail "$_label: 'command' is required" error; return; }
      if [[ "$VERBOSE" == true ]]; then
        printf '[run.sh][DEBUG] - running %s: %s\n' "$_label" "$_command"
      fi
      local _out _ec=0
      _out=$(eval "$_command" 2>&1) || _ec=$?
      if [[ "$VERBOSE" == true ]]; then
        printf '[run.sh][DEBUG] - %s exited %s\n' "$_label" "$_ec"
      fi
      if [[ "$_ec" -eq 0 ]]; then
        _urule_pass "$_label"
      else
        _urule_report_failure "$_label" "$_ec" "$_sev" "$_path" "$_out"
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
      local _arg_keys _ak _av _av_type _args_summary=""
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
        _args_summary="${_args_summary}${_args_summary:+, }${_ak}=${_av//$'\n'/;}"
      done <<< "$_arg_keys"

      if [[ "$VERBOSE" == true && -n "$_args_summary" ]]; then
        printf '[run.sh][DEBUG] - %s args: %s\n' "$_label" "$_args_summary"
      fi

      if [[ "$VERBOSE" == true ]]; then
        printf '[run.sh][DEBUG] - running %s (script: %s): %s\n' "$_label" "$_script_id" "$_script_cmd"
      fi
      local _out _ec=0
      _out=$(eval "$_script_cmd" 2>&1) || _ec=$?
      if [[ "$VERBOSE" == true ]]; then
        printf '[run.sh][DEBUG] - %s exited %s\n' "$_label" "$_ec"
      fi
      if [[ "$_ec" -eq 0 ]]; then
        _urule_pass "$_label"
      else
        _urule_report_failure "$_label" "$_ec" "$_sev" "$_path" "$_out"
      fi
      ;;

    *)
      # unreachable while _URULE_VALID_TYPES only lists script_clean/script_reusable
      # (see schema.yml's ruleType enum) — kept so a future third type added to
      # the enum without a matching arm here fails loudly instead of silently
      # no-op'ing past the _known check above.
      fail "$_label: type '$_type' passed validation but has no handler in eval-rules.sh" error
      ;;
  esac
}

_urule_walk() {
  local _base="$1"
  local _count
  _count=$(yq "${_base} | length" "$PREFLIGHT_FILE" 2>/dev/null || echo 0)
  if [[ "$_count" -eq 0 ]]; then
    if [[ "$VERBOSE" == true ]]; then
      printf '[run.sh][DEBUG] - %s is empty, nothing to walk\n' "$_base"
    fi
    return 0
  fi

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
  if [[ "$_count" -eq 0 ]]; then
    if [[ "$VERBOSE" == true ]]; then
      printf '[run.sh][DEBUG] - no rules configured, skipping rule evaluation\n'
    fi
    return 0
  fi

  section '-- Rules ----------------------------------------------------------------'
  _urule_walk '.rules'
}

# config lint — delegates to scripts/lint-config.sh, the atomic script that
# checks .bumfuzzle/config.yml's own structure (duplicate ids, dangling references,
# per-type required fields, script_reusable arg mismatches, embedded bash
# syntax, and schema conformance) before any rule runs. This function only
# translates lint-config.sh's tiered stdout ([FAIL:structural]/[FAIL:error]/
# [FAIL:warn]) into run.sh's pass/fail/warn reporting: structural findings
# make rule evaluation unreliable, so they abort preflight after all of them
# are printed; error/warn findings are reported but don't block evaluation.

_LINT_STRUCTURAL=0

_lint_structural_fail() {
  _flush_header
  printf '[run.sh][ERROR] - [FAIL] %s\n' "$1"
  _LINT_STRUCTURAL=$((_LINT_STRUCTURAL + 1))
}

# part of run.sh's Prerequisites phase (see the comment at its call site) —
# no section() call here so its [PASS]/[FAIL] lines group under the same
# '-- Prerequisites --' banner rather than opening a separate one.
config_lint_check() {
  _LINT_STRUCTURAL=0

  if [[ "$VERBOSE" == true ]]; then
    printf '[run.sh][DEBUG] - running scripts/lint-config.sh against %s\n' "$PREFLIGHT_FILE_DISPLAY"
  fi
  local _lint_args=("$PREFLIGHT_FILE")
  [[ "$VERBOSE" == true ]] && _lint_args=(--verbose "$PREFLIGHT_FILE")

  # lint-config.sh's own stderr is never discarded here: its _log() already
  # self-gates DEBUG on its own --verbose (passed through above), and its
  # INFO/ERROR lines must always reach the terminal regardless of ours
  local _out _rc=0
  _out=$("$BUMFUZZLE_ROOT/scripts/lint-config.sh" "${_lint_args[@]}") || _rc=$?
  if [[ "$VERBOSE" == true ]]; then
    printf '[run.sh][DEBUG] - lint-config.sh exited %s\n' "$_rc"
  fi
  if [[ "$_rc" -eq 2 ]]; then
    fail "lint-config.sh: usage error — see stderr" hard-stop
    return
  fi

  local _line
  while IFS= read -r _line; do
    case "$_line" in
      '[FAIL:structural] '*) _lint_structural_fail "${_line#'[FAIL:structural] '}" ;;
      '[FAIL:error] '*)      fail "${_line#'[FAIL:error] '}" error ;;
      '[FAIL:warn] '*)       fail "${_line#'[FAIL:warn] '}" warn ;;
      '') ;;
      *)
        if [[ "$VERBOSE" == true ]]; then
          printf '[run.sh][DEBUG] - lint-config.sh: %s\n' "$_line"
        fi
        ;;
    esac
  done <<< "$_out"

  if [[ "$_LINT_STRUCTURAL" -gt 0 ]]; then
    fail "config lint found $_LINT_STRUCTURAL structural error(s) in $PREFLIGHT_FILE_DISPLAY — rules were not evaluated" hard-stop
  fi
  pass "config lint"
}
