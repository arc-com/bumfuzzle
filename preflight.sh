#!/usr/bin/env bash
set -euo pipefail

# Resolve real script location before cd changes CWD (needed to find settings.yml and domains/)
_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_SELF="$_SCRIPT_DIR/$(basename "$0")"
while [[ -L "$_SELF" ]]; do
  _LINK="$(readlink "$_SELF")"
  if [[ "$_LINK" = /* ]]; then _SELF="$_LINK"
  else _SELF="$(cd "$(dirname "$_SELF")" && cd "$(dirname "$_LINK")" && pwd)/$(basename "$_LINK")"
  fi
done
PREFLIGHT_REPO="$(cd "$(dirname "$_SELF")" && pwd)"

# cd to the project root: one level up if called from a scripts/ dir (client project),
# or stay in place if called directly from the repo root (self-validation)
if [[ "$(basename "$_SCRIPT_DIR")" == "scripts" ]]; then
  cd "$_SCRIPT_DIR/.."
elif [[ "$_SCRIPT_DIR" == "$PREFLIGHT_REPO" ]]; then
  cd "$_SCRIPT_DIR"
fi

PREFLIGHT_VERSION="$(cat "$PREFLIGHT_REPO/VERSION" 2>/dev/null || printf 'unknown')"
PREFLIGHT_FILE="bumfuzzle.yml"
ERRORS=()
FAILED_RULES=()
WARNINGS=()
WARNED_RULES=()
CURRENT_RULE=""
ONLY_ENV=""
ONLY_STACK=""
VERBOSE=false
_PENDING_HEADER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ONLY_ENV="${2:-}"
      shift 2
      ;;
    --stack)
      ONLY_STACK="${2:-}"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Usage: ./preflight.sh [--env local|test|prod] [--stack <stack>] [--verbose|-v]"
      exit 1
      ;;
  esac
done

interp() {
  local result="$1"; shift
  while [[ $# -gt 0 ]]; do
    result="${result/\{${1%%=*}\}/${1#*=}}"
    shift
  done
  printf '%s' "$result"
}

is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }

rule_enabled() { [[ "$(yq "$1.enabled" "$PREFLIGHT_FILE")" == "true" ]]; }
rule_get()     { yq "$1" "$PREFLIGHT_FILE"; }

section() { _PENDING_HEADER="$1"; }

_flush_header() {
  if [[ -n "$_PENDING_HEADER" ]]; then
    printf '\n%s\n' "$_PENDING_HEADER"
    _PENDING_HEADER=""
  fi
}

scaffold_enabled() {
  local _val
  _val=$(yq ".scaffold.${1}" "$PREFLIGHT_FILE" 2>/dev/null || echo "null")
  [[ -z "$_val" || "$_val" == "null" ]] && return 0
  [[ "$_val" == "true" ]]
}

artifact_enabled() {
  local _val
  _val=$(yq "(.artifacts.${1}.enabled) // \"false\"" "$PREFLIGHT_FILE" 2>/dev/null || echo "false")
  [[ "$_val" == "true" ]]
}

artifact_path() {
  yq ".artifacts.${1}.path" "$_merged" 2>/dev/null
}

scaffold_dir_key() {
  echo "dirs.${1}"
}

pass() {
  if [[ "$VERBOSE" == true ]]; then
    _flush_header
    printf '[PASS] %s\n' "$1"
  fi
}

fail() {
  local _sev="error"
  if [[ -n "$CURRENT_RULE" && -f "$PREFLIGHT_FILE" ]]; then
    _sev=$(yq ".validation.${CURRENT_RULE}.severity // \"error\"" "$PREFLIGHT_FILE" 2>/dev/null || true)
    [[ -z "$_sev" || "$_sev" == "null" ]] && _sev="error"
  fi
  case "$_sev" in
    skip) return ;;
    warn)
      _flush_header
      printf '[WARN] %s\n' "$1"
      WARNINGS+=("$1")
      [[ -n "$CURRENT_RULE" ]] && WARNED_RULES+=("$CURRENT_RULE")
      ;;
    hard-stop)
      _flush_header
      printf '[FAIL] %s\n' "$1"
      printf '[hard-stop] aborting preflight\n'
      exit 1
      ;;
    *)
      _flush_header
      printf '[FAIL] %s\n' "$1"
      ERRORS+=("$1")
      [[ -n "$CURRENT_RULE" ]] && FAILED_RULES+=("$CURRENT_RULE")
      ;;
  esac
}

run_check() {
  local label="$1"; shift
  local tmpout
  tmpout=$(mktemp)
  if "$@" >"$tmpout" 2>&1; then
    pass "$label"
  else
    fail "$label"
    cat "$tmpout" >&2
  fi
}

NOT_SUPPORTED() { :; }

template_vars() {
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env.template 2>/dev/null | cut -d= -f1 | sort -u
}

config_vars() {
  local file="$1"
  local _cv_seen="${2:-}"
  grep -oE '\$\{\{[A-Za-z_][A-Za-z0-9_]*\}\}' "$file" 2>/dev/null \
    | sed 's/\${{//;s/}}//' \
    | sort -u
  local _ext
  _ext=$(yq '.extends // ""' "$file" 2>/dev/null || true)
  if [[ -n "$_ext" && "$_ext" != "null" ]]; then
    local _ext_path
    _ext_path="$(dirname "$file")/$_ext"
    if [[ -f "$_ext_path" ]] && [[ ":${_cv_seen}:" != *":${_ext_path}:"* ]]; then
      config_vars "$_ext_path" "${_cv_seen}:${_ext_path}"
    fi
  fi
}

all_config_files() {
  find . -maxdepth 1 -name 'config.*.yml' -type f | sort
}

selected_envs() {
  if [[ -n "$ONLY_ENV" ]]; then
    printf '%s\n' "$ONLY_ENV"
  else
    yq '.environments.values[]' "$PREFLIGHT_FILE"
  fi
}

selected_stacks() {
  if [[ -n "$ONLY_STACK" ]]; then
    printf '%s\n' "$ONLY_STACK"
  else
    yq '.stacks.values[]' "$PREFLIGHT_FILE"
  fi
}

validate_values_key() {
  local key="$1"
  local label="$2"
  local count
  local ok=true

  if [[ "$(yq "${key} | type" "$PREFLIGHT_FILE")" != "!!seq" ]]; then
    fail "$label must define a values array"
    return 1
  fi

  count="$(yq "${key} | length" "$PREFLIGHT_FILE")"
  if [[ "$count" -eq 0 ]]; then
    fail "$label values must not be empty"
    return 1
  fi

  local index value
  for index in $(seq 0 $((count - 1))); do
    if [[ "$(yq "${key}[${index}] | type" "$PREFLIGHT_FILE")" != "!!str" ]]; then
      fail "$label values must contain only strings"
      ok=false
      continue
    fi
    value="$(yq "${key}[${index}]" "$PREFLIGHT_FILE")"
    if [[ -z "${value// }" || "$value" == "null" ]]; then
      fail "$label values must not contain blank entries"
      ok=false
    fi
  done

  [[ "$ok" == true ]]
}

section '-- Prerequisites --------------------------------------------------------'

if ! command -v yq &>/dev/null; then
  _flush_header
  printf '[FAIL] yq is not installed - required to parse %s\n' "$PREFLIGHT_FILE"
  exit 1
fi

if [[ ! -f "$PREFLIGHT_FILE" ]]; then
  _flush_header
  printf '[FAIL] %s not found - cannot run validation\n' "$PREFLIGHT_FILE"
  exit 1
fi

pass "yq is installed"
pass "$PREFLIGHT_FILE is present"
pass "preflight v$PREFLIGHT_VERSION"

RULES_FILE="$PREFLIGHT_REPO/settings.yml"
if [[ ! -f "$RULES_FILE" ]]; then
  printf '[FAIL] settings.yml not found at %s\n' "$RULES_FILE"
  exit 1
fi
_project_preflight="$(pwd)/$PREFLIGHT_FILE"
_merged=$(mktemp)
yq eval-all '. as $item ireduce ({}; . * $item)' "$RULES_FILE" "$_project_preflight" > "$_merged"
pass "config merged"
while IFS= read -r _key; do
  [[ -z "$_key" || "$_key" == "null" ]] && continue
  if [[ "$(yq ".validation.${_key}" "$RULES_FILE")" == "null" ]]; then
    printf '[FAIL] bumfuzzle.yml: unknown rule: validation.%s\n' "$_key"
    exit 1
  fi
done < <(yq '.validation | keys | .[]' "$_project_preflight" 2>/dev/null || true)
PREFLIGHT_FILE="$_merged"

# Source all domains and run checks
. "$PREFLIGHT_REPO/domains/preflight-config.sh"
. "$PREFLIGHT_REPO/domains/structure.sh"
. "$PREFLIGHT_REPO/domains/git.sh"
. "$PREFLIGHT_REPO/domains/hooks.sh"
. "$PREFLIGHT_REPO/domains/rules.sh"
. "$PREFLIGHT_REPO/domains/env.sh"
. "$PREFLIGHT_REPO/domains/docker.sh"
. "$PREFLIGHT_REPO/domains/config.sh"
. "$PREFLIGHT_REPO/domains/dependencies.sh"
. "$PREFLIGHT_REPO/domains/lifecycle.sh"

preflight_config_check
structure_check
git_check
hooks_check
rules_check
env_check
docker_check
config_check
dependencies_check
lifecycle_check

printf '%s\n' '-----------------------------------------------------------------------'
if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
  printf '  All checks passed\n'
  printf '%s\n' '-----------------------------------------------------------------------'
  exit 0
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  printf '  %d check(s) failed:\n' "${#ERRORS[@]}"
  for e in "${ERRORS[@]}"; do
    printf '    - %s\n' "$e"
  done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  printf '  %d warning(s):\n' "${#WARNINGS[@]}"
  for w in "${WARNINGS[@]}"; do
    printf '    - %s\n' "$w"
  done
fi

_seen_rules=""
_hint_lines=()
for _rule in "${FAILED_RULES[@]:-}" "${WARNED_RULES[@]:-}"; do
  [[ "$_seen_rules" == *"|${_rule}|"* ]] && continue
  _seen_rules="${_seen_rules}|${_rule}|"
  while IFS= read -r _hint_key; do
    [[ -z "$_hint_key" || "$_hint_key" == "null" ]] && continue
    _hint_text="$(yq ".validation.${_rule}.hints.\"${_hint_key}\"" "$PREFLIGHT_FILE" 2>/dev/null)"
    if [[ -z "$_hint_text" || "$_hint_text" == "null" ]]; then
      _hint_text="$_hint_key"
    fi
    _hint_lines+=("    [${_rule}] ${_hint_text}")
  done < <(yq ".validation.${_rule}.selected_hints[]" "$PREFLIGHT_FILE" 2>/dev/null || true)
done
if [[ ${#_hint_lines[@]} -gt 0 ]]; then
  printf '\n  Hints:\n'
  for _line in "${_hint_lines[@]}"; do
    printf '%s\n' "$_line"
  done
fi

printf '%s\n' '-----------------------------------------------------------------------'
[[ ${#ERRORS[@]} -gt 0 ]] && exit 1 || exit 0
