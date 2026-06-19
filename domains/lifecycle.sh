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
  if step_enabled deploy_sh && artifact_enabled "deploy"; then
    local src="$TEMPLATES/deploy/${PROJECT_TYPE}.sh"
    local dest="$PROJECT_DIR/scripts/deploy.sh"
    if [[ -f "$src" ]]; then
      if [[ -e "$dest" ]]; then
        skip "scripts/deploy.sh exists"
      else
        log "write scripts/deploy.sh"
        if [[ "$DRY_RUN" == false ]]; then
          mkdir -p "$PROJECT_DIR/scripts"
          subst < "$src" > "$dest"
          chmod +x "$dest"
        fi
      fi
    fi
  fi

  if step_enabled start_sh && artifact_enabled "start"; then
    local src="$TEMPLATES/lifecycle/start/${PROJECT_TYPE}.sh"
    local dest="$PROJECT_DIR/scripts/start.sh"
    if [[ -f "$src" ]]; then
      if [[ -e "$dest" ]]; then
        skip "scripts/start.sh exists"
      else
        log "write scripts/start.sh"
        if [[ "$DRY_RUN" == false ]]; then
          mkdir -p "$PROJECT_DIR/scripts"
          subst < "$src" > "$dest"
          chmod +x "$dest"
        fi
      fi
    else
      skip "start_sh: no template for type $PROJECT_TYPE"
    fi
  fi

  if step_enabled stop_sh && artifact_enabled "stop"; then
    local src="$TEMPLATES/lifecycle/stop/${PROJECT_TYPE}.sh"
    local dest="$PROJECT_DIR/scripts/stop.sh"
    if [[ -f "$src" ]]; then
      if [[ -e "$dest" ]]; then
        skip "scripts/stop.sh exists"
      else
        log "write scripts/stop.sh"
        if [[ "$DRY_RUN" == false ]]; then
          mkdir -p "$PROJECT_DIR/scripts"
          subst < "$src" > "$dest"
          chmod +x "$dest"
        fi
      fi
    else
      skip "stop_sh: no template for type $PROJECT_TYPE"
    fi
  fi
}
