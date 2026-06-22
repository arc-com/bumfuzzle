#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFLIGHT_SH="$SCRIPT_DIR/preflight.sh"
KICKSTART_SH="$SCRIPT_DIR/kickstart.sh"
PASS=0
FAIL=0

pass_test() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail_test() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

# ── Test 1: self-validation ───────────────────────────────────────────────────
printf '\n-- Test 1: self-validation ----------------------------------------------\n'
if (cd "$SCRIPT_DIR" && ./preflight.sh > /dev/null 2>&1); then
  pass_test "preflight repo validates itself"
else
  fail_test "preflight repo self-validation failed"
fi

# ── Test 2: missing bumfuzzle.yml exits non-zero ─────────────────────────────
printf '\n-- Test 2: missing bumfuzzle.yml ----------------------------------------\n'
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/scripts"
ln -s "$PREFLIGHT_SH" "$tmpdir/scripts/preflight.sh"
if (cd "$tmpdir" && scripts/preflight.sh > /dev/null 2>&1); then
  fail_test "should exit non-zero when bumfuzzle.yml missing"
else
  pass_test "exits non-zero when bumfuzzle.yml missing"
fi

# ── Test 3: minimal config (all checks disabled) passes ──────────────────────
printf '\n-- Test 3: minimal config -----------------------------------------------\n'
tmpdir2=$(mktemp -d)
mkdir -p "$tmpdir2/scripts"
ln -s "$PREFLIGHT_SH" "$tmpdir2/scripts/preflight.sh"
cat > "$tmpdir2/bumfuzzle.yml" <<'YAML'
project:
  name: test-fixture
YAML
if (cd "$tmpdir2" && scripts/preflight.sh > /dev/null 2>&1); then
  pass_test "minimal config (all disabled) passes"
else
  fail_test "minimal config (all disabled) should pass"
fi

# ── Test 4: merge — description sourced from settings.yml ────────────────────
printf '\n-- Test 4: merge --------------------------------------------------------\n'
tmpdir3=$(mktemp -d)
mkdir -p "$tmpdir3/scripts"
ln -s "$PREFLIGHT_SH" "$tmpdir3/scripts/preflight.sh"
cat > "$tmpdir3/bumfuzzle.yml" <<'YAML'
project:
  name: merge-test
preset: bare
validation:
  required_files:
    enabled: true
    files: []
YAML
output="$(cd "$tmpdir3" && scripts/preflight.sh --verbose 2>&1)"
if printf '%s' "$output" | grep -q 'Required files are present'; then
  pass_test "merge: description sourced from settings.yml"
else
  fail_test "merge: description not found — settings.yml merge may have failed"
fi

# ── Test 5: unknown rule key exits non-zero ───────────────────────────────────
printf '\n-- Test 5: unknown rule key ---------------------------------------------\n'
tmpdir4=$(mktemp -d)
mkdir -p "$tmpdir4/scripts"
ln -s "$PREFLIGHT_SH" "$tmpdir4/scripts/preflight.sh"
cat > "$tmpdir4/bumfuzzle.yml" <<'YAML'
project:
  name: bad-rule-test
validation:
  nonexistent_rule:
    enabled: true
YAML
if (cd "$tmpdir4" && scripts/preflight.sh > /dev/null 2>&1); then
  fail_test "unknown rule key should cause non-zero exit"
else
  pass_test "unknown rule key exits non-zero"
fi

# ── Test 6: all preset files exist ────────────────────────────────────────────
printf '\n-- Test 6: preset files -------------------------------------------------\n'
for _preset in backend frontend bare workspace; do
  _preset_path="$SCRIPT_DIR/presets/purpose/${_preset}.yml"
  if [[ -f "$_preset_path" ]]; then
    pass_test "purpose preset exists: $_preset"
  else
    fail_test "purpose preset missing: $_preset"
  fi
done
for _preset in maven-gradle pnpm; do
  _preset_path="$SCRIPT_DIR/presets/manifest/${_preset}.yml"
  if [[ -f "$_preset_path" ]]; then
    pass_test "manifest preset exists: $_preset"
  else
    fail_test "manifest preset missing: $_preset"
  fi
done

# ── Test 7: project.type validation ──────────────────────────────────────────
printf '\n-- Test 7: project.type validation --------------------------------------\n'
tmpdir5=$(mktemp -d)
mkdir -p "$tmpdir5/scripts"
ln -s "$PREFLIGHT_SH" "$tmpdir5/scripts/preflight.sh"
cat > "$tmpdir5/bumfuzzle.yml" <<'YAML'
project:
  name: type-test
  type: invalid_type
YAML
if (cd "$tmpdir5" && scripts/preflight.sh > /dev/null 2>&1); then
  fail_test "invalid project.type should cause failure"
else
  pass_test "invalid project.type is caught"
fi
cat > "$tmpdir5/bumfuzzle.yml" <<'YAML'
project:
  name: type-test
  type: workspace
YAML
if (cd "$tmpdir5" && scripts/preflight.sh > /dev/null 2>&1); then
  pass_test "project.type: workspace is valid"
else
  fail_test "project.type: workspace should be valid"
fi

# ── Test 8: kickstart --dry-run produces expected output ───────────────────────
printf '\n-- Test 8: kickstart dry-run ----------------------------------------------\n'
tmpdir6=$(mktemp -d)
mkdir -p "$tmpdir6/smoke"
output="$(cd "$tmpdir6/smoke" && bash "$KICKSTART_SH" --dry-run 2>&1)"
if printf '%s' "$output" | grep -q '\[kickstart\]'; then
  pass_test "kickstart --dry-run produces output"
