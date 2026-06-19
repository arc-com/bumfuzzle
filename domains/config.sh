# config — service config var checks (setup not applicable)

config_check() {
  local _config_any=false
  rule_enabled '.validation.config_vars_in_template' && _config_any=true
  rule_enabled '.validation.config_extends_valid'    && _config_any=true
  [[ "$_config_any" == true ]] && section '-- Config ---------------------------------------------------------------'

  CURRENT_RULE="config_vars_in_template"
  if rule_enabled '.validation.config_vars_in_template'; then
    local desc err ok=true file var template_keys
    desc=$(rule_get '.validation.config_vars_in_template.description')
    err=$(rule_get '.validation.config_vars_in_template.error')
    if [[ -f ".env.template" ]]; then
      template_keys=$(template_vars)
      while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        while IFS= read -r var; do
          is_blank "$var" && continue
          if ! echo "$template_keys" | grep -qx "$var"; then
            fail "$(interp "$err" "file=$file" "var=$var")"
            ok=false
          fi
        done < <(config_vars "$file")
      done < <(all_config_files)
    fi
    [[ "$ok" == true ]] && pass "$desc"
  fi

  CURRENT_RULE="config_extends_valid"
  if rule_enabled '.validation.config_extends_valid'; then
    local desc err ok=true file _ext _ext_path
    desc=$(rule_get '.validation.config_extends_valid.description')
    err=$(rule_get '.validation.config_extends_valid.error')
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      _ext=$(yq '.extends // ""' "$file" 2>/dev/null || true)
      is_blank "$_ext" && continue
      _ext_path="$(dirname "$file")/$_ext"
      if [[ ! -f "$_ext_path" ]]; then
        fail "$(interp "$err" "file=$file" "extends=$_ext")"
        ok=false
      fi
    done < <(all_config_files)
    [[ "$ok" == true ]] && pass "$desc"
  fi
}

config_setup() {
  NOT_SUPPORTED "service config files are project-specific"
}
