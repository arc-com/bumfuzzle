#!/usr/bin/env bash
# --dry-run makes no changes but still reports the steps it would take;
# --only forces a normally-disabled step to run; --skip suppresses a
# normally-enabled one.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# -- --dry-run: no filesystem changes at all --------------------------------
WORK1="$(mktemp -d)"
out="$(cd "$WORK1" && BUMFUZZLE_ROOT="$ROOT" "$ROOT/scripts/kickstart.sh" --dry-run 2>&1)"
remaining="$(find "$WORK1" -mindepth 1 | wc -l | tr -d ' ')"
if [[ "$remaining" -ne 0 ]]; then
  echo "FAIL: --dry-run created files on disk" >&2
  find "$WORK1" -mindepth 1 >&2
  exit 1
fi
grep -q '^\[kickstart\] write bumfuzzle.yml$' <<< "$out" || { echo "FAIL: --dry-run did not preview bumfuzzle.yml write" >&2; echo "$out" >&2; exit 1; }
grep -q '^\[dry-run\]' <<< "$out" || { echo "FAIL: --dry-run produced no [dry-run] lines" >&2; echo "$out" >&2; exit 1; }

# -- --only forces a normally-disabled step to run --------------------------
WORK2="$(mktemp -d)"
(cd "$WORK2" && BUMFUZZLE_ROOT="$ROOT" "$ROOT/scripts/kickstart.sh" --only env_files > /dev/null 2>&1)
[[ -e "$WORK2/.env.dev" && -e "$WORK2/.env.prod" ]] || { echo "FAIL: --only env_files did not create env files" >&2; exit 1; }
[[ -d "$WORK2/.git" ]] && { echo "FAIL: --only env_files also ran git_init" >&2; exit 1; }

# -- --skip suppresses a normally-enabled step ------------------------------
WORK3="$(mktemp -d)"
(cd "$WORK3" && BUMFUZZLE_ROOT="$ROOT" "$ROOT/scripts/kickstart.sh" --skip git_init,githooks > /dev/null 2>&1)
[[ ! -d "$WORK3/.git" ]] || { echo "FAIL: --skip git_init did not suppress git init" >&2; exit 1; }
[[ ! -e "$WORK3/.githooks" ]] || { echo "FAIL: --skip githooks did not suppress hook install" >&2; exit 1; }
[[ -d "$WORK3/tmp" ]] || { echo "FAIL: --skip suppressed unrelated steps too" >&2; exit 1; }

echo "OK $(basename "$0")"
