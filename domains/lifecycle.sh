# lifecycle — deploy/start/stop script presence check + scaffolding

lifecycle_check() {
  CURRENT_RULE="lifecycle_scripts_present"
  if rule_enabled '.validation.lifecycle_scripts_present'; then
    section '-- Lifecycle ------------------------------------------------------------'
    local _lifecycle_scripts
    readarray -t _lifecycle_scripts < <(yq '.lifecycle.scripts[]' "$PREFLIGHT_REPO/settings.yml" 2>/dev/null)
    local desc err ok=true _lc_script _lc_path _lc_line2
    desc=$(rule_get '.validation.lifecycle_scripts_present.description')
    err=$(rule_get '.validation.lifecycle_scripts_present.error')
    for _lc_script in "${_lifecycle_scripts[@]}"; do
      _lc_path="scripts/$_lc_script"
      if [[ ! -f "$_lc_path" ]]; then
        fail "$(interp "$err" "issue=$_lc_path is missing")"
        ok=false
        continue
      fi
      _lc_line2=$(sed -n '2p' "$_lc_path" 2>/dev/null || true)
      if [[ "$_lc_line2" != "# "* ]]; then
        fail "$(interp "$err" "issue=$_lc_path is missing a description comment on line 2 (expected: # <description>)")"
        ok=false
      fi
    done
    [[ "$ok" == true ]] && pass "$desc"
  fi
}

lifecycle_setup() {
  :
}
