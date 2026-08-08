#!/usr/bin/env bash
# sync-package-version.sh — writes VERSION's contents into package.json's
# version field via `npm pkg set`, skipping if it's already in sync.
# Single job: keep package.json's version aligned with VERSION, the
# project's one source of truth. Called from package.json's own "prepack"
# script and from scripts/release.sh's version-bump step, replacing what
# used to be two separate inline copies of the same `npm pkg set
# version=...` invocation.
set -euo pipefail

SCRIPT_NAME="sync-package-version.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: sync-package-version.sh [-h|--help] [-v|--verbose] [--dry-run] [--prettify]

Writes VERSION's contents into package.json's version field, skipping if
it's already in sync.

  -v, --verbose  show DEBUG-level detail on stderr
  --dry-run      print what would change, without writing
  --prettify     accepted for a CLI shape consistent with other scripts in
                 this project; has no effect here (this script never emits
                 a Banner or Section)

Exits 0 on success (including no-op), 1 on failure, 2 on a usage error.
EOF
}

VERBOSE=false
DRY_RUN=false
PRETTIFY=false
_show_help=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) _show_help=true; shift ;;
    -v|--verbose) VERBOSE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --prettify) PRETTIFY=true; shift ;;
    *)
      printf '%s: unrecognized argument: %s\n\n' "$SCRIPT_NAME" "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

_logging_flags=()
[[ "$VERBOSE" == true ]] && _logging_flags+=(--verbose)
[[ "$PRETTIFY" == true ]] && _logging_flags+=(--prettify)
source "$ROOT/scripts/logging.sh" ${_logging_flags[@]+"${_logging_flags[@]}"}

if [[ "$_show_help" == true ]]; then
  usage
  exit 0
fi

[[ -f "$ROOT/VERSION" ]] || { log_error "VERSION not found at $ROOT/VERSION"; exit 1; }
[[ -f "$ROOT/package.json" ]] || { log_error "package.json not found at $ROOT/package.json"; exit 1; }

TARGET_VERSION="$(cat "$ROOT/VERSION")"
log_debug "VERSION file: $TARGET_VERSION"

CURRENT_VERSION="$(jq -r '.version' "$ROOT/package.json")"
log_debug "Package.json version: $CURRENT_VERSION"

if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
  log_info "Already in sync - skipped"
  log_data 'package.json version already matches VERSION (%s) - skipped\n' "$TARGET_VERSION"
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  log_info "Dry run - would set version to $TARGET_VERSION"
  log_data 'Dry run, would set package.json version from %s to %s\n' "$CURRENT_VERSION" "$TARGET_VERSION"
  exit 0
fi

(cd "$ROOT" && npm pkg set version="$TARGET_VERSION" > /dev/null)
log_info "Set version to $TARGET_VERSION"
log_data 'Set package.json version from %s to %s\n' "$CURRENT_VERSION" "$TARGET_VERSION"
exit 0
