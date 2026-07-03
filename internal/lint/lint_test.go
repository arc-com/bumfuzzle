package lint

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/arc-com/bumfuzzle/internal/config"
	"github.com/arc-com/bumfuzzle/internal/report"
)

type result struct {
	out     string
	rep     *report.Reporter
	aborted bool
}

func lint(t *testing.T, yml string) result {
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
	var out bytes.Buffer
	rep := report.New(false, &out, &out)
	aborted := Run(cfg, rep)
	return result{out.String(), rep, aborted}
}

func TestCleanConfigPasses(t *testing.T) {
	r := lint(t, `
scripts:
  - id: s1
    name: "S1"
    command: "true"
    args:
      - key: A
        required: true
rules:
  - type: script_reusable
    name: "r1"
    script: s1
    args:
      A: x
`)
	if r.aborted || len(r.rep.Errors) != 0 || len(r.rep.Warnings) != 0 {
		t.Fatalf("clean config should lint clean: aborted=%v errors=%v warnings=%v\n%s",
			r.aborted, r.rep.Errors, r.rep.Warnings, r.out)
	}
}

func TestDuplicateIDs(t *testing.T) {
	r := lint(t, `
scripts:
  - id: dup
    name: "a"
    command: "true"
  - id: dup
    name: "b"
    command: "false"
`)
	found := false
	for _, e := range r.rep.Errors {
		if strings.Contains(e, "duplicate id 'dup' in scripts:") {
			found = true
		}
	}
	if !found {
		t.Fatalf("duplicate id not reported: %v", r.rep.Errors)
	}
}

func TestUnknownScriptIsStructural(t *testing.T) {
	r := lint(t, `
rules:
  - type: script_reusable
    name: "r1"
    script: ghost
`)
	if !r.aborted {
		t.Fatal("unknown script reference must abort")
	}
	if !strings.Contains(r.out, "rule references unknown script 'ghost'") {
		t.Fatalf("missing message:\n%s", r.out)
	}
	if !strings.Contains(r.out, "rules were not evaluated") {
		t.Fatalf("missing hard-stop summary:\n%s", r.out)
	}
}

func TestUnknownArgTemplateIsStructural(t *testing.T) {
	r := lint(t, `
scripts:
  - id: s1
    name: "S1"
    command: "true"
    args:
      - arg_ref: ghost
`)
	if !r.aborted || !strings.Contains(r.out, "script arg references unknown arg-template 'ghost'") {
		t.Fatalf("aborted=%v out:\n%s", r.aborted, r.out)
	}
}

func TestUnknownEnumRefIsError(t *testing.T) {
	r := lint(t, `
scripts:
  - id: s1
    name: "S1"
    command: "true"
    args:
      - key: A
        type: enum
        enum_ref: ghost
`)
	if r.aborted {
		t.Fatal("enum refs are wizard-only and must not abort")
	}
	found := false
	for _, e := range r.rep.Errors {
		if strings.Contains(e, "unknown enum_ref 'ghost'") {
			found = true
		}
	}
	if !found {
		t.Fatalf("missing enum_ref error: %v", r.rep.Errors)
	}
}

func TestUnusedArgTemplateWarns(t *testing.T) {
	r := lint(t, `
arg-templates:
  - id: lonely
    key: L
`)
	found := false
	for _, w := range r.rep.Warnings {
		if strings.Contains(w, "arg-template 'lonely' is not referenced by any script") {
			found = true
		}
	}
	if !found {
		t.Fatalf("missing unused-template warning: %v", r.rep.Warnings)
	}
}

func TestRuleFieldChecks(t *testing.T) {
	r := lint(t, `
rules:
  - description: "no group or type"
  - type: made_up
    name: "weird"
  - type: script_clean
    name: "no command"
  - type: script_reusable
    name: "no script"
  - type: script_clean
    command: "true"
`)
	if !r.aborted {
		t.Fatal("structural rule-field problems must abort")
	}
	for _, want := range []string{
		"rules entry at .rules[0] has neither 'group' nor 'type'",
		"rule weird has unknown type made_up",
		"script_clean rule no command is missing required field: command",
		"script_reusable rule no script is missing required field: script",
		"rule at .rules[4] is missing required field: name",
	} {
		if !strings.Contains(r.out, want) {
			t.Errorf("missing %q in:\n%s", want, r.out)
		}
	}
}

func TestScriptArgChecks(t *testing.T) {
	r := lint(t, `
scripts:
  - id: s1
    name: "S1"
    command: "true"
    args:
      - key: NEEDED
        required: true
rules:
  - type: script_reusable
    name: "r1"
    script: s1
    args:
      EXTRA: x
`)
	joined := strings.Join(r.rep.Errors, "\n")
	if !strings.Contains(joined, "rule 'r1' is missing required arg 'NEEDED' of script 's1'") {
		t.Errorf("missing required-arg error: %v", r.rep.Errors)
	}
	if !strings.Contains(joined, "rule 'r1' passes arg 'EXTRA' not declared by script 's1'") {
		t.Errorf("missing undeclared-arg error: %v", r.rep.Errors)
	}
}

func TestScriptCommandChecks(t *testing.T) {
	r := lint(t, `
scripts:
  - id: empty
    name: "empty"
  - id: broken
    name: "broken"
    command: "if then fi ((("
  - id: twin-a
    name: "a"
    command: "echo same"
  - id: twin-b
    name: "b"
    command: "echo same"
rules:
  - type: script_clean
    name: "broken clean"
    command: "while do ((("
`)
	if !r.aborted || !strings.Contains(r.out, "script 'empty' has no command") {
		t.Fatalf("missing no-command structural fail:\n%s", r.out)
	}
	if !strings.Contains(r.out, "script 'broken' has bash syntax errors") {
		t.Errorf("missing script syntax error:\n%s", r.out)
	}
	if !strings.Contains(r.out, "scripts 'twin-a' and 'twin-b' have identical commands") {
		t.Errorf("missing duplicate-command warning:\n%s", r.out)
	}
	if !strings.Contains(r.out, "script_clean rule 'broken clean' has bash syntax errors") {
		t.Errorf("missing script_clean syntax error:\n%s", r.out)
	}
}

func TestValueHardening(t *testing.T) {
	r := lint(t, `
scripts:
  - id: "Bad ID"
    name: "bad id"
    command: "true"
    args:
      - key: LD_PRELOAD
arg-templates:
  - id: tmpl
    key: "not an env var"
rules:
  - type: script_clean
    name: "bad values"
    command: "true"
    enabled: ture
    severity: fatal
    on_missing: explode
    args:
      "a b": x
      PATH: /evil
`)
	joined := strings.Join(r.rep.Errors, "\n")
	for _, want := range []string{
		"rule 'bad values' has invalid 'enabled' value 'ture'",
		"rule 'bad values' has unknown severity 'fatal'",
		"rule 'bad values' has unknown on_missing 'explode'",
		"rule 'bad values' arg key 'a b' is not a valid environment variable name",
		"rule 'bad values' arg key 'PATH' is reserved",
		"script id 'Bad ID' must match",
		"script 'Bad ID' declares reserved arg key 'LD_PRELOAD'",
		"arg-template 'tmpl' key 'not an env var' is not a valid environment variable name",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("missing %q in errors:\n%s", want, joined)
		}
	}
}

func TestDecodeErrIsStructural(t *testing.T) {
	r := lint(t, "rules:\n  key: value\n")
	if !r.aborted || !strings.Contains(r.out, "bumfuzzle.yml has invalid structure") {
		t.Fatalf("aborted=%v out:\n%s", r.aborted, r.out)
	}
}
