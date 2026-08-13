#!/usr/bin/env bash
# run-all.sh — runs every static, local regression test under scripts/tests/,
# entirely offline. Meant as the pre-release gate (see scripts/release.sh)
# and safe to run any time standalone (scripts/tests/run-all.sh).
#
# Deliberately excludes test-release.sh, test-release-brew-shallow.sh, and
# test-release-brew-deep.sh: those verify a version already published to
# npm/PyPI/GitHub/Homebrew (see release.sh's own header comment - "run
# scripts/tests/test-release.sh afterward"), so they make real 3rd-party API
# calls and can only pass after a release, never before one.
#
# Listed explicitly, not globbed, so a new scripts/tests/*.sh file must be
# deliberately added here (or deliberately left out, like the three above)
# rather than silently picked up or silently skipped.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STATIC_TESTS=(
  test-schema.sh
  test-file-exists.sh
  test-folder-exists.sh
  test-init-run.sh
  test-template-all-checks.sh
  test-rule-pass-count.sh
)

FAILED=()

for t in "${STATIC_TESTS[@]}"; do
  printf -- '---- %s ----\n' "$t"
  if "$TESTS_DIR/$t"; then
    printf -- '---- %s: PASS ----\n\n' "$t"
  else
    printf -- '---- %s: FAIL ----\n\n' "$t"
    FAILED+=("$t")
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf 'run-all.sh: %d test(s) failed: %s\n' "${#FAILED[@]}" "${FAILED[*]}" >&2
  exit 1
fi

printf 'run-all.sh: all %d static test(s) passed\n' "${#STATIC_TESTS[@]}"
