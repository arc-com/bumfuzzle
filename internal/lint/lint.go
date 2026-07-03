// Package lint validates the structure of bumfuzzle.yml before any rule
// runs. Structural problems (broken references, malformed rules) make rule
// evaluation unreliable, so they abort preflight after all of them are
// printed; lesser problems are recorded as ordinary errors or warnings.
package lint

import (
	"fmt"
	"os/exec"
	"sort"
	"strings"

	"github.com/arc-com/bumfuzzle/internal/config"
	"github.com/arc-com/bumfuzzle/internal/report"
	"gopkg.in/yaml.v3"
)

type linter struct {
	cfg        *config.Config
	rep        *report.Reporter
	structural int
}

// Run performs all config lint checks. It returns true when a structural
// problem (or the hard-stop it triggers) means rules must not be evaluated.
func Run(cfg *config.Config, rep *report.Reporter) bool {
	l := &linter{cfg: cfg, rep: rep}

	if cfg.DecodeErr != nil {
		l.fail(fmt.Sprintf("bumfuzzle.yml has invalid structure: %v", cfg.DecodeErr))
		_ = rep.Fail(fmt.Sprintf("config lint found %d structural error(s) in bumfuzzle.yml — rules were not evaluated", l.structural), report.SevHardStop)
		return true
	}

	l.duplicateIDs()
	l.referenceIntegrity()
	l.ruleFields()
	l.scriptArgs()
	l.scriptCommands()

	if l.structural > 0 {
		_ = rep.Fail(fmt.Sprintf("config lint found %d structural error(s) in bumfuzzle.yml — rules were not evaluated", l.structural), report.SevHardStop)
		return true
	}
	rep.Pass("config lint")
	return false
}

func (l *linter) fail(msg string) {
	l.rep.StructuralFail(msg)
	l.structural++
}

// idsUnder collects every `id:` value from mapping nodes under a top-level
// key, in document order.
func (l *linter) idsUnder(top string) []string {
	var ids []string
	config.WalkMaps(l.cfg.TopKey(top), func(m *yaml.Node) {
		if v := config.MapGet(m, "id"); v != nil && v.Value != "" {
			ids = append(ids, v.Value)
		}
	})
	return ids
}

func (l *linter) duplicateIDs() {
	for _, ns := range []string{"scripts", "arg-templates", "enums"} {
		seen := map[string]int{}
		var order []string
		for _, id := range l.idsUnder(ns) {
			if seen[id] == 1 {
				order = append(order, id)
			}
			seen[id]++
		}
		sort.Strings(order)
		for _, id := range order {
			_ = l.rep.Fail(fmt.Sprintf("duplicate id '%s' in %s:", id, ns), report.SevError)
		}
	}
}

func (l *linter) referenceIntegrity() {
	scriptIDs := toSet(l.idsUnder("scripts"))
	for _, ref := range sortedUnique(l.collectRuleScriptRefs()) {
		if !scriptIDs[ref] {
			l.fail(fmt.Sprintf("rule references unknown script '%s'", ref))
		}
	}

	templateIDs := map[string]bool{}
	for _, t := range l.cfg.ArgTemplates {
		if t.ID != "" {
			templateIDs[t.ID] = true
		}
	}
	argRefs := l.collectArgRefs()
	for _, ref := range sortedUnique(argRefs) {
		if !templateIDs[ref] {
			l.fail(fmt.Sprintf("script arg references unknown arg-template '%s'", ref))
		}
	}

	// enum refs don't affect rule execution (wizard-only), so broken ones
	// are errors rather than structural aborts
	enumIDs := toSet(l.idsUnder("enums"))
	var enumRefs []string
	config.WalkMaps(l.cfg.Root, func(m *yaml.Node) {
		if v := config.MapGet(m, "enum_ref"); v != nil && v.Value != "" {
			enumRefs = append(enumRefs, v.Value)
		}
	})
	for _, ref := range sortedUnique(enumRefs) {
		if !enumIDs[ref] {
			_ = l.rep.Fail(fmt.Sprintf("unknown enum_ref '%s'", ref), report.SevError)
		}
	}

	used := toSet(argRefs)
	var unused []string
	for _, t := range l.cfg.ArgTemplates {
		if t.ID != "" && !used[t.ID] {
			unused = append(unused, t.ID)
		}
	}
	sort.Strings(unused)
	for _, id := range unused {
		_ = l.rep.Fail(fmt.Sprintf("arg-template '%s' is not referenced by any script", id), report.SevWarn)
	}
}

func (l *linter) collectRuleScriptRefs() []string {
	var refs []string
	walkRules(l.cfg.Rules, ".rules", func(r *config.Rule, path string) {
		if r.Type == config.TypeScriptReusable && r.Script != "" {
			refs = append(refs, r.Script)
		}
	})
	return refs
}

