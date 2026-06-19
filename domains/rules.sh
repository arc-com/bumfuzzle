# rules — AGENTS.md and CLAUDE.md symlink installation and validation

_rules_repo_dir() {
  local _rr _base
  _base="${KICKOFF_REPO:-${PREFLIGHT_REPO:-}}"
  _rr="$(cd "$_base/.." 2>/dev/null && pwd)/rules"
  printf '%s' "$_rr"
}

rules_check() {
  # Only check rules if bumfuzzle scaffolding marker is present
  [[ ! -f "bumfuzzle.yml" ]] && return

  local _rules_any=false
  artifact_enabled "agents_md" && _rules_any=true
  artifact_enabled "claude_md" && _rules_any=true
  [[ "$_rules_any" == true ]] && section '-- Rules ----------------------------------------------------------------'

  if artifact_enabled "agents_md"; then
    if [[ -e "AGENTS.md" ]]; then
      pass "AGENTS.md is present"
    else
      CURRENT_RULE=""
      fail "AGENTS.md is missing (run kickoff to install)"
    fi
  fi

  if artifact_enabled "claude_md"; then
    if [[ -e "CLAUDE.md" ]]; then
      pass "CLAUDE.md is present"
    else
      CURRENT_RULE=""
      fail "CLAUDE.md is missing (run kickoff to install)"
    fi
  fi
}

rules_setup() {
  local rules_dir
  rules_dir="$(_rules_repo_dir)"

  if artifact_enabled "agents_md"; then
    local dest="$PROJECT_DIR/AGENTS.md"
    if [[ -e "$dest" ]]; then
      skip "AGENTS.md exists"
    elif [[ -f "$rules_dir/AGENTS.md" ]]; then
      local rel
      rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$rules_dir/AGENTS.md" "$PROJECT_DIR")"
      log "link AGENTS.md -> $rel"
      [[ "$DRY_RUN" == false ]] && ln -s "$rel" "$dest"
    else
      warn "AGENTS.md: rules repo not found at $rules_dir — skipping"
    fi
  fi

  if artifact_enabled "claude_md"; then
    local dest="$PROJECT_DIR/CLAUDE.md"
    if [[ -e "$dest" ]]; then
      skip "CLAUDE.md exists"
    elif [[ -f "$rules_dir/CLAUDE.md" ]]; then
      local rel
      rel="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$rules_dir/CLAUDE.md" "$PROJECT_DIR")"
      log "link CLAUDE.md -> $rel"
      [[ "$DRY_RUN" == false ]] && ln -s "$rel" "$dest"
    else
      warn "CLAUDE.md: rules repo not found at $rules_dir — skipping"
    fi
  fi
}
