# user-rules — process the rules: tree (groups + leaf rules) from bumfuzzle.yml

_URULE_VALID_TYPES="file_present file_absent content_present content_absent script_clean"

_urule_pass() {
  [[ "$VERBOSE" == true ]] && { _flush_header; printf '[PASS] %s\n' "$1"; }
}

_urule_instruction() {
  local _path="$1"
  local _instr
  _instr=$(yq "${_path}.instruction // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  is_blank "$_instr" && return
  printf '    → %s\n' "$_instr"
}

_urule_list_files() {
  local _target="$1" _scope="$2" _exclude="$3"
  local _args=() _start="."
  [[ "$_scope" != "root" && -n "$_scope" ]] && _start="./${_scope%/}"
  if [[ "$_target" == */* ]]; then
    _args+=(-path "./$_target")
  else
    _args+=(-name "$_target")
  fi
  _args+=(-type f)
  if ! is_blank "$_exclude"; then
    if [[ "$_exclude" == */* ]]; then
      _args+=(! -path "./$_exclude")
    else
      _args+=(! -name "$_exclude")
    fi
  fi
  find "$_start" "${_args[@]}" 2>/dev/null
}

_urule_find_any() {
  local _target="$1" _scope="$2"
  local _start="."
  [[ "$_scope" != "root" && -n "$_scope" ]] && _start="./${_scope%/}"
  if [[ "$_target" == */* ]]; then
    find "$_start" -path "./$_target" 2>/dev/null | head -1
  else
    find "$_start" -name "$_target" 2>/dev/null | head -1
  fi
}

_urule_process_rule() {
  local _path="$1"

  local _type _name _desc _target _pattern _scope _exclude _command _sev
  _type=$(yq    "${_path}.type              // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _name=$(yq    "${_path}.name              // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _desc=$(yq    "${_path}.description       // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _target=$(yq  "${_path}.target            // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _pattern=$(yq "${_path}.pattern           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _scope=$(yq   "${_path}.scope  // \"root\""        "$PREFLIGHT_FILE" 2>/dev/null || echo root)
  [[ "$_scope" == "recursive" ]] && _scope="root"
  _exclude=$(yq "${_path}.exclude           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _command=$(yq "${_path}.command           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
  _sev=$(yq     "${_path}.severity // \"error\""     "$PREFLIGHT_FILE" 2>/dev/null || echo error)

  is_blank "$_type" && { fail "${_path}: missing required field 'type'" error; return; }

  local _known=false _t
  for _t in $_URULE_VALID_TYPES; do [[ "$_t" == "$_type" ]] && _known=true && break; done
  [[ "$_known" == false ]] && { fail "${_path}: unknown type '$_type'" error; return; }

  local _label="${_name:-${_desc:-${_path} ($_type)}}"

  case "$_type" in
    file_present)
      is_blank "$_target" && { fail "$_label: 'target' is required" error; return; }
      local _hit
      _hit=$(_urule_find_any "$_target" "$_scope")
      if [[ -n "$_hit" ]]; then
        _urule_pass "$_label"
      else
        fail "$_label: '$_target' not found (scope: $_scope)" "$_sev"
        _urule_instruction "$_path"
      fi
      ;;

    file_absent)
      is_blank "$_target" && { fail "$_label: 'target' is required" error; return; }
      local _hit
      _hit=$(_urule_find_any "$_target" "$_scope")
      if [[ -z "$_hit" ]]; then
        _urule_pass "$_label"
      else
        fail "$_label: '$_target' must not exist (found: ${_hit#./})" "$_sev"
        _urule_instruction "$_path"
      fi
      ;;

    content_present|content_absent)
      is_blank "$_target"  && { fail "$_label: 'target' is required" error;  return; }
      is_blank "$_pattern" && { fail "$_label: 'pattern' is required" error; return; }
      local _match_file="" _f
      while IFS= read -r _f; do
        is_blank "$_f" && continue
        if grep -qE "$_pattern" "$_f" 2>/dev/null; then
          _match_file="$_f"
          break
        fi
      done < <(_urule_list_files "$_target" "$_scope" "$_exclude")

      if [[ "$_type" == content_present ]]; then
        if [[ -n "$_match_file" ]]; then
          _urule_pass "$_label"
        else
          fail "$_label: pattern '$_pattern' not found in '$_target' (scope: $_scope)" "$_sev"
          _urule_instruction "$_path"
        fi
      else
        if [[ -z "$_match_file" ]]; then
          _urule_pass "$_label"
        else
          fail "$_label: pattern '$_pattern' found in '${_match_file#./}' (must be absent)" "$_sev"
          _urule_instruction "$_path"
        fi
      fi
      ;;

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