func (l *linter) collectArgRefs() []string {
	var refs []string
	config.WalkMaps(l.cfg.TopKey("scripts"), func(m *yaml.Node) {
		if v := config.MapGet(m, "arg_ref"); v != nil && v.Value != "" {
			refs = append(refs, v.Value)
		}
	})
	return refs
}

func (l *linter) ruleFields() {
	walkRules(l.cfg.Rules, ".rules", func(r *config.Rule, path string) {
		if !r.IsGroup() && r.Type == "" {
			l.fail(fmt.Sprintf("rules entry at %s has neither 'group' nor 'type'", path))
			return
		}
		if r.IsGroup() {
			return
		}
		name := r.Name
		if name == "" {
			name = "?"
		}
		known := false
		for _, t := range config.RuleTypes {
			if r.Type == t {
				known = true
			}
		}
		if !known {
			l.fail(fmt.Sprintf("rule %s has unknown type %s", name, r.Type))
			return
		}
		if r.Type == config.TypeScriptClean && r.Command == "" {
			l.fail(fmt.Sprintf("script_clean rule %s is missing required field: command", name))
		}
		if r.Type == config.TypeScriptReusable && r.Script == "" {
			l.fail(fmt.Sprintf("script_reusable rule %s is missing required field: script", name))
		}
		if r.Name == "" {
			_ = l.rep.Fail(fmt.Sprintf("rule at %s is missing required field: name", path), report.SevError)
		}
	})
}

func (l *linter) scriptArgs() {
	templates := l.cfg.TemplateByID()
	scripts := l.cfg.ScriptByID()

	walkRules(l.cfg.Rules, ".rules", func(r *config.Rule, path string) {
		if r.Type != config.TypeScriptReusable || r.Script == "" {
			return
		}
		s, ok := scripts[r.Script]
		if !ok {
			return // unknown script is reported separately
		}
		ruleName := r.Name
		if ruleName == "" {
			ruleName = "unnamed"
		}
		declared := map[string]bool{}
		var required []string
		for _, a := range s.DeclaredArgs(templates) {
			declared[a.Key] = true
			if a.Required {
				required = append(required, a.Key)
			}
		}
		for _, req := range required {
			if _, ok := r.Args.Map[req]; !ok {
				_ = l.rep.Fail(fmt.Sprintf("rule '%s' is missing required arg '%s' of script '%s'", ruleName, req, r.Script), report.SevError)
			}
		}
		var passed []string
		for k := range r.Args.Map {
			passed = append(passed, k)
		}
		sort.Strings(passed)
		for _, k := range passed {
			if !declared[k] {
				_ = l.rep.Fail(fmt.Sprintf("rule '%s' passes arg '%s' not declared by script '%s'", ruleName, k, r.Script), report.SevError)
			}
		}
	})
}

func (l *linter) scriptCommands() {
	firstByCommand := map[string]string{}
	for _, s := range l.cfg.FlatScripts() {
		if s.ID == "" {
			continue
		}
		if strings.TrimSpace(s.Command) == "" {
			l.fail(fmt.Sprintf("script '%s' has no command", s.ID))
			continue
		}
		if !bashSyntaxOK(s.Command) {
			_ = l.rep.Fail(fmt.Sprintf("script '%s' has bash syntax errors", s.ID), report.SevError)
		}
		if prev, ok := firstByCommand[s.Command]; ok {
			_ = l.rep.Fail(fmt.Sprintf("scripts '%s' and '%s' have identical commands", prev, s.ID), report.SevWarn)
		} else {
			firstByCommand[s.Command] = s.ID
		}
	}

	walkRules(l.cfg.Rules, ".rules", func(r *config.Rule, path string) {
		if r.Type != config.TypeScriptClean || r.Command == "" {
			return // missing command is reported separately
		}
		if !bashSyntaxOK(r.Command) {
			name := r.Name
			if name == "" {
				name = "?"
			}
			_ = l.rep.Fail(fmt.Sprintf("script_clean rule '%s' has bash syntax errors", name), report.SevError)
		}
	})
}

func bashSyntaxOK(command string) bool {
	cmd := exec.Command("bash", "-n")
	cmd.Stdin = strings.NewReader(command)
	return cmd.Run() == nil
}

// walkRules visits every node of the rules tree (groups and leaves) with its
// ".rules[i].rules[j]" path.
func walkRules(items []*config.Rule, base string, fn func(r *config.Rule, path string)) {
	for i, r := range items {
		path := fmt.Sprintf("%s[%d]", base, i)
		fn(r, path)
		if r.IsGroup() {
			walkRules(r.Rules, path+".rules", fn)
		}
	}
}

func toSet(items []string) map[string]bool {
	m := map[string]bool{}
	for _, s := range items {
		m[s] = true
	}
	return m
}

func sortedUnique(items []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range items {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	sort.Strings(out)
	return out
}
