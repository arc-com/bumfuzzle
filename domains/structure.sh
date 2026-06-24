# structure — required files/dirs, package manager check + directories/gitignore setup

_generate_gitignore() {
  local dest="$1"
  local settings="$KICKSTART_REPO/settings.yml"

  # Collect fragment names to include
  local _frags=()

  # Common fragments
  local _f
  while IFS= read -r _f; do
    is_blank "$_f" && continue
    _frags+=("$_f")
  done < <(yq '.gitignore.defaults.common[]' "$settings" 2>/dev/null || true)

  # Apply exclude_fragments from merged config
  local _excluded=()
  local _ex
  while IFS= read -r _ex; do
    is_blank "$_ex" && continue
    _excluded+=("$_ex")
  done < <(yq '.gitignore.exclude_fragments[]' "$_scaffold_merged" 2>/dev/null || true)

  # Apply extra_fragments from merged config (opt-in to non-default fragments)
  local _xf
  while IFS= read -r _xf; do
    is_blank "$_xf" && continue
    local _already=false _ef4
    for _ef4 in "${_frags[@]:-}"; do [[ "$_ef4" == "$_xf" ]] && _already=true && break; done
    [[ "$_already" == false ]] && _frags+=("$_xf")
  done < <(yq '.gitignore.extra_fragments[]' "$_scaffold_merged" 2>/dev/null || true)

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

  # Append extra_patterns from merged config
  local _extra_count
  _extra_count=$(yq '.gitignore.extra_patterns | length' "$_scaffold_merged" 2>/dev/null || echo "0")
  if [[ "$_extra_count" -gt 0 ]]; then
    printf '# project-specific\n' >> "$dest"
    local _pat
    while IFS= read -r _pat; do
      is_blank "$_pat" && continue
      printf '%s\n' "$_pat" >> "$dest"
    done < <(yq '.gitignore.extra_patterns[]' "$_scaffold_merged" 2>/dev/null || true)
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

}

structure_setup() {
  if step_enabled directories; then
    local _dir_name _dir_path
    while IFS='|' read -r _dir_name _dir_path; do
      is_blank "$_dir_name" && continue
      artifact_enabled "$_dir_name" && maybe_mkdir "$PROJECT_DIR/$_dir_path"
    done < <(yq '.artifacts | to_entries[] | select(.value.type == "dir") | [.key, .value.path] | join("|")' "$_scaffold_merged" 2>/dev/null || true)

    # Create extra_dirs from merged config
    local _extra_dir
    while IFS= read -r _extra_dir; do
      is_blank "$_extra_dir" && continue
      maybe_mkdir "$PROJECT_DIR/$_extra_dir"
    done < <(yq '.extra_dirs[]' "$_scaffold_merged" 2>/dev/null || true)
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
    if [[ -e "$PROJECT_DIR/README.md" ]]; then
      skip "README.md exists"
    else
      log "write README.md"
      [[ "$DRY_RUN" == false ]] && printf '# %s\n' "$PROJECT_NAME" > "$PROJECT_DIR/README.md"
    fi
  fi
}
