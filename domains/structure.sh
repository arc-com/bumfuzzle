# structure — required files/dirs, package manager check + directories/gitignore setup

_generate_gitignore() {
  local dest="$1"
  local settings="$KICKOFF_REPO/settings.yml"

  # Collect fragment names to include
  local _frags=()

  # Common fragments
  local _f
  while IFS= read -r _f; do
    is_blank "$_f" && continue
    _frags+=("$_f")
  done < <(yq '.gitignore.defaults.common[]' "$settings" 2>/dev/null || true)

  # Purpose fragments
  while IFS= read -r _f; do
    is_blank "$_f" && continue
    local _already=false _ef
    for _ef in "${_frags[@]:-}"; do [[ "$_ef" == "$_f" ]] && _already=true && break; done
    [[ "$_already" == false ]] && _frags+=("$_f")
  done < <(yq ".gitignore.defaults.by_purpose.${PROJECT_TYPE}[]" "$settings" 2>/dev/null || true)

  # Manifest fragments
  local _pm_entry _pm_manifest _pm_frag
  while IFS= read -r _pm_entry; do
    _pm_manifest="${_pm_entry%%|*}"
    _pm_frag="${_pm_entry##*|}"
    [[ -f "$PROJECT_DIR/$_pm_manifest" ]] || continue
    local _already=false _ef2
    for _ef2 in "${_frags[@]:-}"; do [[ "$_ef2" == "$_pm_frag" ]] && _already=true && break; done
    [[ "$_already" == false ]] && _frags+=("$_pm_frag")
  done < <(yq '.gitignore.defaults.by_manifest | to_entries[] | .key + "|" + .value[]' "$settings" 2>/dev/null || true)

  # Apply exclude_fragments from client bumfuzzle.yml
  local _excluded=()
  if [[ -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
    local _ex
    while IFS= read -r _ex; do
      is_blank "$_ex" && continue
      _excluded+=("$_ex")
    done < <(yq '.gitignore.exclude_fragments[]' "$PROJECT_DIR/bumfuzzle.yml" 2>/dev/null || true)
  fi

  # Write gitignore
  local _frag
  for _frag in "${_frags[@]:-}"; do
    # Check if excluded
    local _skip_frag=false _ex3
    for _ex3 in "${_excluded[@]:-}"; do [[ "$_ex3" == "$_frag" ]] && _skip_frag=true && break; done
    [[ "$_skip_frag" == true ]] && continue

    printf '# %s\n' "$_frag" >> "$dest"
    local _pat
    while IFS= read -r _pat; do
      is_blank "$_pat" && continue
      printf '%s\n' "$_pat" >> "$dest"
    done < <(yq ".gitignore.fragments.${_frag}[]" "$settings" 2>/dev/null || true)
    printf '\n' >> "$dest"
  done

  # Append extra_patterns from client bumfuzzle.yml
  if [[ -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
    local _extra_count
    _extra_count=$(yq '.gitignore.extra_patterns | length' "$PROJECT_DIR/bumfuzzle.yml" 2>/dev/null || echo "0")
    if [[ "$_extra_count" -gt 0 ]]; then
      printf '# project-specific\n' >> "$dest"
      local _pat
      while IFS= read -r _pat; do
        is_blank "$_pat" && continue
        printf '%s\n' "$_pat" >> "$dest"
      done < <(yq '.gitignore.extra_patterns[]' "$PROJECT_DIR/bumfuzzle.yml" 2>/dev/null || true)
    fi
  fi
}

structure_check() {
  section '-- Structure ------------------------------------------------------------'

  # Artifact presence checks (file, dir, pattern)
  CURRENT_RULE=""
  local _art_ok=true _art_any=false _art_name _art_type _art_path _art_foreach
  while IFS='|' read -r _art_name _art_type _art_path _art_foreach; do
    is_blank "$_art_name" && continue
    artifact_enabled "$_art_name" || continue
    _art_any=true
    case "$_art_type" in
      file)
        if [[ ! -f "$_art_path" ]]; then
          fail "Required file missing: $_art_path"
          _art_ok=false
        fi
        ;;
      dir)
        if [[ ! -d "$_art_path" ]]; then
          fail "Required directory missing: $_art_path"
          _art_ok=false
        fi
        ;;
      pattern)
        local _pval _expanded
        while IFS= read -r _pval; do
          is_blank "$_pval" && continue
          _expanded="${_art_path//\{\{VALUE\}\}/$_pval}"
          if [[ ! -e "$_expanded" ]]; then
            fail "Required file missing: $_expanded"
            _art_ok=false
          fi
        done < <(yq ".${_art_foreach}[]" "$_merged" 2>/dev/null || true)
        ;;
    esac
  done < <(yq '.artifacts | to_entries[] | [.key, .value.type, .value.path, (.value.foreach // "")] | join("|")' "$_merged" 2>/dev/null || true)
  [[ "$_art_ok" == true && "$_art_any" == true ]] && pass "All declared artifacts present"

  # Escape hatch: explicit required_files / required_dirs lists in bumfuzzle.yml
  CURRENT_RULE="required_files"
  if rule_enabled '.validation.required_files'; then
    local _rf_ok=true _rf_file _rf_err
    _rf_err=$(rule_get '.validation.required_files.error')
    while IFS= read -r _rf_file; do
      is_blank "$_rf_file" && continue
      if [[ ! -f "$_rf_file" ]]; then
        fail "$(interp "$_rf_err" "file=$_rf_file")"
        _rf_ok=false
      fi
    done < <(rule_get '.validation.required_files.files[]' 2>/dev/null || true)
    [[ "$_rf_ok" == true ]] && pass "$(rule_get '.validation.required_files.description')"
  fi

  CURRENT_RULE="required_dirs"
  if rule_enabled '.validation.required_dirs'; then
    local _rd_ok=true _rd_dir _rd_err
    _rd_err=$(rule_get '.validation.required_dirs.error')
    while IFS= read -r _rd_dir; do
      is_blank "$_rd_dir" && continue
      if [[ ! -d "$_rd_dir" ]]; then
        fail "$(interp "$_rd_err" "dir=$_rd_dir")"
        _rd_ok=false
      fi
    done < <(rule_get '.validation.required_dirs.dirs[]' 2>/dev/null || true)
    [[ "$_rd_ok" == true ]] && pass "$(rule_get '.validation.required_dirs.description')"
  fi

  CURRENT_RULE="single_package_manager"
  if rule_enabled '.validation.single_package_manager'; then
    local desc err _pm_found=()
    desc=$(rule_get '.validation.single_package_manager.description')
    err=$(rule_get '.validation.single_package_manager.error')
    local _pm_entry _pm_manifest _pm_purpose
    while IFS= read -r _pm_entry; do
      _pm_manifest="${_pm_entry%%|*}"
      _pm_purpose="${_pm_entry##*|}"
      [[ -f "$_pm_manifest" ]] || continue
      local _seen=false _pt
      for _pt in "${_pm_found[@]:-}"; do [[ "$_pt" == "$_pm_purpose" ]] && _seen=true && break; done
      [[ "$_seen" == false ]] && _pm_found+=("$_pm_purpose")
    done < <(yq '.project.package_managers[] | .manifest + "|" + .purpose' "$PREFLIGHT_REPO/settings.yml" 2>/dev/null)
    if [[ ${#_pm_found[@]} -gt 1 ]]; then
      local _pm_list="${_pm_found[*]}"
      _pm_list="${_pm_list// /, }"
      fail "$(interp "$err" "details=$_pm_list")"
    else
      pass "$desc"
    fi
  fi
}

structure_setup() {
  if step_enabled directories; then
    local _dir_name _dir_path
    while IFS='|' read -r _dir_name _dir_path; do
      is_blank "$_dir_name" && continue
      artifact_enabled "$_dir_name" && maybe_mkdir "$PROJECT_DIR/$_dir_path"
    done < <(yq '.artifacts | to_entries[] | select(.value.type == "dir") | [.key, .value.path] | join("|")' "$_scaffold_merged" 2>/dev/null || true)
  fi

  if step_enabled gitignore && artifact_enabled "gitignore"; then
    if [[ -e "$PROJECT_DIR/.gitignore" ]]; then
      skip ".gitignore exists"
    else
      log "write .gitignore (composable fragments)"
      if [[ "$DRY_RUN" == false ]]; then
        _generate_gitignore "$PROJECT_DIR/.gitignore"
      fi
    fi
  fi

  if step_enabled readme && artifact_enabled "readme"; then
    maybe_write_subst "$TEMPLATES/readme/README.md" "$PROJECT_DIR/README.md"
  fi
}
