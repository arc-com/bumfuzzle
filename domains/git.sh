# git — gitignore, ai coauthors check + git init setup

_gitignore_expected_patterns() {
  local _settings="$PREFLIGHT_REPO/settings.yml"
  local _purpose _f _frags=() _already _ef _pm_entry _pm_manifest _pm_frag
  local _excluded=() _ex _frag _skip_frag _ex3 _pat _extra_count

  _purpose=$(yq '.preset // ""' "$PREFLIGHT_FILE" 2>/dev/null || true)

  while IFS= read -r _f; do
    is_blank "$_f" && continue
    _frags+=("$_f")
  done < <(yq '.gitignore.defaults.common[]' "$_settings" 2>/dev/null || true)

  if ! is_blank "$_purpose"; then
    while IFS= read -r _f; do
      is_blank "$_f" && continue
      _already=false
      for _ef in "${_frags[@]:-}"; do [[ "$_ef" == "$_f" ]] && _already=true && break; done
      [[ "$_already" == false ]] && _frags+=("$_f")
    done < <(yq ".gitignore.defaults.by_purpose.${_purpose}[]" "$_settings" 2>/dev/null || true)
  fi

  while IFS= read -r _pm_entry; do
    _pm_manifest="${_pm_entry%%|*}"
    _pm_frag="${_pm_entry##*|}"
    [[ -f "$_pm_manifest" ]] || continue
    _already=false
    for _ef in "${_frags[@]:-}"; do [[ "$_ef" == "$_pm_frag" ]] && _already=true && break; done
    [[ "$_already" == false ]] && _frags+=("$_pm_frag")
  done < <(yq '.gitignore.defaults.by_manifest | to_entries[] | .key + "|" + .value[]' "$_settings" 2>/dev/null || true)

  while IFS= read -r _ex; do
    is_blank "$_ex" && continue
    _excluded+=("$_ex")
  done < <(yq '.gitignore.exclude_fragments[]' "$PREFLIGHT_FILE" 2>/dev/null || true)

  for _frag in "${_frags[@]:-}"; do
    _skip_frag=false
    for _ex3 in "${_excluded[@]:-}"; do [[ "$_ex3" == "$_frag" ]] && _skip_frag=true && break; done
    [[ "$_skip_frag" == true ]] && continue
    while IFS= read -r _pat; do
      is_blank "$_pat" && continue
      printf '%s\n' "$_pat"
    done < <(yq ".gitignore.fragments.${_frag}[]" "$_settings" 2>/dev/null || true)
  done

  _extra_count=$(yq '.gitignore.extra_patterns | length' "$PREFLIGHT_FILE" 2>/dev/null || echo "0")
  if [[ "$_extra_count" -gt 0 ]]; then
    while IFS= read -r _pat; do
      is_blank "$_pat" && continue
      printf '%s\n' "$_pat"
    done < <(yq '.gitignore.extra_patterns[]' "$PREFLIGHT_FILE" 2>/dev/null || true)
  fi
}

git_check() {
  local _git_any=false
  rule_enabled '.validation.gitignore_patterns'    && _git_any=true
  rule_enabled '.validation.git_no_ai_coauthors'  && _git_any=true
  [[ "$_git_any" == true ]] && section '-- Git ------------------------------------------------------------------'

  CURRENT_RULE="gitignore_patterns"
  if rule_enabled '.validation.gitignore_patterns'; then
    local desc err ok=true _pcount
    desc=$(rule_get '.validation.gitignore_patterns.description')
    err=$(rule_get '.validation.gitignore_patterns.error')
    _pcount=$(yq '.validation.gitignore_patterns.patterns | length' "$PREFLIGHT_FILE" 2>/dev/null || echo "0")
    if [[ "$_pcount" -gt 0 ]]; then
      while IFS= read -r pattern; do
        if ! grep -qF "$pattern" .gitignore 2>/dev/null; then
          fail "$(interp "$err" "pattern=$pattern")"
          ok=false
        fi
      done < <(rule_get '.validation.gitignore_patterns.patterns[]')
    else
      while IFS= read -r pattern; do
        if ! grep -qF "$pattern" .gitignore 2>/dev/null; then
          fail "$(interp "$err" "pattern=$pattern")"
          ok=false
        fi
      done < <(_gitignore_expected_patterns)
    fi
    [[ "$ok" == true ]] && pass "$desc"
  fi

  CURRENT_RULE="git_no_ai_coauthors"
  if rule_enabled '.validation.git_no_ai_coauthors' && [[ -d ".git" ]]; then
    local desc err _ai_count _ai_recent
    desc=$(rule_get '.validation.git_no_ai_coauthors.description')
    err=$(rule_get '.validation.git_no_ai_coauthors.error')
    _ai_count=$(git log --oneline --grep="Co-Authored-By: Claude" -i 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$_ai_count" -gt 0 ]]; then
      _ai_recent=$(git log --format="%h %s" --grep="Co-Authored-By: Claude" -i -1 2>/dev/null || true)
      fail "$(interp "$err" "count=$_ai_count" "recent=$_ai_recent")"
    else
      pass "$desc"
    fi
  fi
}

git_setup() {
  if step_enabled git_init && scaffold_enabled "git.init"; then
    if [[ -d "$PROJECT_DIR/.git" ]]; then
      skip "git already initialized"
    else
      log "git init $PROJECT_DIR"
      run git -C "$PROJECT_DIR" init
    fi
  fi
}
