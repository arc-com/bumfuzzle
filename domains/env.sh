# env — .env file checks + env file scaffolding

env_check() {
  section '-- Environments ---------------------------------------------------------'

  if [[ "$(yq '.environments.values | type' "$PREFLIGHT_FILE")" == "!!seq" ]]; then

    if validate_values_key '.environments.values' 'environments'; then
      pass "environments.values is present and non-empty"
    fi

    if [[ -n "$ONLY_ENV" ]] && ! grep -qxF "$ONLY_ENV" <<< "$(yq '.environments.values[]' "$PREFLIGHT_FILE")"; then
      fail "unknown env '$ONLY_ENV'"
    fi

    CURRENT_RULE="env_no_unknown_keys"
    if rule_enabled '.validation.env_no_unknown_keys'; then
      local desc err ok=true env env_file template_keys env_keys extra
      desc=$(rule_get '.validation.env_no_unknown_keys.description')
      err=$(rule_get '.validation.env_no_unknown_keys.error')
      if [[ -f ".env.template" ]]; then
        template_keys=$(template_vars)
        while IFS= read -r env; do
          is_blank "$env" && continue
          env_file=".env.${env}"
          [[ ! -f "$env_file" ]] && continue
          env_keys=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" | cut -d= -f1 | sort -u)
          extra=$(comm -13 <(echo "$template_keys") <(echo "$env_keys") | paste -sd ',' -)
          if [[ -n "$extra" ]]; then
            fail "$(interp "$err" "file=$env_file" "details=$extra")"
            ok=false
          fi
        done < <(selected_envs)
      fi
      [[ "$ok" == true ]] && pass "$desc"
    fi

    CURRENT_RULE="env_no_missing_keys"
    if rule_enabled '.validation.env_no_missing_keys'; then
      local desc err ok=true env env_file template_keys env_keys missing
      desc=$(rule_get '.validation.env_no_missing_keys.description')
      err=$(rule_get '.validation.env_no_missing_keys.error')
      if [[ -f ".env.template" ]]; then
        template_keys=$(template_vars)
        while IFS= read -r env; do
          is_blank "$env" && continue
          env_file=".env.${env}"
          [[ ! -f "$env_file" ]] && continue
          env_keys=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" | cut -d= -f1 | sort -u)
          missing=$(comm -23 <(echo "$template_keys") <(echo "$env_keys") | paste -sd ',' -)
          if [[ -n "$missing" ]]; then
            fail "$(interp "$err" "file=$env_file" "details=$missing")"
            ok=false
          fi
        done < <(selected_envs)
      fi
      [[ "$ok" == true ]] && pass "$desc"
    fi

    CURRENT_RULE="env_accounted_for"
    if rule_enabled '.validation.env_accounted_for'; then
      local desc err ok=true
      desc=$(rule_get '.validation.env_accounted_for.description')
      err=$(rule_get '.validation.env_accounted_for.error')
      if [[ -f ".env.template" ]]; then
        if [[ "$(yq '.env.vars | type' "$PREFLIGHT_FILE")" == "!!seq" ]]; then
          local declared_vars
          declared_vars=$(yq '.env.vars[]' "$PREFLIGHT_FILE" 2>/dev/null | sort -u)
          while IFS= read -r var; do
            is_blank "$var" && continue
            if ! echo "$declared_vars" | grep -qx "$var"; then
              fail "$(interp "$err" "var=$var")"
              ok=false
            fi
          done < <(template_vars)
        else
          local accounted
          accounted="$(mktemp)"
          all_config_files | while IFS= read -r file; do
            [[ -f "$file" ]] && config_vars "$file"
          done > "$accounted"
          yq '.env.compose.vars[]' "$PREFLIGHT_FILE" >> "$accounted"
          if [[ "$(yq '.env.tools.vars | type' "$PREFLIGHT_FILE")" == "!!seq" ]]; then
            yq '.env.tools.vars[]' "$PREFLIGHT_FILE" >> "$accounted"
          fi
          sort -u -o "$accounted" "$accounted"
          while IFS= read -r var; do
            is_blank "$var" && continue
            if ! grep -qx "$var" "$accounted"; then
              fail "$(interp "$err" "var=$var")"
              ok=false
            fi
          done < <(template_vars)
        fi
      fi
      [[ "$ok" == true ]] && pass "$desc"
    fi

    CURRENT_RULE="env_required_present"
    if rule_enabled '.validation.env_required_present'; then
      local _skip
      _skip=$(yq '.validation.env_required_present.skip_without_env_flag // "false"' "$PREFLIGHT_FILE" 2>/dev/null)
      if [[ "$_skip" != "true" || -n "$ONLY_ENV" ]]; then
        local desc err ok=true env env_file var value
        desc=$(rule_get '.validation.env_required_present.description')
        err=$(rule_get '.validation.env_required_present.error')
        while IFS= read -r env; do
          is_blank "$env" && continue
          env_file=".env.${env}"
          [[ ! -f "$env_file" ]] && continue
          if [[ "$(yq ".env.required.${env} | type" "$PREFLIGHT_FILE")" != "!!seq" ]]; then
            continue
          fi
          while IFS= read -r var; do
            is_blank "$var" && continue
            value=$(grep -E "^${var}=" "$env_file" 2>/dev/null | tail -n 1 | cut -d= -f2- || true)
            if [[ -z "${value// }" ]]; then
              fail "$(interp "$err" "file=$env_file" "var=$var")"
              ok=false
            fi
          done < <(yq ".env.required.${env}[]" "$PREFLIGHT_FILE" 2>/dev/null)
        done < <(selected_envs)
        [[ "$ok" == true ]] && pass "$desc"
      fi
    fi

  fi  # end environments section

  CURRENT_RULE="env_no_blank_values"
  if rule_enabled '.validation.env_no_blank_values'; then
    local desc err ok=true env_file line key value
    desc=$(rule_get '.validation.env_no_blank_values.description')
    err=$(rule_get '.validation.env_no_blank_values.error')
    while IFS= read -r env_file; do
      while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        [[ -z "$key" ]] && continue
        if [[ -z "${value// }" ]]; then
          fail "$(interp "$err" "file=$env_file" "var=$key")"
          ok=false
        fi
      done < "$env_file"
    done < <(find . -maxdepth 1 -name '.env.*' -type f | sort)
    [[ "$ok" == true ]] && pass "$desc"
  fi
}

env_setup() {
  if step_enabled env_files; then
    local src="$TEMPLATES/env/${PROJECT_TYPE}.template"
    if [[ -f "$src" ]]; then
      artifact_enabled "env_template" && maybe_write_subst "$src" "$PROJECT_DIR/.env.template"
      if artifact_enabled "env_file"; then
        local env
        while IFS= read -r env; do
          is_blank "$env" && continue
          maybe_write_subst "$src" "$PROJECT_DIR/.env.${env}"
        done < <(cfg '.defaults.environments[]' 2>/dev/null || true)
      fi
    fi
  fi
}
