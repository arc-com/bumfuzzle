#!/usr/bin/env bash
# Regression test for bumfuzzle-template.yml's own structural cleanliness
# and for the `bumfuzzle run --plain` flag (scripts/run.sh), run standalone
# (scripts/tests/test-template-all-checks.sh).
#
# Exists because of a real incident: bumfuzzle-template.yml shipped two
# default rules with SEARCH_ROOT: "." while script_arg_types_validate.py
# rejected bare "." as a path - a structural bug in the shipped template
# that nothing caught before release. Every rule in the template ships
# disabled by default (see no-redundant-enabled-false.sh's own comment), so
# a normal `bumfuzzle run` against it never actually executes the catalog -
# only --plain, which overrides the enabled gate, does.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE="$ROOT/bumfuzzle-template.yml"
RUN="$ROOT/scripts/run.sh"
FIXTURE_DIR="$ROOT/tmp/test-template-all-checks-fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# -- the shipped template must itself pass structural/schema/arg-type checks,
#    regardless of which of its rules anyone has enabled -------------------
"$ROOT/scripts/prerequisites.sh" "$TEMPLATE" > /dev/null 2>&1 \
  || fail "bumfuzzle-template.yml failed scripts/prerequisites.sh - the shipped default config is structurally broken"
echo "OK bumfuzzle-template.yml passes prerequisites.sh on its own"

# -- --plain must run the full catalog regardless of enabled/disabled and
#    complete cleanly (no crash), even though most content checks legitimately
#    fail against a near-empty fixture project -----------------------------
d="$FIXTURE_DIR/full-sweep"
mkdir -p "$d/.bumfuzzle" "$d/.githooks"
cp "$TEMPLATE" "$d/.bumfuzzle/config.yml"
printf '#!/bin/sh\nbumfuzzle run\n' > "$d/.githooks/pre-commit"

out=$(cd "$d" && "$RUN" --plain 2>&1) && rc=0 || rc=$?
[[ "$rc" -eq 0 || "$rc" -eq 1 ]] \
  || fail "run --plain exited $rc (expected 0 or 1 - a crash, not a controlled result): $out"
head -1 <<< "$out" | grep -qE '^(Success|Failure)$' \
  || fail "run --plain's first line was not a bare Success/Failure verdict: $(head -1 <<< "$out")"
echo "OK run --plain: well-formed Success/Failure verdict"

# "Readme present" ships disabled by default in the template - it showing up
# here proves --plain overrode the enabled gate instead of skipping it
grep -q "Readme present" <<< "$out" \
  || fail "run --plain did not exercise 'Readme present', a rule disabled by default - enabled gate was not overridden"
echo "OK run --plain: runs rules that are disabled by default"

# none of the reported failures should look like the check itself crashed
# (unbound variable, command not found, bad substitution) rather than
# producing a controlled pass/fail verdict from the check's own logic
if grep -qiE 'unbound variable|command not found|bad substitution|syntax error near unexpected token' <<< "$out"; then
  fail "run --plain reported what looks like a broken check (interpreter error), not a content failure:
$(grep -iE 'unbound variable|command not found|bad substitution|syntax error near unexpected token' <<< "$out")"
fi
echo "OK run --plain: no rule crashed with an interpreter-level error"

# -- --plain --verbose must additionally include the full narration log,
#    on top of the same final verdict ---------------------------------------
out_v=$(cd "$d" && "$RUN" --plain --verbose 2>&1) || true
verbose_lines=$(wc -l <<< "$out_v")
[[ "$verbose_lines" -gt 100 ]] \
  || fail "run --plain --verbose produced only $verbose_lines lines - expected the full per-check narration log as well"
grep -qE '^(Success|Failure)$' <<< "$out_v" \
  || fail "run --plain --verbose did not include the Success/Failure verdict alongside the full log"
echo "OK run --plain --verbose: includes the full log and the verdict"

echo "OK $(basename "$0")"
