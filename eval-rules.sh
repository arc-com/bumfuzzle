# eval-rules — walk the rules: tree from bumfuzzle.yml and run each check

_URULE_VALID_TYPES="script_clean script_reusable"

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
  if [[ "$_enabled" == "false" ]]; then return; fi
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

  case "$_type" in
    script_clean)
      is_blank "$_command" && { fail "$_label: 'command' is required" error; return; }
      local _out _ec=0
      _out=$(eval "$_command" 2>&1) || _ec=$?
      if [[ "$_ec" -eq 0 ]]; then
        _urule_pass "$_label"
      else
        fail "$_label: command exited $_ec" "$_sev"
        _urule_instruction "$_path"
        if [[ "$VERBOSE" == true && -n "$_out" ]]; then
          printf '%s\n' "$_out" | sed 's/^/    /' >&2
        fi
      fi
      ;;

    script_reusable)
      local _script_id _script_cmd
      _script_id=$(yq "${_path}.script // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
      is_blank "$_script_id" && { fail "$_label: 'script' id is required" error; return; }
      _script_cmd=$(yq ".scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \"$_script_id\") | .command // \"\"" "$PREFLIGHT_FILE" 2>/dev/null | head -1 || true)
      is_blank "$_script_cmd" && { fail "$_label: reusable script '$_script_id' not found or has no command" error; return; }

      # unset all vars declared by this script so optional args not provided by the
      # rule don't inherit stale values from a previous rule execution
      local _all_skeys _sk
      _all_skeys=$(yq ".scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \"$_script_id\") | .args[].key" "$PREFLIGHT_FILE" 2>/dev/null || true)
      while IFS= read -r _sk; do
        is_blank "$_sk" && continue
        unset "$_sk" 2>/dev/null || true
      done <<< "$_all_skeys"

      # export each arg provided by the rule as an env var; arrays are joined space-separated
      local _arg_keys _ak _av _av_type
      _arg_keys=$(yq "${_path}.args | keys | .[]" "$PREFLIGHT_FILE" 2>/dev/null || true)
      while IFS= read -r _ak; do
        is_blank "$_ak" && continue
        _av_type=$(yq "${_path}.args.${_ak} | tag" "$PREFLIGHT_FILE" 2>/dev/null || true)
        if [[ "$_av_type" == "!!seq" ]]; then
          _av=$(yq "${_path}.args.${_ak}[]" "$PREFLIGHT_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
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
        fail "$_label: command exited $_ec" "$_sev"
        _urule_instruction "$_path"
        if [[ "$VERBOSE" == true && -n "$_out" ]]; then
          printf '%s\n' "$_out" | sed 's/^/    /' >&2
        fi
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
