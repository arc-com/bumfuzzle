// Package engine walks the rules: tree and executes each enabled check.
// Every command runs in its own `bash -c` process with an explicitly
// constructed environment: a script's declared arg keys are removed from the
// inherited environment and only the invoking rule's args are added, so
// values can never leak between rules or in from the caller's shell.
package engine

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/arc-com/bumfuzzle/internal/config"
	"github.com/arc-com/bumfuzzle/internal/report"
)

type runner struct {
	cfg     *config.Config
	rep     *report.Reporter
	dir     string
	scripts map[string]*config.Script
	tmpl    map[string]config.ArgTemplate
}

// Run evaluates all rules. The returned error is report.ErrHardStop when a
// hard-stop severity check failed.
func Run(cfg *config.Config, rep *report.Reporter, dir string) error {
	if len(cfg.Rules) == 0 {
		return nil
	}
	rep.Section("-- Rules ----------------------------------------------------------------")
	r := &runner{
		cfg:     cfg,
		rep:     rep,
		dir:     dir,
		scripts: cfg.ScriptByID(),
		tmpl:    cfg.TemplateByID(),
	}
	return r.walk(cfg.Rules, ".rules")
}

func (r *runner) walk(items []*config.Rule, base string) error {
	for i, rule := range items {
		path := fmt.Sprintf("%s[%d]", base, i)
		if rule.IsGroup() {
			r.rep.Section(fmt.Sprintf("-- %s %s", rule.Group, strings.Repeat("-", 40)))
			if err := r.walk(rule.Rules, path+".rules"); err != nil {
				return err
			}
			continue
		}
		if err := r.process(rule, path); err != nil {
			return err
		}
	}
	return nil
}

func (r *runner) process(rule *config.Rule, path string) error {
	label := rule.Label(path)

	// Rules are enabled unless explicitly disabled; an invalid enabled:
	// value also disables (lint reports it as an error).
	if rule.Enabled.Set && !rule.Enabled.True(true) {
		r.rep.Skip(fmt.Sprintf("%s (disabled)", label))
		return nil
	}
	if rule.Enabled.Set && !rule.Enabled.Valid {
		r.rep.Skip(fmt.Sprintf("%s (invalid enabled value)", label))
		return nil
	}

	if rule.Type == "" {
		return r.rep.Fail(fmt.Sprintf("%s: missing required field 'type'", path), report.SevError)
	}
	known := false
	for _, t := range config.RuleTypes {
		if rule.Type == t {
			known = true
		}
	}
	if !known {
		return r.rep.Fail(fmt.Sprintf("%s: unknown type '%s'", path, rule.Type), report.SevError)
	}

	sev := report.SeverityOf(rule.Severity)

	// requires: gates the rule on an external tool being installed;
	// on_missing decides what happens when it is not: skip | warn (default) | fail
	if rule.Requires != "" {
		if _, err := exec.LookPath(rule.Requires); err != nil {
			switch rule.OnMissing {
			case "skip":
				r.rep.Skip(fmt.Sprintf("%s (%s not installed)", label, rule.Requires))
				return nil
			case "fail":
				r.instruction(rule)
				return r.rep.Fail(fmt.Sprintf("%s: required tool '%s' is not installed", label, rule.Requires), sev)
			default:
				return r.rep.Fail(fmt.Sprintf("%s: skipped — required tool '%s' is not installed", label, rule.Requires), report.SevWarn)
			}
		}
	}

	switch rule.Type {
	case config.TypeScriptClean:
		if strings.TrimSpace(rule.Command) == "" {
			return r.rep.Fail(fmt.Sprintf("%s: 'command' is required", label), report.SevError)
		}
		return r.execute(rule, label, rule.Command, nil, nil)

	case config.TypeScriptReusable:
		if rule.Script == "" {
			return r.rep.Fail(fmt.Sprintf("%s: 'script' id is required", label), report.SevError)
		}
		script, ok := r.scripts[rule.Script]
		if !ok || strings.TrimSpace(script.Command) == "" {
			return r.rep.Fail(fmt.Sprintf("%s: reusable script '%s' not found or has no command", label, rule.Script), report.SevError)
		}

		var declared []string
		for _, a := range script.DeclaredArgs(r.tmpl) {
			declared = append(declared, a.Key)
		}
		env := map[string]string{}
		for k, v := range rule.Args.Map {
			if !config.ArgKeyPattern.MatchString(k) || config.ReservedEnvKey(k) {
				return r.rep.Fail(fmt.Sprintf("%s: invalid arg key '%s'", label, k), report.SevError)
			}
			env[k] = v.EnvString()
		}
		return r.execute(rule, label, script.Command, declared, env)
	}
	return nil
}

func (r *runner) execute(rule *config.Rule, label, command string, unsetKeys []string, env map[string]string) error {
	out, code := r.runBash(command, unsetKeys, env)
	if code == 0 {
		r.rep.Pass(label)
		return nil
	}
	r.instruction(rule)
	if r.rep.Verbose && strings.TrimSpace(out) != "" {
		for _, line := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
			r.rep.Detail("    " + line)
		}
	}
	return r.rep.Fail(fmt.Sprintf("%s: command exited %d", label, code), report.SeverityOf(rule.Severity))
}

func (r *runner) instruction(rule *config.Rule) {
	if strings.TrimSpace(rule.Instruction) != "" {
		r.rep.Line(fmt.Sprintf("    → %s", rule.Instruction))
	}
}

func (r *runner) runBash(command string, unsetKeys []string, extra map[string]string) (string, int) {
	cmd := exec.Command("bash", "-c", command)
	cmd.Dir = r.dir

	drop := map[string]bool{}
	for _, k := range unsetKeys {
		drop[k] = true
	}
	var env []string
	for _, kv := range os.Environ() {
		if i := strings.IndexByte(kv, '='); i > 0 {
			k := kv[:i]
			if drop[k] {
				continue
			}
			if _, ok := extra[k]; ok {
				continue
			}
		}
		env = append(env, kv)
	}
	for k, v := range extra {
		env = append(env, k+"="+v)
	}
	cmd.Env = env

	out, err := cmd.CombinedOutput()
	if err == nil {
		return string(out), 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return string(out), ee.ExitCode()
	}
	return string(out) + err.Error(), 127
}
