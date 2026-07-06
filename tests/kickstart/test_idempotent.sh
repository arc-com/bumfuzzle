#!/usr/bin/env bash
# kickstart never overwrites: a second run against an already-scaffolded
# project reports every step as [skip] and makes no further changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

WORK="$(mktemp -d)"
(cd "$WORK" && BUMFUZZLE_ROOT="$ROOT" "$ROOT/scripts/kickstart.sh" > /dev/null 2>&1)

before="$(cd "$WORK" && find . -not -path './.git/*' | sort)"
out="$(cd "$WORK" && BUMFUZZLE_ROOT="$ROOT" "$ROOT/scripts/kickstart.sh" 2>&1)"
after="$(cd "$WORK" && find . -not -path './.git/*' | sort)"

if grep -q '^\[kickstart\] write\|^\[kickstart\] mkdir\|^\[kickstart\] git init\|^\[kickstart\] install' <<< "$out"; then
  echo "FAIL: second kickstart run made changes instead of skipping" >&2
  echo "$out" >&2
  exit 1
fi

if [[ "$before" != "$after" ]]; then
  echo "FAIL: second kickstart run altered the file tree" >&2
  diff <(echo "$before") <(echo "$after") >&2
  exit 1
fi

echo "OK $(basename "$0")"
