package engine

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/arc-com/bumfuzzle/internal/config"
	"github.com/arc-com/bumfuzzle/internal/report"
)

type result struct {
	out, err string
	rep      *report.Reporter
	runErr   error
}

func run(t *testing.T, yml string, verbose bool) result {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "bumfuzzle.yml")
	if err := os.WriteFile(path, []byte(yml), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	var out, errBuf bytes.Buffer
	rep := report.New(verbose, &out, &errBuf)
	runErr := Run(cfg, rep, dir)
	return result{out.String(), errBuf.String(), rep, runErr}
}

func TestArgsDoNotLeakBetweenRules(t *testing.T) {
	// rule 1 provides CANARY to script set-canary; script probe does not
	// declare it, so an implementation that exports into its own process
	// would leak it into rule 2's check.
	r := run(t, `
scripts:
  - id: set-canary
    name: "set"
    command: '[ "$CANARY" = boom ]'
    args:
      - key: CANARY
  - id: probe
    name: "probe"
    command: '[ -z "${CANARY:-}" ]'
rules:
  - type: script_reusable
    name: "provides canary"
    script: set-canary
    args:
      CANARY: boom
  - type: script_reusable
    name: "must not see canary"
    script: probe
`, false)
	if len(r.rep.Errors) != 0 {
		t.Fatalf("errors: %v\noutput:\n%s", r.rep.Errors, r.out)
	}
}

func TestDeclaredArgNotInheritedFromCallerEnv(t *testing.T) {
	t.Setenv("OPT_ARG", "stale-from-shell")
	r := run(t, `
scripts:
  - id: probe
    name: "probe"
    command: '[ -z "${OPT_ARG:-}" ]'
    args:
      - key: OPT_ARG
rules:
  - type: script_reusable
    name: "declared-but-unprovided arg is unset"
    script: probe
`, false)
	if len(r.rep.Errors) != 0 {
		t.Fatalf("declared arg leaked in from caller env: %v", r.rep.Errors)
	}
}

func TestEnabledSemantics(t *testing.T) {
	r := run(t, `
rules:
  - type: script_clean
    name: "default runs"
    command: "exit 1"
  - type: script_clean
    name: "disabled skipped"
    command: "exit 1"
    enabled: false
  - type: script_clean
    name: "invalid skipped"
    command: "exit 1"
    enabled: ture
`, true)
	if len(r.rep.Errors) != 1 || !strings.Contains(r.rep.Errors[0], "default runs") {
		t.Fatalf("only the default-enabled rule should fail, got %v", r.rep.Errors)
	}
	if !strings.Contains(r.out, "[SKIP] disabled skipped (disabled)") {
		t.Errorf("missing disabled skip line:\n%s", r.out)
	}
	if !strings.Contains(r.out, "[SKIP] invalid skipped (invalid enabled value)") {
		t.Errorf("missing invalid-enabled skip line:\n%s", r.out)
	}
}

func TestSeverities(t *testing.T) {
	r := run(t, `
rules:
  - type: script_clean
    name: "warns"
    command: "exit 1"
    severity: warn
  - type: script_clean
    name: "errors"
    command: "exit 2"
`, false)
	if len(r.rep.Warnings) != 1 || len(r.rep.Errors) != 1 {
		t.Fatalf("warnings=%v errors=%v", r.rep.Warnings, r.rep.Errors)
	}
	if !strings.Contains(r.rep.Errors[0], "command exited 2") {
		t.Errorf("exit code not reported: %v", r.rep.Errors)
	}
}

func TestHardStopAbortsRun(t *testing.T) {
	r := run(t, `
rules:
  - type: script_clean
    name: "stops"
    command: "exit 3"
    severity: hard-stop
  - type: script_clean
    name: "never reached"
    command: "exit 1"
`, false)
	if !errors.Is(r.runErr, report.ErrHardStop) {
		t.Fatalf("want ErrHardStop, got %v", r.runErr)
	}
	if strings.Contains(r.out, "never reached") {
		t.Errorf("rules after hard-stop must not run:\n%s", r.out)
	}
	if !strings.Contains(r.out, "[hard-stop] aborting preflight") {
		t.Errorf("missing abort line:\n%s", r.out)
	}
}

func TestInvalidAndReservedArgKeysRejected(t *testing.T) {
	r := run(t, `
scripts:
  - id: probe
    name: "probe"
    command: "true"
    args:
      - key: PATH
      - key: OK_KEY
rules:
  - type: script_reusable
    name: "reserved key"
    script: probe
    args:
      PATH: /tmp/evil
  - type: script_reusable
    name: "bad identifier"
    script: probe
    args:
      OK_KEY: fine
      "a b": nope
`, false)
	if len(r.rep.Errors) != 2 {
		t.Fatalf("want 2 errors, got %v", r.rep.Errors)
	}
	for _, e := range r.rep.Errors {
		if !strings.Contains(e, "invalid arg key") {
			t.Errorf("unexpected error: %s", e)
		}
	}
}

func TestRequiresOnMissing(t *testing.T) {
	r := run(t, `
rules:
  - type: script_clean
    name: "skips"
    command: "true"
    requires: definitely-not-a-real-binary-bfz
    on_missing: skip
  - type: script_clean
    name: "warns by default"
    command: "true"
    requires: definitely-not-a-real-binary-bfz
  - type: script_clean
    name: "fails"
    command: "true"
    requires: definitely-not-a-real-binary-bfz
    on_missing: fail
`, true)
	if !strings.Contains(r.out, "[SKIP] skips (definitely-not-a-real-binary-bfz not installed)") {
		t.Errorf("missing skip line:\n%s", r.out)
	}
	if len(r.rep.Warnings) != 1 || !strings.Contains(r.rep.Warnings[0], "skipped — required tool") {
		t.Errorf("warnings=%v", r.rep.Warnings)
	}
	if len(r.rep.Errors) != 1 || !strings.Contains(r.rep.Errors[0], "required tool 'definitely-not-a-real-binary-bfz' is not installed") {
		t.Errorf("errors=%v", r.rep.Errors)
	}
}

func TestInstructionAndOutputOnFailure(t *testing.T) {
	r := run(t, `
rules:
  - type: script_clean
    name: "fails loudly"
    command: "echo some diagnostic; exit 1"
    instruction: "Do the thing"
`, true)
	if !strings.Contains(r.out, "    → Do the thing") {
		t.Errorf("missing instruction line:\n%s", r.out)
	}
	if !strings.Contains(r.err, "    some diagnostic") {
		t.Errorf("missing indented command output on stderr:\n%s", r.err)
	}
}

func TestGroupHeadersDeferred(t *testing.T) {
	r := run(t, `
rules:
  - group: "Silent Group"
    rules:
      - type: script_clean
        name: "quiet pass"
        command: "true"
  - group: "Loud Group"
    rules:
      - type: script_clean
        name: "fails"
        command: "exit 1"
`, false)
	if strings.Contains(r.out, "Silent Group") {
		t.Errorf("header for all-passing group should not print in non-verbose:\n%s", r.out)
	}
	if !strings.Contains(r.out, "-- Loud Group") {
		t.Errorf("header for failing group missing:\n%s", r.out)
	}
}
