# editor — .vscode and .claude settings (setup only; no preflight check)

editor_check() {
  NOT_SUPPORTED "no preflight checks for editor settings"
}

editor_setup() {
  if step_enabled vscode_settings && artifact_enabled "vscode_settings"; then
    if [[ -e "$PROJECT_DIR/.vscode/settings.json" ]]; then
      skip ".vscode/settings.json exists"
    else
      log "write .vscode/settings.json"
      if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$PROJECT_DIR/.vscode"
        printf '{\n  "editor.formatOnSave": true,\n  "editor.trimAutoWhitespace": true,\n  "files.trimTrailingWhitespace": true,\n  "files.insertFinalNewline": true\n}\n' > "$PROJECT_DIR/.vscode/settings.json"
      fi
    fi
  fi

  if step_enabled claude_settings && artifact_enabled "claude_settings"; then
    if [[ -e "$PROJECT_DIR/.claude/settings.json" ]]; then
      skip ".claude/settings.json exists"
    else
      log "write .claude/settings.json"
      if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$PROJECT_DIR/.claude"
        printf '{}\n' > "$PROJECT_DIR/.claude/settings.json"
      fi
    fi
  fi
}
