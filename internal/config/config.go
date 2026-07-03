// Package config loads bumfuzzle.yml into a typed model while retaining the
// underlying yaml.Node tree. The node tree is the source of truth for writes
// (the wizard edits it in place so user comments and unknown keys survive);
// the typed model is what lint and the rule engine consume.
package config

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"
)

const (
	TypeScriptClean    = "script_clean"
	TypeScriptReusable = "script_reusable"
)

var RuleTypes = []string{TypeScriptClean, TypeScriptReusable}

// ArgKeyPattern constrains rule arg keys to valid shell identifiers so they
// can be exported into a check's environment safely.
var ArgKeyPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// IDPattern constrains script/arg-template/enum ids so they can never break
// out of contexts that quote them.
var IDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)

// reservedEnvPrefixes and reservedEnvKeys are arg keys that would change how
// the check process itself resolves binaries or loads code.
var reservedEnvKeys = map[string]bool{"PATH": true, "HOME": true, "IFS": true, "SHELL": true}
var reservedEnvPrefixes = []string{"LD_", "DYLD_"}

func ReservedEnvKey(k string) bool {
	if reservedEnvKeys[k] {
		return true
	}
	for _, p := range reservedEnvPrefixes {
		if strings.HasPrefix(k, p) {
			return true
		}
	}
	return false
}

// OptionalBool decodes a YAML value that should be a boolean without letting
// a malformed value (e.g. `enabled: ture`) abort the whole document decode.
// Lint reports invalid values; consumers decide the fallback.
type OptionalBool struct {
	Set   bool
	Valid bool
	Value bool
	Raw   string
}

func (b *OptionalBool) UnmarshalYAML(n *yaml.Node) error {
	b.Set = true
	b.Raw = n.Value
	var v bool
	if err := n.Decode(&v); err == nil {
		b.Valid = true
		b.Value = v
	}
	return nil
}

// True reports the effective value given a default for the unset case.
func (b OptionalBool) True(def bool) bool {
	if !b.Set || !b.Valid {
		return def
	}
	return b.Value
}

// ArgValue is a rule-provided argument: a scalar or a sequence of scalars.
// Sequences are newline-joined when exported (entries may contain spaces;
// scripts consume them with `while IFS= read -r`).
type ArgValue struct {
	IsList bool
	Scalar string
	List   []string
	Valid  bool
}

func (v *ArgValue) UnmarshalYAML(n *yaml.Node) error {
	switch n.Kind {
	case yaml.ScalarNode:
		v.Scalar = n.Value
		v.Valid = true
	case yaml.SequenceNode:
		v.IsList = true
		v.Valid = true
		for _, c := range n.Content {
			if c.Kind != yaml.ScalarNode {
				v.Valid = false
				return nil
			}
			v.List = append(v.List, c.Value)
		}
	}
	return nil
}

func (v ArgValue) EnvString() string {
	if v.IsList {
		return strings.Join(v.List, "\n")
	}
	return v.Scalar
}

// RuleArgs tolerates a non-map args: value instead of failing the decode;
// lint reports the shape error.
type RuleArgs struct {
	Map   map[string]ArgValue
	Valid bool
	Set   bool
}

func (a *RuleArgs) UnmarshalYAML(n *yaml.Node) error {
	a.Set = true
	if n.Kind != yaml.MappingNode {
		return nil
	}
	a.Valid = true
	return n.Decode(&a.Map)
}

// Rule is one entry of the rules: tree — either a group (Group != "") or a
// leaf check.
type Rule struct {
	Group string  `yaml:"group"`
	Rules []*Rule `yaml:"rules"`

	Type        string       `yaml:"type"`
	Name        string       `yaml:"name"`
	Description string       `yaml:"description"`
	Command     string       `yaml:"command"`
	Script      string       `yaml:"script"`
	Severity    string       `yaml:"severity"`
	Instruction string       `yaml:"instruction"`
	Requires    string       `yaml:"requires"`
	OnMissing   string       `yaml:"on_missing"`
	Enabled     OptionalBool `yaml:"enabled"`
	Args        RuleArgs     `yaml:"args"`
}

func (r *Rule) IsGroup() bool { return r.Group != "" }

// Label mirrors the bash fallback chain: name, then description, then
// "<path> (<type>)".
func (r *Rule) Label(path string) string {
	if r.Name != "" {
		return r.Name
	}
	if r.Description != "" {
		return r.Description
	}
	return fmt.Sprintf("%s (%s)", path, r.Type)
}

type ScriptArg struct {
	Key      string       `yaml:"key"`
	ArgRef   string       `yaml:"arg_ref"`
	Label    string       `yaml:"label"`
	Type     string       `yaml:"type"`
	Required OptionalBool `yaml:"required"`
	EnumRef  string       `yaml:"enum_ref"`
}

