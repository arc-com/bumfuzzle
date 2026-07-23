#!/usr/bin/env bash
# sync-skill.sh — upserts skills/bumfuzzle/SKILL.md into a consumer
# project's .claude/skills/bumfuzzle/SKILL.md. Runs automatically as this
# package's npm postinstall hook; also safe to run directly or with
# --target-dir for manual use.
#
# Only ever writes under an existing .claude/ — if the target project has no
# .claude/ directory, it skips rather than creating one.
#
# EXCEPTION: this is one of three files in the repo (alongside install.sh
# and uninstall.sh) permitted to write outside $PROJECT_DIR. When invoked as
# a dependency's postinstall hook it deliberately writes into the consumer
# project that installed bumfuzzle, not into this repo.
# All other scripts must write only within the active project directory.
#
# Runs unattended as an npm lifecycle hook (no TTY, no operator to prompt),
# so unlike most mutating scripts in this repo it does not gate behind an
# interactive confirmation — install.sh/uninstall.sh set the same precedent
# for this class of write. It also reads $INIT_CWD, npm's only channel for
# telling a lifecycle script where the install happened — the one input this
# script accepts that isn't a flag, since no flag can substitute for it here.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  target="$(readlink "$SOURCE")"
  SOURCE="$(cd "$(dirname "$SOURCE")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
done
BUMFUZZLE_ROOT="$(cd "$(dirname "$SOURCE")/.." && pwd)"

SCRIPT_NAME="sync-skill.sh"
source "$BUMFUZZLE_ROOT/scripts/lib.sh"

_banner_line() { printf '%*s' 71 '' | tr ' ' '-'; }

usage() {
  printf 'Usage: sync-skill.sh [--target-dir DIR] [--dry-run] [-v|--verbose] [-h|--help]\n\n'
  printf 'Upserts skills/bumfuzzle/SKILL.md into DIR/.claude/skills/bumfuzzle/SKILL.md.\n'
  printf 'DIR defaults to $INIT_CWD (set by npm during postinstall).\n'
}

DRY_RUN=false
TARGET_PROJECT_DIR="${INIT_CWD:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir)
      [[ $# -ge 2 ]] || { _log ERROR "TAG::ARGS Missing value for --target-dir"; usage; exit 2; }
      TARGET_PROJECT_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      _log ERROR "TAG::ARGS Unrecognized argument: $1"
      usage
      exit 2
      ;;
  esac
done

_log INFO "Starting skill sync"

if [[ -z "$TARGET_PROJECT_DIR" ]]; then
  _log INFO "No target project directory resolved - skipped"
  _log DEBUG "INIT_CWD unset and --target-dir not passed"
  exit 0
fi

if [[ ! -d "$TARGET_PROJECT_DIR" ]]; then
  _log ERROR "TAG::MISSING Target project directory not found"
  _log DEBUG "Target project directory: $TARGET_PROJECT_DIR"
  exit 1
fi
_log DEBUG "Target project directory exists: $TARGET_PROJECT_DIR"
TARGET_PROJECT_DIR="$(cd "$TARGET_PROJECT_DIR" && pwd)"

if [[ "$TARGET_PROJECT_DIR" == "$BUMFUZZLE_ROOT" ]]; then
  _log INFO "Target project is this repo itself - skipped, nothing to sync into"
  exit 0
fi
_log DEBUG "Target project differs from this repo - proceeding"

_log DEBUG "Checked for .claude/ at: $TARGET_PROJECT_DIR/.claude"
if [[ ! -d "$TARGET_PROJECT_DIR/.claude" ]]; then
  _log INFO "No .claude/ directory in target project - skipped"
  exit 0
fi
_log DEBUG "Found .claude/ in target project"

SRC="$BUMFUZZLE_ROOT/skills/bumfuzzle/SKILL.md"
DEST_DIR="$TARGET_PROJECT_DIR/.claude/skills/bumfuzzle"
DEST="$DEST_DIR/SKILL.md"

if [[ ! -f "$SRC" ]]; then
  _log ERROR "TAG::MISSING Source skill file not found"
  _log DEBUG "Source skill file: $SRC"
  exit 1
fi
_log DEBUG "Source skill file: $SRC"

if [[ -f "$DEST" ]] && cmp -s "$SRC" "$DEST"; then
  _log INFO "Skill file already up to date - skipped"
  _log DEBUG "Destination: $DEST"
  printf '%s\n' "$(_banner_line)"
  printf 'bumfuzzle skill already up to date\n'
  printf '%s\n' "$(_banner_line)"
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  _log INFO "Dry run - would write skill file"
  _log DEBUG "Would write: $DEST"
  printf '%s\n' "$(_banner_line)"
  printf 'Dry run, would upsert .claude/skills/bumfuzzle/SKILL.md\n'
  printf '%s\n' "$(_banner_line)"
  exit 0
fi

mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST"
_log INFO "Wrote skill file"
_log DEBUG "Wrote: $DEST"

printf '%s\n' "$(_banner_line)"
printf 'bumfuzzle skill synced to .claude/skills/bumfuzzle/SKILL.md\n'
printf '%s\n' "$(_banner_line)"
