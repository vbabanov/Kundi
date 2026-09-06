package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/kundi/kundi/backend/internal/releaseartifact"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "build":
		err = build(os.Args[2:])
	case "compare":
		err = compare(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "releasepack: %v\n", err)
		os.Exit(1)
	}
}

func build(args []string) error {
	flags := flag.NewFlagSet("build", flag.ContinueOnError)
	var cfg releaseartifact.Config
	flags.StringVar(&cfg.SourceRoot, "source-root", "", "clean Git worktree containing the source commit")
	flags.StringVar(&cfg.OutputRoot, "output-root", "", "new output directory outside the source worktree")
	flags.StringVar(&cfg.GoCache, "gocache", "", "dedicated Go build cache outside the source worktree")
	flags.StringVar(&cfg.GoCommand, "go", "go", "exact Go 1.24.0 command")
	flags.StringVar(&cfg.ExpectedSHA, "expected-sha", "", "required full source commit SHA")
	flags.StringVar(&cfg.SourceBranch, "source-branch", "", "required origin source branch")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected positional arguments: %v", flags.Args())
	}
	result, err := releaseartifact.Build(cfg)
	if err != nil {
		return err
	}
	fmt.Printf("archive_sha256=%s\n", result.ArchiveSHA)
	fmt.Printf("archive=%s\n", result.ArchivePath)
	fmt.Printf("manifest=%s\n", result.ManifestPath)
	fmt.Printf("artifact_checksum=%s\n", result.ArtifactPath)
	return nil
}

func compare(args []string) error {
	flags := flag.NewFlagSet("compare", flag.ContinueOnError)
	var buildA string
	var buildB string
	flags.StringVar(&buildA, "build-a", "", "Build A output directory")
	flags.StringVar(&buildB, "build-b", "", "Build B output directory")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if buildA == "" || buildB == "" {
		return fmt.Errorf("build-a and build-b are required")
	}
	comparison, err := releaseartifact.Compare(buildA, buildB)
	if err != nil {
		return err
	}
	for _, binary := range comparison.Binaries {
		fmt.Printf("binary=%s size=%d sha256=%s vcs.revision=%s vcs.modified=%t\n",
			binary.Name, binary.Size, binary.SHA256, binary.VCSRevision, binary.VCSModified)
	}
	for _, migration := range comparison.Migrations {
		fmt.Printf("migration=%s sha256=%s\n", migration.Filename, migration.SHA256)
	}
	fmt.Printf("archive_sha256=%s\n", comparison.ArchiveSHA)
	return nil
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: releasepack <build|compare> [flags]")
}
