// Package preflight orchestrates a validation run: prerequisites, config
// load, config lint, rule evaluation, summary.
package preflight

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/arc-com/bumfuzzle/internal/config"
	"github.com/arc-com/bumfuzzle/internal/engine"
	"github.com/arc-com/bumfuzzle/internal/lint"
	"github.com/arc-com/bumfuzzle/internal/report"
)

const FileName = "bumfuzzle.yml"

// Run validates dir/bumfuzzle.yml and returns the process exit code.
func Run(dir string, verbose bool, version string, out, errOut io.Writer) int {
	rep := report.New(verbose, out, errOut)

	rep.Section("-- Prerequisites --------------------------------------------------------")

	if _, err := exec.LookPath("bash"); err != nil {
		rep.Flush()
		fmt.Fprintf(out, "[FAIL] bash is not installed - required to run checks\n")
		return 1
	}
	path := filepath.Join(dir, FileName)
	if _, err := os.Stat(path); err != nil {
		rep.Flush()
		fmt.Fprintf(out, "[FAIL] %s not found - cannot run validation\n", FileName)
		return 1
	}
	rep.Pass("bash is available")
	rep.Pass(FileName + " is present")
	rep.Pass("preflight v" + version)

	cfg, err := config.Load(path)

	rep.Section("-- Config Lint ----------------------------------------------------------")
	if err != nil {
		_ = rep.Fail(fmt.Sprintf("%s is not parseable YAML", FileName), report.SevHardStop)
		return 1
	}
	rep.Pass(FileName + " parses as YAML")

	if aborted := lint.Run(cfg, rep); aborted {
		return 1
	}

	if err := engine.Run(cfg, rep, dir); err != nil {
		if errors.Is(err, report.ErrHardStop) {
			return 1
		}
		fmt.Fprintf(errOut, "preflight: %v\n", err)
		return 1
	}

	return rep.Summary()
}
