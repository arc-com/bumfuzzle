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

  CURRENT_RULE="command_checks"
  if rule_enabled '.validation.command_checks'; then
    local _cc_count
    _cc_count=$(yq '.validation.command_checks.items | length' "$PREFLIGHT_FILE" 2>/dev/null || echo 0)
    if [[ "$_cc_count" -gt 0 ]]; then
      section '-- Checks ---------------------------------------------------------------'
      local _ci
      for _ci in $(seq 0 $((_cc_count - 1))); do
        local _cc_label _cc_command _cc_sev
        _cc_label=$(yq   ".validation.command_checks.items[${_ci}].label   // \"check[${_ci}]\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
        _cc_command=$(yq ".validation.command_checks.items[${_ci}].command // \"\""               "$PREFLIGHT_FILE" 2>/dev/null || true)
        _cc_sev=$(yq    ".validation.command_checks.items[${_ci}].severity // \"error\""          "$PREFLIGHT_FILE" 2>/dev/null || echo error)
        is_blank "$_cc_command" && { fail "$_cc_label: 'command' is required" error; continue; }
        local _cc_out _cc_ec=0
        _cc_out=$(eval "$_cc_command" 2>&1) || _cc_ec=$?
        if [[ "$_cc_ec" -eq 0 ]]; then
          pass "$_cc_label"
        else
          fail "$_cc_label" "$_cc_sev"
          local _cc_h_count _cc_hi
          _cc_h_count=$(yq ".validation.command_checks.items[${_ci}].hints | length" "$PREFLIGHT_FILE" 2>/dev/null || echo 0)
          for _cc_hi in $(seq 0 $((_cc_h_count - 1))); do
            local _cc_h
            _cc_h=$(yq ".validation.command_checks.items[${_ci}].hints[${_cc_hi}]" "$PREFLIGHT_FILE" 2>/dev/null || true)
            is_blank "$_cc_h" && continue
            printf '    → %s\n' "$_cc_h"
          done
          [[ "$VERBOSE" == true && -n "$_cc_out" ]] && printf '%s\n' "$_cc_out" | sed 's/^/    /' >&2
        fi
      done
    fi
  fi
}

dependencies_setup() {
  NOT_SUPPORTED
}
