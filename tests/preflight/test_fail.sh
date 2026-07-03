#!/usr/bin/env bash
# A failing rule produces a [FAIL] line, its instruction, a summary count,
# and exit code 1; a hard-stop rule aborts the run before later rules.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$(mktemp -d)/bumfuzzle"
(cd "$ROOT" && go build -o "$BIN" ./cmd/bumfuzzle)

# -- ordinary failure: marker.txt is missing -------------------------------
WORK="$(mktemp -d)"
cp "$ROOT/tests/fixtures/pass/bumfuzzle.yml" "$WORK/"

rc=0
out="$(cd "$WORK" && "$BIN" preflight 2>&1)" || rc=$?
if [[ "$rc" -ne 1 ]]; then
  echo "FAIL: expected exit 1, got $rc" >&2; echo "$out" >&2; exit 1
fi
grep -q '^\[FAIL\] Marker file present: command exited 1$' <<< "$out"
grep -q '→ Create marker.txt' <<< "$out"
grep -q '^  1 check(s) failed:$' <<< "$out"

# -- hard-stop: aborts before later rules -----------------------------------
WORK2="$(mktemp -d)"
cp "$ROOT/tests/fixtures/hard-stop/bumfuzzle.yml" "$WORK2/"

rc=0
out="$(cd "$WORK2" && "$BIN" preflight --verbose 2>&1)" || rc=$?
if [[ "$rc" -ne 1 ]]; then
  echo "FAIL: expected exit 1 for hard-stop, got $rc" >&2; echo "$out" >&2; exit 1
fi
grep -q '^\[FAIL\] Stops everything: command exited 3$' <<< "$out"
grep -q '^\[hard-stop\] aborting preflight$' <<< "$out"
if grep -q 'Never reached' <<< "$out"; then
  echo "FAIL: rule after hard-stop was evaluated" >&2; echo "$out" >&2; exit 1
fi

echo "OK $(basename "$0")"
