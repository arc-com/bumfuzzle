package config

import (
	"os"
	"path/filepath"
	"testing"
)

func load(t *testing.T, yml string) *Config {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "bumfuzzle.yml")
	if err := os.WriteFile(path, []byte(yml), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	return cfg
}

func TestLoadTypedModel(t *testing.T) {
	cfg := load(t, `
scripts:
  - group: "G"
    scripts:
      - id: s1
        name: "S1"
        command: "true"
        args:
          - key: A
            required: true
          - arg_ref: t1
arg-templates:
  - id: t1
    key: B
    required: true
rules:
  - group: "R"
    rules:
      - type: script_reusable
        name: "r1"
        script: s1
        args:
          A: "x"
          B: ["one", "two words"]
`)
	if cfg.DecodeErr != nil {
		t.Fatalf("DecodeErr: %v", cfg.DecodeErr)
	}
	s := cfg.ScriptByID()["s1"]
	if s == nil {
		t.Fatal("script s1 not found")
	}
	declared := s.DeclaredArgs(cfg.TemplateByID())
	if len(declared) != 2 || declared[0].Key != "A" || declared[1].Key != "B" {
		t.Fatalf("declared args = %+v", declared)
	}
	if !declared[0].Required || !declared[1].Required {
		t.Fatalf("required flags = %+v", declared)
	}
	rule := cfg.Rules[0].Rules[0]
	if got := rule.Args.Map["B"].EnvString(); got != "one\ntwo words" {
		t.Fatalf("list arg env = %q", got)
	}
	if got := rule.Args.Map["A"].EnvString(); got != "x" {
		t.Fatalf("scalar arg env = %q", got)
	}
}

func TestOptionalBool(t *testing.T) {
	cfg := load(t, `
rules:
  - type: script_clean
    name: "absent"
    command: "true"
  - type: script_clean
    name: "on"
    command: "true"
    enabled: true
  - type: script_clean
    name: "off"
    command: "true"
    enabled: false
  - type: script_clean
    name: "typo"
    command: "true"
    enabled: ture
`)
	if cfg.DecodeErr != nil {
		t.Fatalf("a malformed enabled: must not fail the decode: %v", cfg.DecodeErr)
	}
	r := cfg.Rules
	if r[0].Enabled.Set {
		t.Error("absent enabled should be unset")
	}
	if !r[0].Enabled.True(true) {
		t.Error("absent enabled should default true")
	}
	if !r[1].Enabled.True(false) {
		t.Error("enabled: true should be true")
	}
	if r[2].Enabled.True(true) {
		t.Error("enabled: false should be false")
	}
	if !r[3].Enabled.Set || r[3].Enabled.Valid {
		t.Errorf("enabled: ture should be set+invalid, got %+v", r[3].Enabled)
	}
	if r[3].Enabled.Raw != "ture" {
		t.Errorf("raw = %q", r[3].Enabled.Raw)
	}
}

func TestRuleArgsNonMapTolerated(t *testing.T) {
	cfg := load(t, `
rules:
  - type: script_reusable
    name: "bad args"
    script: s1
    args: "not-a-map"
`)
	if cfg.DecodeErr != nil {
		t.Fatalf("non-map args must not fail the decode: %v", cfg.DecodeErr)
	}
	a := cfg.Rules[0].Args
	if !a.Set || a.Valid {
		t.Errorf("args should be set+invalid, got %+v", a)
	}
}

func TestDecodeErrOnWrongShape(t *testing.T) {
	cfg := load(t, "rules:\n  key: value\n")
	if cfg.DecodeErr == nil {
		t.Fatal("rules as map should set DecodeErr")
	}
}

func TestKeyAndIDPatterns(t *testing.T) {
	for _, ok := range []string{"FILE_PATH", "_x", "A1"} {
		if !ArgKeyPattern.MatchString(ok) {
			t.Errorf("key %q should be valid", ok)
		}
	}
	for _, bad := range []string{"1X", "A-B", "A B", "", "A.B"} {
		if ArgKeyPattern.MatchString(bad) {
			t.Errorf("key %q should be invalid", bad)
		}
	}
	for _, k := range []string{"PATH", "IFS", "LD_PRELOAD", "DYLD_LIBRARY_PATH"} {
		if !ReservedEnvKey(k) {
			t.Errorf("%q should be reserved", k)
		}
	}
	if ReservedEnvKey("FILE_PATH") {
		t.Error("FILE_PATH should not be reserved")
	}
	for _, ok := range []string{"file-exists", "s1", "a"} {
		if !IDPattern.MatchString(ok) {
			t.Errorf("id %q should be valid", ok)
		}
	}
	for _, bad := range []string{"-x", "A", "a b", `a"b`, ""} {
		if IDPattern.MatchString(bad) {
			t.Errorf("id %q should be invalid", bad)
		}
	}
}
