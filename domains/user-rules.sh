# user-rules — process the rules: array from bumfuzzle.yml
# fail() is called with explicit $2 severity; CURRENT_RULE stays "" so FAILED_RULES is never touched.
# Inline _urule_hints() replaces the deferred hint-summary mechanism for user rules.

_URULE_VALID_TYPES="file_present file_absent content_present content_absent script_clean"

_urule_pass() {
  [[ "$VERBOSE" == true ]] && { _flush_header; printf '[PASS] %s\n' "$1"; }
}

_urule_hints() {
  local _i="$1"
  local _h_count
  _h_count=$(yq ".rules[$_i].hints | length" "$PREFLIGHT_FILE" 2>/dev/null || echo 0)
  [[ "$_h_count" -eq 0 ]] && return
  local _hi
  for _hi in $(seq 0 $((_h_count - 1))); do
    local _h
    _h=$(yq ".rules[$_i].hints[$_hi]" "$PREFLIGHT_FILE" 2>/dev/null || true)
    is_blank "$_h" && continue
    printf '    → %s\n' "$_h"
  done
}

# Print files matching target glob + scope + exclude. One path per line.
_urule_list_files() {
  local _target="$1" _scope="$2" _exclude="$3"
  local _args=()
  [[ "$_scope" == root ]] && _args+=(-maxdepth 1)
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
  find . "${_args[@]}" 2>/dev/null
}

# Return non-empty string if target path/glob matches at least one entry.
_urule_find_any() {
  local _target="$1" _scope="$2"
  if [[ "$_scope" == root ]]; then
    # Shell expands the glob in CWD; if nothing matches, the literal string is tested (-e is false)
    local _g
    for _g in $_target; do
      [[ -e "$_g" ]] && printf '%s' "$_g" && return
    done
  else
    if [[ "$_target" == */* ]]; then
      find . -path "./$_target" 2>/dev/null | head -1
    else
      find . -name "$_target" 2>/dev/null | head -1
    fi
  fi
}

user_rules_check() {
  local _count
  _count=$(yq '.rules | length' "$PREFLIGHT_FILE" 2>/dev/null || echo 0)
  [[ "$_count" -eq 0 ]] && return 0

  section '-- User Rules -----------------------------------------------------------'

  local _i
  for _i in $(seq 0 $((_count - 1))); do
    local _type _desc _target _pattern _scope _exclude _command _sev
    _type=$(yq    ".rules[$_i].type              // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
    _desc=$(yq    ".rules[$_i].description       // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
    _target=$(yq  ".rules[$_i].target            // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
    _pattern=$(yq ".rules[$_i].pattern           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
    _scope=$(yq   ".rules[$_i].scope  // \"recursive\""   "$PREFLIGHT_FILE" 2>/dev/null || echo recursive)
    _exclude=$(yq ".rules[$_i].exclude           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
    _command=$(yq ".rules[$_i].command           // \"\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
    _sev=$(yq     ".rules[$_i].severity // \"error\""     "$PREFLIGHT_FILE" 2>/dev/null || echo error)

    is_blank "$_type" && { fail "rule[$_i]: missing required field 'type'" error; continue; }

    # Validate type
    local _known=false _t
    for _t in $_URULE_VALID_TYPES; do [[ "$_t" == "$_type" ]] && _known=true && break; done
    [[ "$_known" == false ]] && {
      fail "rule[$_i]: unknown type '$_type' (valid: $_URULE_VALID_TYPES)" error
      continue
    }

    local _label="${_desc:-rule[$_i] ($_type)}"

    case "$_type" in

      file_present)
        is_blank "$_target" && { fail "$_label: 'target' is required" error; continue; }
        local _hit
        _hit=$(_urule_find_any "$_target" "$_scope")
        if [[ -n "$_hit" ]]; then
          _urule_pass "$_label"
        else
          fail "$_label: '$_target' not found (scope: $_scope)" "$_sev"
          _urule_hints "$_i"
        fi
        ;;

      file_absent)
        is_blank "$_target" && { fail "$_label: 'target' is required" error; continue; }
        local _hit
        _hit=$(_urule_find_any "$_target" "$_scope")
        if [[ -z "$_hit" ]]; then
          _urule_pass "$_label"
        else
          fail "$_label: '$_target' must not exist (found: ${_hit#./})" "$_sev"
          _urule_hints "$_i"
        fi
        ;;

      content_present|content_absent)
        is_blank "$_target"  && { fail "$_label: 'target' is required" error;  continue; }
        is_blank "$_pattern" && { fail "$_label: 'pattern' is required" error; continue; }

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
            _urule_hints "$_i"
          fi
        else
          if [[ -z "$_match_file" ]]; then
            _urule_pass "$_label"
          else
            fail "$_label: pattern '$_pattern' found in '${_match_file#./}' (must be absent)" "$_sev"
            _urule_hints "$_i"
          fi
        fi
        ;;

      script_clean)
        is_blank "$_command" && { fail "$_label: 'command' is required" error; continue; }
        local _out _ec=0
        _out=$(eval "$_command" 2>&1) || _ec=$?
        if [[ "$_ec" -eq 0 ]]; then
          _urule_pass "$_label"
        else
          fail "$_label: command exited $_ec: $_command" "$_sev"
          _urule_hints "$_i"
          if [[ "$VERBOSE" == true && -n "$_out" ]]; then
            printf '%s\n' "$_out" | sed 's/^/    /' >&2
          fi
        fi
        ;;

    esac
  done
}
