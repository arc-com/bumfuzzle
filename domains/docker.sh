# docker — compose file checks + docker-compose scaffolding

docker_check() {
  if [[ "$(yq '.stacks.values | type' "$PREFLIGHT_FILE")" != "!!seq" ]] || \
     [[ "$(yq '.stacks.values | length' "$PREFLIGHT_FILE")" -eq 0 ]]; then
    return
  fi

  section '-- Stacks ---------------------------------------------------------------'

  if validate_values_key '.stacks.values' 'stacks'; then
    pass "stacks.values is present and non-empty"
  fi

  if [[ -n "$ONLY_STACK" ]] && ! grep -qxF "$ONLY_STACK" <<< "$(yq '.stacks.values[]' "$PREFLIGHT_FILE")"; then
    fail "unknown stack '$ONLY_STACK'"
  fi

  CURRENT_RULE="service_configs_declared"
  if rule_enabled '.validation.service_configs_declared'; then
    local desc err ok=true stack
    desc=$(rule_get '.validation.service_configs_declared.description')
    err=$(rule_get '.validation.service_configs_declared.error')
    local _exempt_stacks
    _exempt_stacks=$(yq '.docker.config_exempt_stacks // [] | .[]' "$PREFLIGHT_REPO/settings.yml" 2>/dev/null || true)
    while IFS= read -r stack; do
      is_blank "$stack" && continue
      printf '%s\n' "$_exempt_stacks" | grep -qx "$stack" && continue
      if [[ ! -f "config.${stack}.yml" ]]; then
        fail "$(interp "$err" "stack=$stack")"
        ok=false
      fi
    done < <(yq '.stacks.values[]' "$PREFLIGHT_FILE")
    [[ "$ok" == true ]] && pass "$desc"
  fi

  CURRENT_RULE="compose_config_valid"
  if rule_enabled '.validation.compose_config_valid'; then
    local desc err ok=true env env_file stack compose_file output details
    desc=$(rule_get '.validation.compose_config_valid.description')
    err=$(rule_get '.validation.compose_config_valid.error')
    while IFS= read -r env; do
      is_blank "$env" && continue
      env_file=".env.${env}"
      [[ ! -f "$env_file" ]] && continue
      while IFS= read -r stack; do
        is_blank "$stack" && continue
        compose_file="docker-compose.${stack}.yml"
        [[ ! -f "$compose_file" ]] && continue
        if ! output="$(APP_ENV="$env" docker compose --env-file "$env_file" -f "$compose_file" config --quiet 2>&1)"; then
          details="$(printf '%s' "$output" | head -n 1)"
          [[ -z "$details" ]] && details="docker compose config returned a non-zero exit code"
          fail "$(interp "$err" "env=$env" "stack=$stack" "details=$details")"
          ok=false
        fi
      done < <(selected_stacks)
    done < <(selected_envs)
    [[ "$ok" == true ]] && pass "$desc"
  fi

  CURRENT_RULE="compose_build_contexts_present"
  if rule_enabled '.validation.compose_build_contexts_present'; then
    local desc err ok=true stack compose_file service context
    desc=$(rule_get '.validation.compose_build_contexts_present.description')
    err=$(rule_get '.validation.compose_build_contexts_present.error')
    while IFS= read -r stack; do
      is_blank "$stack" && continue
      compose_file="docker-compose.${stack}.yml"
      [[ ! -f "$compose_file" ]] && continue
      while IFS=$'\t' read -r service context; do
        [[ -z "$service" || -z "$context" ]] && continue
        if [[ ! -d "$context" && ! -f "$context" ]]; then
          fail "$(interp "$err" "stack=$stack" "service=$service" "context=$context")"
          ok=false
        fi
      done < <(yq '.services | to_entries[] | select(.value.build.context) | [.key, .value.build.context] | @tsv' "$compose_file")
    done < <(selected_stacks)
    [[ "$ok" == true ]] && pass "$desc"
  fi

  CURRENT_RULE="no_external_images"
  if rule_enabled '.validation.no_external_images'; then
    local desc err ok=true stack compose_file service image allowed allowed_img
    desc=$(rule_get '.validation.no_external_images.description')
    err=$(rule_get '.validation.no_external_images.error')
    while IFS= read -r stack; do
      is_blank "$stack" && continue
      compose_file="docker-compose.${stack}.yml"
      [[ ! -f "$compose_file" ]] && continue
      while IFS=$'\t' read -r service image; do
        [[ -z "$service" || -z "$image" || "$image" == "null" ]] && continue
        allowed=false
        while IFS= read -r allowed_img; do
          is_blank "$allowed_img" && continue
          [[ "$image" == "$allowed_img" ]] && allowed=true && break
        done < <(yq '.docker.image_allowlist[]' "$PREFLIGHT_FILE" 2>/dev/null || true)
        if [[ "$allowed" == false ]]; then
          fail "$(interp "$err" "file=$compose_file" "service=$service" "image=$image")"
          ok=false
        fi
      done < <(yq '.services | to_entries[] | select(.value.image) | select(.value.build | not) | [.key, .value.image] | @tsv' "$compose_file" 2>/dev/null || true)
    done < <(selected_stacks)
    [[ "$ok" == true ]] && pass "$desc"
  fi
}

docker_setup() {
  if step_enabled docker_compose && artifact_enabled "docker_compose"; then
    if [[ "$PROJECT_TYPE" == "backend" ]]; then
      local _stack _src _dest
      while IFS= read -r _stack; do
        is_blank "$_stack" && continue
        _src="$TEMPLATES/docker/${_stack}.yml"
        _dest="$PROJECT_DIR/docker-compose.${_stack}.yml"
        [[ -f "$_src" ]] && maybe_write_subst "$_src" "$_dest"
      done < <(yq '.stacks.values[]' "$_scaffold_merged" 2>/dev/null || true)
    else
      skip "docker_compose: not applicable for type $PROJECT_TYPE"
    fi
  fi
}
