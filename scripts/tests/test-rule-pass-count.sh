#!/usr/bin/env bash
# Regression test for scripts/run.sh's final summary line conflating
# prerequisite bookkeeping passes (config present, run version, config lint)
# with actual user-rule outcomes. Before the fix, a config with zero enabled
# rules still reported "3 passed" — the fixed count of unconditional
# bookkeeping passes — instead of 0. Run standalone
# (scripts/tests/test-rule-pass-count.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN="$ROOT/scripts/run.sh"
FIXTURE_DIR="$ROOT/tmp/test-rule-pass-count-fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

write_config() {
  mkdir -p "$1/.bumfuzzle"
  cat > "$1/.bumfuzzle/config.yml"
}

# -- zero enabled rules -> summary must report 0 passed, not the fixed
#    bookkeeping count (config present, run version, config lint) ----------
d="$FIXTURE_DIR/all-disabled"
mkdir -p "$d"
write_config "$d" <<'EOF'
schema_version: 1
rules:
  - group: "Sanity"
    rules:
      - type: script_clean
        name: "Never enabled"
        command: |
          true
EOF
out=$(cd "$d" && "$RUN" 2>&1) || fail "run (0 enabled rules) exited non-zero: $out"
grep -q 'Bumfuzzle run: SUCCESS - 0 passed, 0 failed, 0 warned' <<< "$out" \
  || fail "run (0 enabled rules): expected '0 passed', got: $(grep 'Bumfuzzle run:' <<< "$out")"
echo "OK run: 0 enabled rules reports 0 passed"

# -- one enabled, passing rule -> summary must report exactly 1 passed -----
d="$FIXTURE_DIR/one-enabled-pass"
mkdir -p "$d"
write_config "$d" <<'EOF'
schema_version: 1
rules:
  - group: "Sanity"
    rules:
      - type: script_clean
        name: "Always true"
        enabled: true
        command: |
          true
EOF
out=$(cd "$d" && "$RUN" 2>&1) || fail "run (1 enabled, passing rule) exited non-zero: $out"
grep -q 'Bumfuzzle run: SUCCESS - 1 passed, 0 failed, 0 warned' <<< "$out" \
  || fail "run (1 enabled, passing rule): expected '1 passed', got: $(grep 'Bumfuzzle run:' <<< "$out")"
echo "OK run: one enabled passing rule reports 1 passed"

# -- one enabled passing rule plus one enabled failing rule -> summary must
#    still count only the passing one, not fold bookkeeping passes back in --
d="$FIXTURE_DIR/mixed"
mkdir -p "$d"
write_config "$d" <<'EOF'
schema_version: 1
rules:
  - group: "Sanity"
    rules:
      - type: script_clean
        name: "Always true"
        enabled: true
        command: |
          true
      - type: script_clean
        name: "Always false"
        enabled: true
        command: |
          false
EOF
out=$(cd "$d" && "$RUN" 2>&1) && rc=0 || rc=$?
[[ "$rc" -eq 1 ]] || fail "run (mixed pass/fail) exited $rc, expected 1"
grep -q 'Bumfuzzle run: FAILURE - 1 passed, 1 failed, 0 warned' <<< "$out" \
  || fail "run (mixed pass/fail): expected '1 passed, 1 failed', got: $(grep 'Bumfuzzle run:' <<< "$out")"
echo "OK run: mixed enabled rules report exact pass/fail counts"

echo "OK $(basename "$0")"