else
  fail_test "kickstart --dry-run produced no output"
fi
if printf '%s' "$output" | grep -q '\[dry-run\]'; then
  pass_test "kickstart --dry-run shows dry-run markers"
else
  fail_test "kickstart --dry-run missing dry-run markers"
fi

# ── Test 9: commit-msg hook rejects AI co-author ─────────────────────────────
printf '\n-- Test 9: commit-msg hook ----------------------------------------------\n'
COMMIT_MSG_HOOK="$SCRIPT_DIR/scripts/hooks/commit-msg"
tmpfile=$(mktemp)
printf 'fix: something\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n' > "$tmpfile"
if bash "$COMMIT_MSG_HOOK" "$tmpfile" > /dev/null 2>&1; then
  fail_test "commit-msg hook should reject AI co-author"
else
  pass_test "commit-msg hook rejects Co-Authored-By: Claude"
fi
printf 'fix: something\n\nCo-authored-by: Claude sonnet <x@y.z>\n' > "$tmpfile"
if bash "$COMMIT_MSG_HOOK" "$tmpfile" > /dev/null 2>&1; then
  fail_test "commit-msg hook should reject AI co-author (case-insensitive)"
else
  pass_test "commit-msg hook rejects co-authored-by: claude (case-insensitive)"
fi
printf 'fix: something clean\n' > "$tmpfile"
if bash "$COMMIT_MSG_HOOK" "$tmpfile" > /dev/null 2>&1; then
  pass_test "commit-msg hook passes clean commit message"
else
  fail_test "commit-msg hook should pass clean commit message"
fi

# ── Test 10: single_package_manager hard-stop ─────────────────────────────────
printf '\n-- Test 10: single_package_manager hard-stop ----------------------------\n'
tmpdir7=$(mktemp -d)
mkdir -p "$tmpdir7/scripts"
ln -s "$PREFLIGHT_SH" "$tmpdir7/scripts/preflight.sh"
touch "$tmpdir7/package.json" "$tmpdir7/Cargo.toml"
cat > "$tmpdir7/bumfuzzle.yml" <<'YAML'
project:
  name: multi-pm-test
validation:
  single_package_manager:
    enabled: true
YAML
output="$(cd "$tmpdir7" && scripts/preflight.sh 2>&1)" || true
if printf '%s' "$output" | grep -q 'hard-stop'; then
  pass_test "single_package_manager triggers hard-stop"
else
  fail_test "single_package_manager should trigger hard-stop"
fi

# ── Test 11: kickstart installs all hooks ───────────────────────────────────────
printf '\n-- Test 11: kickstart multi-hook install ----------------------------------\n'
tmpdir8=$(mktemp -d)
mkdir -p "$tmpdir8/hook-proj"
(cd "$tmpdir8/hook-proj" && bash "$KICKSTART_SH" > /dev/null 2>&1) || true
hook_count=$(ls "$tmpdir8/hook-proj/.githooks/" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$hook_count" -ge 2 ]]; then
  pass_test "kickstart installs multiple hooks ($hook_count found)"
else
  fail_test "kickstart should install at least 2 hooks (commit-msg + pre-commit), got $hook_count"
fi

# ── Test 12: kickstart defaults to CWD when no dir arg given ───────────────────
printf '\n-- Test 12: kickstart CWD default -----------------------------------------\n'
tmpdir9=$(mktemp -d)
output="$(cd "$tmpdir9" && bash "$KICKSTART_SH" --dry-run 2>&1)" || true
if printf '%s' "$output" | grep -q '\[kickstart\]'; then
  pass_test "kickstart runs on CWD when no dir arg given"
else
  fail_test "kickstart should run on CWD with no dir arg"
fi

# ── Test 13: single manifest → [info] log ─────────────────────────────────────
printf '\n-- Test 13: detect_manifests single hit → info --------------------------\n'
tmpdir10=$(mktemp -d)
touch "$tmpdir10/pom.xml"
output="$(cd "$tmpdir10" && bash "$KICKSTART_SH" --dry-run 2>&1)" || true
if printf '%s' "$output" | grep -q '\[info\] detected project purpose: backend'; then
  pass_test "single manifest emits [info] and sets purpose to backend"
else
  fail_test "single manifest should emit [info] detected project purpose: backend"
fi

# ── Test 14: multiple manifests → [warn] + no hard-stop ───────────────────────
printf '\n-- Test 14: detect_manifests multi-hit → warn, no abort -----------------\n'
tmpdir11=$(mktemp -d)
touch "$tmpdir11/pom.xml" "$tmpdir11/package.json"
output="$(cd "$tmpdir11" && bash "$KICKSTART_SH" --dry-run 2>&1)" || true
if printf '%s' "$output" | grep -q '\[warn\] multiple package managers'; then
  pass_test "multiple manifests emit [warn]"
else
  fail_test "multiple manifests should emit [warn]"
fi
if printf '%s' "$output" | grep -q '\[kickstart\]'; then
  pass_test "kickstart continues (no hard-stop) on multiple manifests"
else
  fail_test "kickstart should continue after multi-PM warn"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n%s\n' '-----------------------------------------------------------------------'
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
printf '%s\n' '-----------------------------------------------------------------------'
[[ $FAIL -eq 0 ]]
