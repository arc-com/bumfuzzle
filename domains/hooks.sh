# hooks — git hook installation and validation

hooks_check() {
  scaffold_enabled "git.hooks" && rule_enabled '.validation.githooks_installed' && \
    section '-- Git Hooks ------------------------------------------------------------'

  CURRENT_RULE="githooks_installed"
  if rule_enabled '.validation.githooks_installed' && scaffold_enabled "git.hooks" && [[ -d ".githooks" ]]; then
    local desc err ok=true
    desc=$(rule_get '.validation.githooks_installed.description')
    err=$(rule_get '.validation.githooks_installed.error')
    while IFS= read -r src; do
      local name installed
      name="$(basename "$src")"
      installed=".git/hooks/$name"
      if [[ ! -f "$installed" ]]; then
        fail "$(interp "$err" "hook=$name" "detail=not installed")"
        ok=false
      elif [[ "$(shasum -a 256 "$src" | cut -d' ' -f1)" != "$(shasum -a 256 "$installed" | cut -d' ' -f1)" ]]; then
        fail "$(interp "$err" "hook=$name" "detail=hash mismatch — run: scripts/hooks.sh --force")"
        ok=false
      fi
    done < <(find .githooks -maxdepth 1 -type f | sort)
    [[ "$ok" == true ]] && pass "$desc"
  fi
}

hooks_setup() {
  if step_enabled githooks && scaffold_enabled "git.hooks"; then
    local hooks_dest="$PROJECT_DIR/.githooks"
    if [[ -d "$hooks_dest" ]]; then
      skip ".githooks exists"
    else
      log "write .githooks/ hooks"
      if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$hooks_dest"
        local _hook_src
        for _hook_src in "$TEMPLATES/hooks/"*; do
          [[ -f "$_hook_src" ]] || continue
          [[ "$(basename "$_hook_src")" == "hooks.sh" ]] && continue
          cp "$_hook_src" "$hooks_dest/$(basename "$_hook_src")"
          chmod +x "$hooks_dest/$(basename "$_hook_src")"
        done
      fi
    fi
    local dest="$PROJECT_DIR/scripts/hooks.sh"
    if [[ -e "$dest" ]]; then
      skip "scripts/hooks.sh exists"
    else
      log "write scripts/hooks.sh"
      if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$PROJECT_DIR/scripts"
        cp "$TEMPLATES/hooks/hooks.sh" "$dest"
        chmod +x "$dest"
      fi
    fi
    if [[ -d "$PROJECT_DIR/.git" ]]; then
      log "install git hooks → .git/hooks/"
      [[ "$DRY_RUN" == false ]] && bash "$PROJECT_DIR/scripts/hooks.sh" --force
    fi
  fi
}