// Script is one entry of the scripts: tree — either a group or a reusable
// script definition.
type Script struct {
	Group   string    `yaml:"group"`
	Scripts []*Script `yaml:"scripts"`

	ID          string      `yaml:"id"`
	Name        string      `yaml:"name"`
	Description string      `yaml:"description"`
	Command     string      `yaml:"command"`
	Args        []ScriptArg `yaml:"args"`
}

func (s *Script) IsGroup() bool { return s.Group != "" }

type ArgTemplate struct {
	ID       string       `yaml:"id"`
	Key      string       `yaml:"key"`
	Label    string       `yaml:"label"`
	Type     string       `yaml:"type"`
	Required OptionalBool `yaml:"required"`
	EnumRef  string       `yaml:"enum_ref"`
}

type Config struct {
	Path string
	// Root is the parsed document node, retained for comment-preserving
	// round-trip writes.
	Root *yaml.Node

	Scripts      []*Script
	Rules        []*Rule
	ArgTemplates []ArgTemplate

	// DecodeErr is set when the YAML parsed but did not fit the schema
	// shapes (e.g. rules: is a map). Lint reports it as structural.
	DecodeErr error
}

type doc struct {
	Scripts      []*Script     `yaml:"scripts"`
	Rules        []*Rule       `yaml:"rules"`
	ArgTemplates []ArgTemplate `yaml:"arg-templates"`
}

// Load parses the file. A non-nil error means the YAML itself is
// unparseable; schema-shape problems land in Config.DecodeErr instead.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var root yaml.Node
	if err := yaml.Unmarshal(data, &root); err != nil {
		return nil, err
	}
	cfg := &Config{Path: path, Root: &root}
	var d doc
	if err := root.Decode(&d); err != nil {
		cfg.DecodeErr = err
		return cfg, nil
	}
	cfg.Scripts = d.Scripts
	cfg.Rules = d.Rules
	cfg.ArgTemplates = d.ArgTemplates
	return cfg, nil
}

// ScriptByID flattens the scripts tree; on duplicate ids the first
// definition wins (lint reports the duplicate).
func (c *Config) ScriptByID() map[string]*Script {
	m := map[string]*Script{}
	var walk func(items []*Script)
	walk = func(items []*Script) {
		for _, s := range items {
			if s.IsGroup() {
				walk(s.Scripts)
				continue
			}
			if s.ID != "" {
				if _, ok := m[s.ID]; !ok {
					m[s.ID] = s
				}
			}
		}
	}
	walk(c.Scripts)
	return m
}

// FlatScripts returns leaf scripts in document order.
func (c *Config) FlatScripts() []*Script {
	var out []*Script
	var walk func(items []*Script)
	walk = func(items []*Script) {
		for _, s := range items {
			if s.IsGroup() {
				walk(s.Scripts)
				continue
			}
			out = append(out, s)
		}
	}
	walk(c.Scripts)
	return out
}

// TemplateByID indexes arg-templates by id; first wins on duplicates.
func (c *Config) TemplateByID() map[string]ArgTemplate {
	m := map[string]ArgTemplate{}
	for _, t := range c.ArgTemplates {
		if t.ID != "" {
			if _, ok := m[t.ID]; !ok {
				m[t.ID] = t
			}
		}
	}
	return m
}

// DeclaredArgs resolves a script's arg list against arg-templates, returning
// (key, required) pairs. Unresolvable arg_refs are skipped here; lint
// reports them separately.
func (s *Script) DeclaredArgs(templates map[string]ArgTemplate) []struct {
	Key      string
	Required bool
} {
	var out []struct {
		Key      string
		Required bool
	}
	for _, a := range s.Args {
		key, req := a.Key, a.Required.True(false)
		if key == "" && a.ArgRef != "" {
			t, ok := templates[a.ArgRef]
			if !ok {
				continue
			}
			key, req = t.Key, t.Required.True(false)
		}
		if key == "" {
			continue
		}
		out = append(out, struct {
			Key      string
			Required bool
		}{key, req})
	}
	return out
}

// TopKey returns the value node of a top-level mapping key, or nil.
func (c *Config) TopKey(key string) *yaml.Node {
	if c.Root == nil || len(c.Root.Content) == 0 {
		return nil
	}
	m := c.Root.Content[0]
	if m.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			return m.Content[i+1]
		}
	}
	return nil
}

// WalkMaps visits every mapping node under n, depth-first.
func WalkMaps(n *yaml.Node, fn func(m *yaml.Node)) {
	if n == nil {
		return
	}
	if n.Kind == yaml.MappingNode {
		fn(n)
	}
	for _, c := range n.Content {
		WalkMaps(c, fn)
	}
}

// MapGet returns the value node for a key in a mapping node, or nil.
func MapGet(m *yaml.Node, key string) *yaml.Node {
	if m == nil || m.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			return m.Content[i+1]
		}
	}
	return nil
}
