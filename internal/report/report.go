// Package report owns all preflight terminal output: deferred section
// headers, [PASS]/[FAIL]/[WARN]/[SKIP] lines, and the final summary block.
// The format mirrors the original bash implementation so agents and CI
// parsing the output see no difference.
package report

import (
	"errors"
	"fmt"
	"io"
)

// ErrHardStop is returned by Fail for hard-stop severity; callers must
// unwind and exit 1 without evaluating further checks.
var ErrHardStop = errors.New("hard-stop")

type Severity int

const (
	SevError Severity = iota
	SevWarn
	SevHardStop
)

// SeverityOf maps a config string to a severity; anything unrecognised is
// treated as error, matching the bash fail() default case.
func SeverityOf(s string) Severity {
	switch s {
	case "warn":
		return SevWarn
	case "hard-stop":
		return SevHardStop
	default:
		return SevError
	}
}

type Reporter struct {
	Verbose  bool
	Errors   []string
	Warnings []string

	out     io.Writer
	errOut  io.Writer
	pending string
}

func New(verbose bool, out, errOut io.Writer) *Reporter {
	return &Reporter{Verbose: verbose, out: out, errOut: errOut}
}

// Section defers a header until the first line printed under it, so empty
// sections stay silent. A later Section before any output replaces it.
func (r *Reporter) Section(header string) { r.pending = header }

func (r *Reporter) Flush() {
	if r.pending != "" {
		fmt.Fprintf(r.out, "\n%s\n", r.pending)
		r.pending = ""
	}
}

func (r *Reporter) Pass(msg string) {
	if r.Verbose {
		r.Flush()
		fmt.Fprintf(r.out, "[PASS] %s\n", msg)
	}
}

func (r *Reporter) Skip(msg string) {
	if r.Verbose {
		r.Flush()
		fmt.Fprintf(r.out, "[SKIP] %s\n", msg)
	}
}

// Line prints a raw line (e.g. a rule's instruction) after flushing the
// pending header.
func (r *Reporter) Line(s string) {
	r.Flush()
	fmt.Fprintln(r.out, s)
}

// Detail writes auxiliary text (failing command output) to stderr.
func (r *Reporter) Detail(s string) {
	fmt.Fprintln(r.errOut, s)
}

func (r *Reporter) Fail(msg string, sev Severity) error {
	r.Flush()
	switch sev {
	case SevWarn:
		fmt.Fprintf(r.out, "[WARN] %s\n", msg)
		r.Warnings = append(r.Warnings, msg)
	case SevHardStop:
		fmt.Fprintf(r.out, "[FAIL] %s\n", msg)
		fmt.Fprintf(r.out, "[hard-stop] aborting preflight\n")
		return ErrHardStop
	default:
		fmt.Fprintf(r.out, "[FAIL] %s\n", msg)
		r.Errors = append(r.Errors, msg)
	}
	return nil
}

// StructuralFail prints a [FAIL] line without recording it in Errors; the
// config-lint phase counts these itself and aborts with a single hard-stop.
func (r *Reporter) StructuralFail(msg string) {
	r.Flush()
	fmt.Fprintf(r.out, "[FAIL] %s\n", msg)
}

const rule71 = "-----------------------------------------------------------------------"

// Summary prints the closing block and returns the process exit code.
func (r *Reporter) Summary() int {
	fmt.Fprintln(r.out, rule71)
	if len(r.Errors) == 0 && len(r.Warnings) == 0 {
		fmt.Fprintln(r.out, "  All checks passed")
		fmt.Fprintln(r.out, rule71)
		return 0
	}
	if len(r.Errors) > 0 {
		fmt.Fprintf(r.out, "  %d check(s) failed:\n", len(r.Errors))
		for _, e := range r.Errors {
			fmt.Fprintf(r.out, "    - %s\n", e)
		}
	}
	if len(r.Warnings) > 0 {
		fmt.Fprintf(r.out, "  %d warning(s):\n", len(r.Warnings))
		for _, w := range r.Warnings {
			fmt.Fprintf(r.out, "    - %s\n", w)
		}
	}
	fmt.Fprintln(r.out, rule71)
	if len(r.Errors) > 0 {
		return 1
	}
	return 0
}
