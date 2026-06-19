# editor — .vscode and .claude settings (setup only; no preflight check)

editor_check() {
  NOT_SUPPORTED "no preflight checks for editor settings"
}

editor_setup() {
  if step_enabled vscode_settings && scaffold_enabled "editor.vscode"; then
    if [[ -e "$PROJECT_DIR/.vscode/settings.json" ]]; then
      skip ".vscode/settings.json exists"
    else
      log "write .vscode/settings.json"
      if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$PROJECT_DIR/.vscode"
        cp "$TEMPLATES/vscode/settings.json" "$PROJECT_DIR/.vscode/settings.json"
      fi
    fi
  fi

  if step_enabled claude_settings && scaffold_enabled "editor.claude"; then
    if [[ -e "$PROJECT_DIR/.claude/settings.json" ]]; then
      skip ".claude/settings.json exists"
    else
      log "write .claude/settings.json"
      if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$PROJECT_DIR/.claude"
        cp "$TEMPLATES/claude/settings.json" "$PROJECT_DIR/.claude/settings.json"
      fi
    fi
  fi
}
