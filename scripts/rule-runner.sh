# rule-runner — walk the rules: tree from .bumfuzzle/config.yml and run each check

_urule_pass() {
  _PASS_COUNT=$((_PASS_COUNT + 1))
  _flush_header
  if [[ "$VERBOSE" == true ]]; then
    _log DEBUG "[PASS] $1"
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

# _urule_lookup_manifest PATH — reads (enabled, name) for PATH out of
# $_URULE_MANIFEST, a bulk-fetched "path|enabled|name" listing built once by
# user_rules_check. Pure in-bash linear scan, no subprocess spawned, so a
# rule's enabled/disabled decision never costs a yq call — with hundreds of
# rules this used to be the dominant per-rule cost even for disabled ones.
_urule_lookup_manifest() {
  local _target_path="$1" _p _en _nm
  while IFS='|' read -r _p _en _nm; do
    if [[ "$_p" == "$_target_path" ]]; then
      printf '%s\t%s\n' "$_en" "$_nm"
      return 0
    fi
  done <<< "$_URULE_MANIFEST"
  printf 'false\t\n'
}

_urule_process_rule() {
  local _path="$1"

  local _type _name _desc _command _sev _enabled _looked_up
  _looked_up=$(_urule_lookup_manifest "$_path")
  _enabled="${_looked_up%%$'\t'*}"
  _name="${_looked_up#*$'\t'}"
  if [[ "$_enabled" != "true" ]]; then
    if [[ "$VERBOSE" == true ]]; then
      _flush_header
      _log DEBUG "[SKIP] ${_name:-$_path} (disabled)"
    fi
    return
  fi
  _log DEBUG "Enabled, proceeding: ${_name:-$_path}"
  _type=$(yq    "${_path}.type              // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _desc=$(yq    "${_path}.description       // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _command=$(yq "${_path}.command           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _sev=$(yq     "${_path}.severity // \"error\""     "$PREFLIGHT_FILE" 2>/dev/null || echo error)

  is_blank "$_type" && { fail "${_path}: missing required field 'type'" error; return; }

  local _known=false _t
  for _t in $_URULE_VALID_TYPES; do [[ "$_t" == "$_type" ]] && _known=true && break; done
  [[ "$_known" == false ]] && { fail "${_path}: unknown type '$_type'" error; return; }

  local _label="${_name:-${_desc:-${_path} ($_type)}}"
  _log DEBUG "Known type '$_type' for $_label"

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
            _log DEBUG "[SKIP] $_label ($_requires not installed)"
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
    else
      _log DEBUG "Required tool '$_requires' found for $_label"
    fi
  fi

  case "$_type" in
    script_clean)
      is_blank "$_command" && { fail "$_label: 'command' is required" error; return; }
      _log DEBUG "Running $_label: $_command"
      local _out _ec=0
      _out=$(eval "$_command" 2>&1) || _ec=$?
      _log DEBUG "Command for $_label exited $_ec"
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

      [[ -n "$_args_summary" ]] && _log DEBUG "Args for $_label: $_args_summary"

      _log DEBUG "Running $_label (script: $_script_id): $_script_cmd"
      local _out _ec=0
      _out=$(eval "$_script_cmd" 2>&1) || _ec=$?
      _log DEBUG "Command for $_label exited $_ec"
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
      fail "$_label: type '$_type' passed validation but has no handler in rule-runner.sh" error
      ;;
  esac
}

_urule_walk() {
  local _base="$1"
  local _count
  _count=$(yq "${_base} | length" "$PREFLIGHT_FILE" 2>/dev/null || echo 0)
  if [[ "$_count" -eq 0 ]]; then
    _log DEBUG "Empty, nothing to walk: $_base"
    return 0
  fi

  local _i
  for _i in $(seq 0 $((_count - 1))); do
    local _path="${_base}.${_i}"
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
    _log DEBUG "No rules configured, skipping rule evaluation"
    return 0
  fi

  # computed here, not at source time: this is the earliest point config_lint_check
  # (which hard-stops via prerequisites.sh's yq-installed gate if yq is missing)
  # is guaranteed to have already run, so this is safe to call unconditionally.
  # ruleType is read from the shared schema (schema.yml, $defs.ruleType) — the
  # single source of truth also read by the wizard (index.html) — instead of
  # being hardcoded here too. severity/onMissing/argType are likewise
  # schema-driven but validated by scripts/prerequisites/validate-schema.sh,
  # not duplicated here — see scripts/prerequisites.sh's _run_schema_check.
  _URULE_VALID_TYPES=$(yq '.["$defs"].ruleType.enum | join(" ")' "$BUMFUZZLE_ROOT/schema.yml")

  local _manifest_start_ms _manifest_ms
  _manifest_start_ms=$(_now_ms)
  _URULE_MANIFEST=$(yq '.rules | .. | select(type == "!!map") | select(has("type")) | ("." + (path | join("."))) + "|" + ((.enabled // false) | tostring) + "|" + (.name // "unnamed")' "$PREFLIGHT_FILE" 2>/dev/null || true)
  _manifest_ms=$(( $(_now_ms) - _manifest_start_ms ))
  _log DEBUG "TAG::PERF Fetched enabled/name manifest for all rules in ${_manifest_ms}ms"

  section '-- Rules ----------------------------------------------------------------'
  _urule_walk '.rules'
}

# config lint — delegates to scripts/prerequisites.sh, the orchestrator that
# runs each atomic check under scripts/prerequisites/ (duplicate ids,
# dangling references, per-type required fields, script_reusable arg
# mismatches, embedded bash syntax, and schema conformance) before any rule
# runs. This function only translates prerequisites.sh's tiered stdout
# ([FAIL:structural]/[FAIL:error]/[FAIL:warn]) into run.sh's pass/fail/warn
# reporting: structural findings make rule evaluation unreliable, so they
# abort preflight after all of them are printed; error/warn findings are
# reported but don't block evaluation.

_LINT_STRUCTURAL=0

_lint_structural_fail() {
  _flush_header
  _log ERROR "[FAIL] $1"
  _LINT_STRUCTURAL=$((_LINT_STRUCTURAL + 1))
}

# part of run.sh's Prerequisites phase (see the comment at its call site) —
# no section() call here so its [PASS]/[FAIL] lines group under the same
# '-- Prerequisites --' banner rather than opening a separate one.
config_lint_check() {
  _LINT_STRUCTURAL=0

  _log DEBUG "Running scripts/prerequisites.sh against $PREFLIGHT_FILE_DISPLAY"
  local _lint_args=("$PREFLIGHT_FILE")
  [[ "$VERBOSE" == true ]] && _lint_args=(--verbose "$PREFLIGHT_FILE")

  # prerequisites.sh's own stderr is never discarded here: its _log() already
  # self-gates DEBUG on its own --verbose (passed through above), and its
  # INFO/ERROR lines must always reach the terminal regardless of ours
  local _out _rc=0
  _out=$("$BUMFUZZLE_ROOT/scripts/prerequisites.sh" "${_lint_args[@]}") || _rc=$?
  _log DEBUG "Prerequisites.sh exited $_rc"
  if [[ "$_rc" -eq 2 ]]; then
    fail "prerequisites.sh: usage error — see stderr" hard-stop
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
        _log DEBUG "Prerequisites.sh: $_line"
        ;;
    esac
  done <<< "$_out"

  if [[ "$_LINT_STRUCTURAL" -gt 0 ]]; then
    fail "config lint found $_LINT_STRUCTURAL structural error(s) in $PREFLIGHT_FILE_DISPLAY — rules were not evaluated" hard-stop
  fi
  pass "config lint"
}
