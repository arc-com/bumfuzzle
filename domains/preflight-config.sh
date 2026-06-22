# preflight-config — validate bumfuzzle.yml + write bumfuzzle.yml

preflight_config_check() {
  section '-- Preflight ------------------------------------------------------------'

  CURRENT_RULE="preflight_config_valid"
  if rule_enabled '.validation.preflight_config_valid'; then
    local desc err ok=true
    desc=$(rule_get '.validation.preflight_config_valid.description')
    err=$(rule_get '.validation.preflight_config_valid.error')

    local _pf_name
    _pf_name=$(yq '.project.name // ""' "$_project_preflight" 2>/dev/null)
    if is_blank "$_pf_name"; then
      fail "$(interp "$err" "issue=project.name is missing or empty in bumfuzzle.yml")"
      ok=false
    fi

    local _pf_rule
    while IFS= read -r _pf_rule; do
      is_blank "$_pf_rule" && continue

      local _pf_enabled_type
      _pf_enabled_type=$(yq ".validation.\"${_pf_rule}\".enabled | type" "$_project_preflight" 2>/dev/null)
      if [[ "$_pf_enabled_type" != "null" && "$_pf_enabled_type" != "!!null" && "$_pf_enabled_type" != "!!bool" ]]; then
        fail "$(interp "$err" "issue=validation.$_pf_rule.enabled must be a boolean, got $_pf_enabled_type")"
        ok=false
      fi

      local _pf_sev
      _pf_sev=$(yq ".validation.\"${_pf_rule}\".severity // \"\"" "$_project_preflight" 2>/dev/null || true)
      if [[ -n "$_pf_sev" && "$_pf_sev" != "null" ]]; then
        local _valid_sevs=()
        while IFS= read -r _vs_val; do _valid_sevs+=("$_vs_val"); done \
          < <(yq '.preflight.valid_severities[]' "$PREFLIGHT_REPO/settings.yml" 2>/dev/null || true)
        local _valid_sevs_str; _valid_sevs_str="${_valid_sevs[*]}"; _valid_sevs_str="${_valid_sevs_str// /, }"
        local _pf_sev_ok=false _vs
        for _vs in "${_valid_sevs[@]}"; do
          [[ "$_pf_sev" == "$_vs" ]] && _pf_sev_ok=true && break
        done
        if [[ "$_pf_sev_ok" == false ]]; then
          fail "$(interp "$err" "issue=validation.$_pf_rule.severity '$_pf_sev' is invalid (valid: $_valid_sevs_str)")"
          ok=false
        fi
      fi

      local _pf_field _pf_field_type
      for _pf_field in selected_hints files dirs patterns checks; do
        _pf_field_type=$(yq ".validation.\"${_pf_rule}\".\"${_pf_field}\" | type" "$_project_preflight" 2>/dev/null)
        if [[ "$_pf_field_type" != "null" && "$_pf_field_type" != "!!null" && "$_pf_field_type" != "!!seq" ]]; then
          fail "$(interp "$err" "issue=validation.$_pf_rule.$_pf_field must be a list, got $_pf_field_type")"
          ok=false
        fi
      done

      local _pf_hint _pf_hint_val
      while IFS= read -r _pf_hint; do
        is_blank "$_pf_hint" && continue
        _pf_hint_val=$(yq ".validation.\"${_pf_rule}\".hints.\"${_pf_hint}\"" "$RULES_FILE" 2>/dev/null)
        if is_blank "$_pf_hint_val"; then
          fail "$(interp "$err" "issue=selected_hints key '$_pf_hint' for rule '$_pf_rule' is not a valid hint")"
          ok=false
        fi
      done < <(yq ".validation.\"${_pf_rule}\".selected_hints[]" "$_project_preflight" 2>/dev/null || true)

    done < <(yq '.validation | keys | .[]' "$_project_preflight" 2>/dev/null || true)

    local _pf_env_type
    _pf_env_type=$(yq '.environments.values | type' "$_project_preflight" 2>/dev/null)
    if [[ "$_pf_env_type" != "null" && "$_pf_env_type" != "!!null" && "$_pf_env_type" != "!!seq" ]]; then
      fail "$(interp "$err" "issue=environments.values must be a list, got $_pf_env_type")"
      ok=false
    fi

    local _pf_evars_type
    _pf_evars_type=$(yq '.env.vars | type' "$_project_preflight" 2>/dev/null)
    if [[ "$_pf_evars_type" != "null" && "$_pf_evars_type" != "!!null" && "$_pf_evars_type" != "!!seq" ]]; then
      fail "$(interp "$err" "issue=env.vars must be a list, got $_pf_evars_type")"
      ok=false
    fi

    [[ "$ok" == true ]] && pass "$desc"
  fi
}

preflight_config_setup() {
  if step_enabled bumfuzzle_yml; then
    local dest="$PROJECT_DIR/bumfuzzle.yml"
    if [[ -e "$dest" ]]; then
      skip "bumfuzzle.yml exists"
      return
    fi
    log "write bumfuzzle.yml (from settings defaults)"
    if [[ "$DRY_RUN" == false ]]; then
      printf 'project:\n  name: %s\n\nartifacts:\n' "$PROJECT_NAME" > "$dest"
      local _kind _key _default
      while IFS='|' read -r _kind _key _default; do
        [[ "$_kind" != "artifact" || "$_default" != "true" ]] && continue
        printf '  %s: { enabled: true }\n' "$_key" >> "$dest"
      done < <({
        yq '.bumfuzzle.directories[] | .kind + "|" + .key + "|" + (.bumfuzzle_default | tostring)' "$KICKSTART_REPO/settings.yml" 2>/dev/null
        yq '.bumfuzzle.files[] | .kind + "|" + .key + "|" + (.bumfuzzle_default | tostring)' "$KICKSTART_REPO/settings.yml" 2>/dev/null
      })
      _build_scaffold_merged
    fi
  fi
}
