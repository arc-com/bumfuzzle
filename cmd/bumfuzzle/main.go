package main

import (
	"fmt"
	"os"

	"github.com/arc-com/bumfuzzle/internal/preflight"
)

// version is injected at build time via -ldflags "-X main.version=$(cat VERSION)".
var version = "dev"

func usage(w *os.File) {
	fmt.Fprintf(w, "bumfuzzle v%s\n\n", version)
	fmt.Fprintf(w, "Usage: bumfuzzle <command> [options]\n\n")
	fmt.Fprintf(w, "Commands:\n")
	fmt.Fprintf(w, "  wizard               Start the browser-based config wizard\n")
	fmt.Fprintf(w, "  kickstart            Copy the default bumfuzzle.yml and install the pre-commit hook\n")
	fmt.Fprintf(w, "    --force              Overwrite an existing pre-commit hook\n")
	fmt.Fprintf(w, "  preflight            Validate bumfuzzle.yml in the current directory\n")
	fmt.Fprintf(w, "    -v, --verbose        Show passing checks\n")
	fmt.Fprintf(w, "  version              Print the version\n")
	fmt.Fprintf(w, "\n")
}

func main() {
	args := os.Args[1:]
	cmd := ""
	if len(args) > 0 {
		cmd = args[0]
		args = args[1:]
	}

	switch cmd {
	case "preflight":
		os.Exit(cmdPreflight(args))
	case "wizard":
		os.Exit(cmdWizard(args))
	case "kickstart":
		os.Exit(cmdKickstart(args))
	case "version", "--version":
		fmt.Println(version)
	case "", "-h", "--help", "help":
		usage(os.Stdout)
	default:
		fmt.Fprintf(os.Stderr, "bumfuzzle: unknown command: %s\n\n", cmd)
		usage(os.Stderr)
		os.Exit(1)
	}
}

func cmdPreflight(args []string) int {
	verbose := false
	for _, a := range args {
		switch a {
		case "-v", "--verbose":
			verbose = true
		default:
			fmt.Fprintf(os.Stdout, "Usage: bumfuzzle preflight [--verbose|-v]\n")
			return 1
		}
	}
	dir, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "bumfuzzle: %v\n", err)
		return 1
	}
	return preflight.Run(dir, verbose, version, os.Stdout, os.Stderr)
}

// cmdWizard is implemented in a later phase; the bash wizard remains the
// entry point until then.
func cmdWizard(args []string) int {
	fmt.Fprintln(os.Stderr, "bumfuzzle: wizard is not available in this build yet; use scripts/wizard.sh")
	return 1
}

// cmdKickstart is implemented in a later phase; the bash stub remains the
// entry point until then.
func cmdKickstart(args []string) int {
	fmt.Fprintln(os.Stderr, "bumfuzzle: kickstart is not available in this build yet; use scripts/kickstart.sh")
	return 1
}
