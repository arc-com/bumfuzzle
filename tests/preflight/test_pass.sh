#!/usr/bin/env bash
# All rules in the pass fixture succeed, and the run proves rules were
# actually evaluated (regression guard for the enabled-default bug that made
# preflight report "All checks passed" after evaluating zero rules).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$(mktemp -d)/bumfuzzle"
(cd "$ROOT" && go build -o "$BIN" ./cmd/bumfuzzle)

WORK="$(mktemp -d)"
cp "$ROOT/tests/fixtures/pass/bumfuzzle.yml" "$WORK/"
touch "$WORK/marker.txt"

# OPT_ARG is declared by a script but not provided by any rule; it must not
# leak in from this shell.
out="$(cd "$WORK" && OPT_ARG=stale-from-shell "$BIN" preflight --verbose)"

grep -q '^  All checks passed$' <<< "$out"
grep -q '^\[PASS\] Marker file present$' <<< "$out"
grep -q '^\[PASS\] Working directory readable$' <<< "$out"
grep -q '^\[PASS\] Optional arg not inherited$' <<< "$out"
grep -q '^\[SKIP\] Disabled rule never runs (disabled)$' <<< "$out"
grep -q -- '-- Structure -' <<< "$out"
grep -q -- '-- Isolation -' <<< "$out"

# 5 prerequisite/lint passes + 3 rule passes
pass_count="$(grep -c '^\[PASS\] ' <<< "$out")"
if [[ "$pass_count" -ne 8 ]]; then
  echo "FAIL: expected 8 [PASS] lines, got $pass_count" >&2
  echo "$out" >&2
  exit 1
fi

echo "OK $(basename "$0")"
