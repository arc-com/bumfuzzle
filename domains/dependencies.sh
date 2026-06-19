# dependencies — pnpm/maven quality checks + package manager init

dependencies_check() {
  local _build_any=false
  rule_enabled '.validation.pnpm_checks'    && _build_any=true
  rule_enabled '.validation.maven_checks'   && _build_any=true
  rule_enabled '.validation.gradle_checks'  && _build_any=true
  [[ "$_build_any" == true ]] && section '-- Build ----------------------------------------------------------------'

  CURRENT_RULE="pnpm_checks"
  if rule_enabled '.validation.pnpm_checks'; then
    if command -v pnpm &>/dev/null; then
      local check
      while IFS= read -r check; do
        is_blank "$check" && continue
        run_check "$check" pnpm --silent "$check"
      done < <(rule_get '.validation.pnpm_checks.checks[]')
    else
      fail "pnpm not found"
    fi
  fi

  CURRENT_RULE="maven_checks"
  if rule_enabled '.validation.maven_checks'; then
    if [[ -f "pom.xml" ]]; then
      local desc
      desc=$(rule_get '.validation.maven_checks.description')
      if ! command -v mvn &>/dev/null; then
        fail "mvn is not installed — required for maven_checks"
      else
        run_check "$desc" mvn compile -q
      fi
    fi
  fi

  CURRENT_RULE="gradle_checks"
  if rule_enabled '.validation.gradle_checks'; then
    if [[ -f "build.gradle" || -f "build.gradle.kts" ]] && [[ -f "./gradlew" ]]; then
      local desc
      desc=$(rule_get '.validation.gradle_checks.description')
      run_check "$desc" ./gradlew test --no-daemon
    fi
  fi
}

dependencies_setup() {
  if step_enabled dependencies; then
    case "$PROJECT_TYPE" in
      frontend)
        if [[ -e "$PROJECT_DIR/package.json" ]]; then
          skip "package.json exists"
        else
          log "pnpm init"
          if [[ "$DRY_RUN" == false ]]; then
            (cd "$PROJECT_DIR" && pnpm init)
          fi
        fi
        ;;
      *)
        skip "dependencies: not applicable for type $PROJECT_TYPE"
        ;;
    esac
  fi
}
