package releaseartifact

import (
	"archive/tar"
	"bufio"
	"compress/gzip"
	"crypto/sha256"
	"debug/buildinfo"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	RequiredGoVersion = "go1.24.0"
	TargetGOOS        = "linux"
	TargetGOARCH      = "amd64"
	TargetGOAMD64     = "v1"
	TargetCGOEnabled  = "0"
	SchemaVersion     = 1
)

var productionTargets = []string{
	"api",
	"migrator",
	"worker_ai",
	"worker_jobs",
	"worker_whatsapp",
}

var requiredBuildFlags = []string{
	"-mod=readonly",
	"-trimpath",
	"-buildvcs=true",
	"-ldflags=-buildid=",
}

type Config struct {
	SourceRoot   string
	OutputRoot   string
	GoCache      string
	GoCommand    string
	ExpectedSHA  string
	SourceBranch string
}

type Binary struct {
	Name        string `json:"name"`
	Path        string `json:"path"`
	Size        int64  `json:"size"`
	SHA256      string `json:"sha256"`
	VCSRevision string `json:"vcs_revision"`
	VCSModified bool   `json:"vcs_modified"`
}

type Migration struct {
	Filename string `json:"filename"`
	SHA256   string `json:"sha256"`
}

type Manifest struct {
	SchemaVersion   int         `json:"schema_version"`
	Repository      string      `json:"repository"`
	SourceBranch    string      `json:"source_branch"`
	GitCommit       string      `json:"git_commit"`
	GitTree         string      `json:"git_tree"`
	GitCommitTime   string      `json:"git_commit_time"`
	GoVersion       string      `json:"go_version"`
	GOOS            string      `json:"goos"`
	GOARCH          string      `json:"goarch"`
	GOAMD64         string      `json:"goamd64"`
	CGOEnabled      string      `json:"cgo_enabled"`
	BuildFlags      []string    `json:"build_flags"`
	Binaries        []Binary    `json:"binaries"`
	Migrations      []Migration `json:"migrations"`
	PackageFilename string      `json:"package_filename"`
}

type Result struct {
	ManifestPath string
	ArchivePath  string
	ArtifactPath string
	ArchiveSHA   string
}

type Comparison struct {
	ArchiveSHA string
	Binaries   []Binary
	Migrations []Migration
}

type buildMetadata struct {
	Repository     string
	Commit         string
	Tree           string
	CommitTime     string
	CommitUnix     int64
	GoVersion      string
	MigrationNames []string
}

type archiveEntry struct {
	SourcePath  string
	ArchivePath string
	Mode        int64
}

func ProductionTargets() []string {
	return append([]string(nil), productionTargets...)
}

func BuildFlags() []string {
	return append([]string(nil), requiredBuildFlags...)
}

func Build(cfg Config) (Result, error) {
	if err := normalizeConfig(&cfg); err != nil {
		return Result{}, err
	}
	meta, err := preflight(cfg)
	if err != nil {
		return Result{}, err
	}

	shortSHA := cfg.ExpectedSHA[:7]
	packageBase := fmt.Sprintf("kundi-backend-%s", shortSHA)
	packageFilename := fmt.Sprintf("%s-linux-amd64.tar.gz", packageBase)
	packageRoot := filepath.Join(cfg.OutputRoot, packageBase)
	if _, err := os.Stat(cfg.OutputRoot); err == nil {
		return Result{}, fmt.Errorf("output root already exists: %s", cfg.OutputRoot)
	} else if !errors.Is(err, os.ErrNotExist) {
		return Result{}, fmt.Errorf("inspect output root: %w", err)
	}
	if err := os.MkdirAll(filepath.Join(packageRoot, "bin"), 0o755); err != nil {
		return Result{}, fmt.Errorf("create package directories: %w", err)
	}
	if err := os.MkdirAll(filepath.Join(packageRoot, "migrations"), 0o755); err != nil {
		return Result{}, fmt.Errorf("create migration directory: %w", err)
	}
	if err := os.MkdirAll(cfg.GoCache, 0o755); err != nil {
		return Result{}, fmt.Errorf("create Go cache: %w", err)
	}

	manifest := Manifest{
		SchemaVersion:   SchemaVersion,
		Repository:      meta.Repository,
		SourceBranch:    cfg.SourceBranch,
		GitCommit:       meta.Commit,
		GitTree:         meta.Tree,
		GitCommitTime:   meta.CommitTime,
		GoVersion:       meta.GoVersion,
		GOOS:            TargetGOOS,
		GOARCH:          TargetGOARCH,
		GOAMD64:         TargetGOAMD64,
		CGOEnabled:      TargetCGOEnabled,
		BuildFlags:      BuildFlags(),
		PackageFilename: packageFilename,
	}

	for _, name := range productionTargets {
		if err := requireClean(cfg.SourceRoot); err != nil {
			return Result{}, fmt.Errorf("source must be clean before building %s: %w", name, err)
		}
		binaryPath := filepath.Join(packageRoot, "bin", name)
		args := append(BuildFlags(), "-o", binaryPath, "./cmd/"+name)
		if err := runGo(cfg, filepath.Join(cfg.SourceRoot, "backend"), "build", args...); err != nil {
			return Result{}, fmt.Errorf("build %s: %w", name, err)
		}
		binary, err := inspectBinary(binaryPath, name, cfg.ExpectedSHA)
		if err != nil {
			return Result{}, err
		}
		manifest.Binaries = append(manifest.Binaries, binary)
	}

	for _, filename := range meta.MigrationNames {
		destination := filepath.Join(packageRoot, "migrations", filename)
		contents, err := gitBytes(cfg.SourceRoot, "cat-file", "blob", "HEAD:backend/migrations/"+filename)
		if err != nil {
			return Result{}, fmt.Errorf("read migration Git blob %s: %w", filename, err)
		}
		if err := os.WriteFile(destination, contents, 0o644); err != nil {
			return Result{}, fmt.Errorf("write migration %s: %w", filename, err)
		}
		hash, _, err := fileSHA256(destination)
		if err != nil {
			return Result{}, err
		}
		manifest.Migrations = append(manifest.Migrations, Migration{Filename: filename, SHA256: hash})
	}

	manifestBytes, err := marshalManifest(manifest)
	if err != nil {
		return Result{}, err
	}
	if err := validateManifestPrivacy(manifestBytes, cfg); err != nil {
		return Result{}, err
	}
	insideManifest := filepath.Join(packageRoot, "RELEASE_MANIFEST.json")
	if err := os.WriteFile(insideManifest, manifestBytes, 0o644); err != nil {
		return Result{}, fmt.Errorf("write release manifest: %w", err)
	}
	if err := writeChecksums(packageRoot); err != nil {
		return Result{}, err
	}

	archivePath := filepath.Join(cfg.OutputRoot, packageFilename)
	if err := writeArchive(packageRoot, archivePath, packageBase, time.Unix(meta.CommitUnix, 0).UTC()); err != nil {
		return Result{}, err
	}
	archiveHash, _, err := fileSHA256(archivePath)
	if err != nil {
		return Result{}, err
	}
	adjacentManifest := filepath.Join(cfg.OutputRoot, "RELEASE_MANIFEST.json")
	if err := os.WriteFile(adjacentManifest, manifestBytes, 0o644); err != nil {
		return Result{}, fmt.Errorf("write adjacent manifest: %w", err)
	}
	artifactPath := filepath.Join(cfg.OutputRoot, "ARTIFACT_SHA256.txt")
	artifactLine := fmt.Sprintf("%s  %s\n", archiveHash, packageFilename)
	if err := os.WriteFile(artifactPath, []byte(artifactLine), 0o644); err != nil {
		return Result{}, fmt.Errorf("write artifact checksum: %w", err)
	}
	if err := requireClean(cfg.SourceRoot); err != nil {
		return Result{}, fmt.Errorf("source became dirty during release build: %w", err)
	}

	return Result{
		ManifestPath: adjacentManifest,
		ArchivePath:  archivePath,
		ArtifactPath: artifactPath,
		ArchiveSHA:   archiveHash,
	}, nil
}

func Compare(outputA, outputB string) (Comparison, error) {
	manifestA, rawA, err := readManifest(filepath.Join(outputA, "RELEASE_MANIFEST.json"))
	if err != nil {
		return Comparison{}, fmt.Errorf("read build A manifest: %w", err)
	}
	manifestB, rawB, err := readManifest(filepath.Join(outputB, "RELEASE_MANIFEST.json"))
	if err != nil {
		return Comparison{}, fmt.Errorf("read build B manifest: %w", err)
	}
	if string(rawA) != string(rawB) {
		return Comparison{}, errors.New("release manifests differ")
	}
	if len(manifestA.Binaries) != len(productionTargets) || len(manifestB.Binaries) != len(productionTargets) {
		return Comparison{}, errors.New("manifest does not contain the exact production binary set")
	}
	for index, expectedName := range productionTargets {
		a := manifestA.Binaries[index]
		b := manifestB.Binaries[index]
		if a.Name != expectedName || b.Name != expectedName {
			return Comparison{}, fmt.Errorf("binary order or name mismatch at index %d", index)
		}
		if a.Size != b.Size || a.SHA256 != b.SHA256 {
			return Comparison{}, fmt.Errorf("binary %s is not reproducible", expectedName)
		}
		if err := verifyManifestFile(outputA, manifestA, a.Path, a.SHA256, a.Size); err != nil {
			return Comparison{}, fmt.Errorf("verify build A binary %s: %w", expectedName, err)
		}
		if err := verifyManifestFile(outputB, manifestB, b.Path, b.SHA256, b.Size); err != nil {
			return Comparison{}, fmt.Errorf("verify build B binary %s: %w", expectedName, err)
		}
	}
	if len(manifestA.Migrations) != len(manifestB.Migrations) {
		return Comparison{}, errors.New("migration counts differ")
	}
	for index := range manifestA.Migrations {
		if manifestA.Migrations[index] != manifestB.Migrations[index] {
			return Comparison{}, fmt.Errorf("migration %s differs", manifestA.Migrations[index].Filename)
		}
		migration := manifestA.Migrations[index]
		relativePath := filepath.ToSlash(filepath.Join("migrations", migration.Filename))
		if err := verifyManifestFile(outputA, manifestA, relativePath, migration.SHA256, -1); err != nil {
			return Comparison{}, fmt.Errorf("verify build A migration %s: %w", migration.Filename, err)
		}
		if err := verifyManifestFile(outputB, manifestB, relativePath, migration.SHA256, -1); err != nil {
			return Comparison{}, fmt.Errorf("verify build B migration %s: %w", migration.Filename, err)
		}
	}
	archiveA := filepath.Join(outputA, manifestA.PackageFilename)
	archiveB := filepath.Join(outputB, manifestB.PackageFilename)
	hashA, sizeA, err := fileSHA256(archiveA)
	if err != nil {
		return Comparison{}, fmt.Errorf("hash build A archive: %w", err)
	}
	hashB, sizeB, err := fileSHA256(archiveB)
	if err != nil {
		return Comparison{}, fmt.Errorf("hash build B archive: %w", err)
	}
	if sizeA != sizeB || hashA != hashB {
		return Comparison{}, errors.New("release archives are not reproducible")
	}
	return Comparison{ArchiveSHA: hashA, Binaries: manifestA.Binaries, Migrations: manifestA.Migrations}, nil
}

func normalizeConfig(cfg *Config) error {
	if cfg.GoCommand == "" {
		cfg.GoCommand = "go"
	}
	if cfg.SourceRoot == "" || cfg.OutputRoot == "" || cfg.GoCache == "" || cfg.ExpectedSHA == "" || cfg.SourceBranch == "" {
		return errors.New("source-root, output-root, gocache, expected-sha, and source-branch are required")
	}
	if !regexp.MustCompile(`^[0-9a-f]{40}$`).MatchString(cfg.ExpectedSHA) {
		return fmt.Errorf("expected SHA must be a full lowercase 40-character Git SHA: %q", cfg.ExpectedSHA)
	}
	var err error
	if cfg.SourceRoot, err = filepath.Abs(cfg.SourceRoot); err != nil {
		return fmt.Errorf("resolve source root: %w", err)
	}
	if cfg.OutputRoot, err = filepath.Abs(cfg.OutputRoot); err != nil {
		return fmt.Errorf("resolve output root: %w", err)
	}
	if cfg.GoCache, err = filepath.Abs(cfg.GoCache); err != nil {
		return fmt.Errorf("resolve Go cache: %w", err)
	}
	for label, candidate := range map[string]string{"output root": cfg.OutputRoot, "Go cache": cfg.GoCache} {
		inside, err := pathInside(cfg.SourceRoot, candidate)
		if err != nil {
			return err
		}
		if inside {
			return fmt.Errorf("%s must be outside the Git working tree: %s", label, candidate)
		}
	}
	return nil
}

func preflight(cfg Config) (buildMetadata, error) {
	if err := requireClean(cfg.SourceRoot); err != nil {
		return buildMetadata{}, err
	}
	commit, err := gitOutput(cfg.SourceRoot, "rev-parse", "HEAD")
	if err != nil {
		return buildMetadata{}, err
	}
	if commit != cfg.ExpectedSHA {
		return buildMetadata{}, fmt.Errorf("wrong source SHA: got %s, want %s", commit, cfg.ExpectedSHA)
	}
	remoteCommit, err := gitOutput(cfg.SourceRoot, "rev-parse", "refs/remotes/origin/"+cfg.SourceBranch)
	if err != nil {
		return buildMetadata{}, fmt.Errorf("resolve source branch: %w", err)
	}
	if remoteCommit != cfg.ExpectedSHA {
		return buildMetadata{}, fmt.Errorf("source branch origin/%s is %s, want %s", cfg.SourceBranch, remoteCommit, cfg.ExpectedSHA)
	}
	goVersion, err := commandOutput(cfg.SourceRoot, goEnvironment(cfg, os.Environ()), cfg.GoCommand, "version")
	if err != nil {
		return buildMetadata{}, fmt.Errorf("read Go version: %w", err)
	}
	fields := strings.Fields(goVersion)
	if len(fields) < 3 || fields[0] != "go" || fields[1] != "version" || fields[2] != RequiredGoVersion {
		return buildMetadata{}, fmt.Errorf("wrong Go toolchain: got %q, require exact %s", goVersion, RequiredGoVersion)
	}
	goDirective, err := readGoDirective(filepath.Join(cfg.SourceRoot, "backend", "go.mod"))
	if err != nil {
		return buildMetadata{}, err
	}
	if "go"+goDirective != RequiredGoVersion {
		return buildMetadata{}, fmt.Errorf("backend/go.mod declares go %s, require %s", goDirective, strings.TrimPrefix(RequiredGoVersion, "go"))
	}
	migrations, err := migrationFiles(filepath.Join(cfg.SourceRoot, "backend", "migrations"))
	if err != nil {
		return buildMetadata{}, err
	}
	tree, err := gitOutput(cfg.SourceRoot, "rev-parse", "HEAD^{tree}")
	if err != nil {
		return buildMetadata{}, err
	}
	commitTime, err := gitOutput(cfg.SourceRoot, "show", "-s", "--format=%cI", "HEAD")
	if err != nil {
		return buildMetadata{}, err
	}
	commitUnixRaw, err := gitOutput(cfg.SourceRoot, "show", "-s", "--format=%ct", "HEAD")
	if err != nil {
		return buildMetadata{}, err
	}
	commitUnix, err := strconv.ParseInt(commitUnixRaw, 10, 64)
	if err != nil {
		return buildMetadata{}, fmt.Errorf("parse commit time: %w", err)
	}
	remote, err := gitOutput(cfg.SourceRoot, "remote", "get-url", "origin")
	if err != nil {
		return buildMetadata{}, err
	}
	repository, err := normalizeRepository(remote)
	if err != nil {
		return buildMetadata{}, err
	}
	migrationNames := make([]string, 0, len(migrations))
	for _, path := range migrations {
		migrationNames = append(migrationNames, filepath.Base(path))
	}
	return buildMetadata{
		Repository: repository, Commit: commit, Tree: tree, CommitTime: commitTime,
		CommitUnix: commitUnix, GoVersion: RequiredGoVersion, MigrationNames: migrationNames,
	}, nil
}

func runGo(cfg Config, directory, operation string, args ...string) error {
	allArgs := append([]string{operation}, args...)
	command := exec.Command(cfg.GoCommand, allArgs...)
	command.Dir = directory
	command.Env = goEnvironment(cfg, os.Environ())
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("%s %s: %w", cfg.GoCommand, strings.Join(allArgs, " "), err)
	}
	return nil
}

func goEnvironment(cfg Config, base []string) []string {
	blocked := map[string]bool{
		"CGO_ENABLED": true, "GOAMD64": true, "GOARCH": true, "GOCACHE": true,
		"GOENV": true, "GOEXPERIMENT": true, "GOFLAGS": true, "GOOS": true,
		"GOTOOLCHAIN": true,
	}
	environment := make([]string, 0, len(base)+9)
	for _, item := range base {
		key := item
		if index := strings.IndexByte(item, '='); index >= 0 {
			key = item[:index]
		}
		if !blocked[strings.ToUpper(key)] {
			environment = append(environment, item)
		}
	}
	environment = append(environment,
		"CGO_ENABLED="+TargetCGOEnabled,
		"GOAMD64="+TargetGOAMD64,
		"GOARCH="+TargetGOARCH,
		"GOCACHE="+cfg.GoCache,
		"GOENV=off",
		"GOEXPERIMENT=",
		"GOOS="+TargetGOOS,
		"GOTOOLCHAIN=local",
	)
	return environment
}

func inspectBinary(path, name, expectedSHA string) (Binary, error) {
	info, err := buildinfo.ReadFile(path)
	if err != nil {
		return Binary{}, fmt.Errorf("read build info for %s: %w", name, err)
	}
	settings := make(map[string]string, len(info.Settings))
	for _, setting := range info.Settings {
		settings[setting.Key] = setting.Value
	}
	if err := validateBuildSettings(settings, expectedSHA); err != nil {
		return Binary{}, fmt.Errorf("invalid build info for %s: %w", name, err)
	}
	if info.GoVersion != RequiredGoVersion {
		return Binary{}, fmt.Errorf("invalid build info for %s: Go version %s, want %s", name, info.GoVersion, RequiredGoVersion)
	}
	hash, size, err := fileSHA256(path)
	if err != nil {
		return Binary{}, err
	}
	return Binary{
		Name: name, Path: filepath.ToSlash(filepath.Join("bin", name)), Size: size, SHA256: hash,
		VCSRevision: settings["vcs.revision"], VCSModified: false,
	}, nil
}

func validateBuildSettings(settings map[string]string, expectedSHA string) error {
	expected := map[string]string{
		"GOOS": TargetGOOS, "GOARCH": TargetGOARCH, "GOAMD64": TargetGOAMD64,
		"CGO_ENABLED":  TargetCGOEnabled,
		"vcs.revision": expectedSHA, "vcs.modified": "false",
	}
	for key, want := range expected {
		got, ok := settings[key]
		if !ok {
			return fmt.Errorf("missing %s", key)
		}
		if got != want {
			return fmt.Errorf("%s=%s, want %s", key, got, want)
		}
	}
	return nil
}

func migrationFiles(directory string) ([]string, error) {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return nil, fmt.Errorf("read migrations: %w", err)
	}
	var files []string
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".sql") {
			files = append(files, filepath.Join(directory, entry.Name()))
		}
	}
	sort.Strings(files)
	if len(files) != 11 {
		return nil, fmt.Errorf("require exactly 11 SQL migrations, found %d", len(files))
	}
	for index, path := range files {
		prefix := fmt.Sprintf("%04d_", index+1)
		if !strings.HasPrefix(filepath.Base(path), prefix) {
			return nil, fmt.Errorf("migration sequence mismatch at %d: %s", index+1, filepath.Base(path))
		}
	}
	return files, nil
}

func writeChecksums(packageRoot string) error {
	var relativePaths []string
	for _, directory := range []string{"bin", "migrations"} {
		entries, err := os.ReadDir(filepath.Join(packageRoot, directory))
		if err != nil {
			return fmt.Errorf("read %s for checksums: %w", directory, err)
		}
		for _, entry := range entries {
			if !entry.IsDir() {
				relativePaths = append(relativePaths, filepath.ToSlash(filepath.Join(directory, entry.Name())))
			}
		}
	}
	relativePaths = append(relativePaths, "RELEASE_MANIFEST.json")
	sort.Strings(relativePaths)
	var builder strings.Builder
	for _, relativePath := range relativePaths {
		hash, _, err := fileSHA256(filepath.Join(packageRoot, filepath.FromSlash(relativePath)))
		if err != nil {
			return err
		}
		fmt.Fprintf(&builder, "%s  %s\n", hash, relativePath)
	}
	if err := os.WriteFile(filepath.Join(packageRoot, "SHA256SUMS"), []byte(builder.String()), 0o644); err != nil {
		return fmt.Errorf("write SHA256SUMS: %w", err)
	}
	return nil
}

func writeArchive(packageRoot, archivePath, packageBase string, modTime time.Time) error {
	entries, err := collectArchiveEntries(packageRoot, packageBase)
	if err != nil {
		return err
	}
	file, err := os.Create(archivePath)
	if err != nil {
		return fmt.Errorf("create archive: %w", err)
	}
	success := false
	defer func() {
		_ = file.Close()
		if !success {
			_ = os.Remove(archivePath)
		}
	}()
	gzipWriter, err := gzip.NewWriterLevel(file, gzip.BestCompression)
	if err != nil {
		return fmt.Errorf("create gzip writer: %w", err)
	}
	gzipWriter.Header.ModTime = time.Unix(0, 0).UTC()
	gzipWriter.Header.Name = ""
	gzipWriter.Header.Comment = ""
	gzipWriter.Header.OS = 255
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range entries {
		info, err := os.Stat(entry.SourcePath)
		if err != nil {
			return fmt.Errorf("stat archive entry: %w", err)
		}
		header := &tar.Header{
			Name: entry.ArchivePath, Mode: entry.Mode, Size: info.Size(),
			ModTime: modTime, Typeflag: tar.TypeReg, Uid: 0, Gid: 0,
			Uname: "", Gname: "", Format: tar.FormatUSTAR,
		}
		if err := tarWriter.WriteHeader(header); err != nil {
			return fmt.Errorf("write archive header %s: %w", entry.ArchivePath, err)
		}
		input, err := os.Open(entry.SourcePath)
		if err != nil {
			return fmt.Errorf("open archive entry: %w", err)
		}
		_, copyErr := io.Copy(tarWriter, input)
		closeErr := input.Close()
		if copyErr != nil {
			return fmt.Errorf("write archive entry: %w", copyErr)
		}
		if closeErr != nil {
			return fmt.Errorf("close archive entry: %w", closeErr)
		}
	}
	if err := tarWriter.Close(); err != nil {
		return fmt.Errorf("close tar stream: %w", err)
	}
	if err := gzipWriter.Close(); err != nil {
		return fmt.Errorf("close gzip stream: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close archive file: %w", err)
	}
	success = true
	return nil
}

func collectArchiveEntries(packageRoot, packageBase string) ([]archiveEntry, error) {
	var entries []archiveEntry
	err := filepath.Walk(packageRoot, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if info.IsDir() {
			return nil
		}
		relativePath, err := filepath.Rel(packageRoot, path)
		if err != nil {
			return err
		}
		mode := int64(0o644)
		if strings.HasPrefix(filepath.ToSlash(relativePath), "bin/") {
			mode = 0o755
		}
		entries = append(entries, archiveEntry{
			SourcePath:  path,
			ArchivePath: packageBase + "/" + filepath.ToSlash(relativePath),
			Mode:        mode,
		})
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("collect archive entries: %w", err)
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].ArchivePath < entries[j].ArchivePath })
	return entries, nil
}

func marshalManifest(manifest Manifest) ([]byte, error) {
	bytes, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("marshal release manifest: %w", err)
	}
	return append(bytes, '\n'), nil
}

func validateManifestPrivacy(contents []byte, cfg Config) error {
	text := string(contents)
	for label, value := range map[string]string{
		"source root": cfg.SourceRoot, "output root": cfg.OutputRoot, "Go cache": cfg.GoCache,
	} {
		if value != "" && strings.Contains(strings.ToLower(text), strings.ToLower(value)) {
			return fmt.Errorf("manifest leaks absolute %s", label)
		}
	}
	for _, forbidden := range []string{"OPENAI_API_KEY", "AZURE_OPENAI_API_KEY", "DATABASE_URL", "POSTGRES_PASSWORD", "MINIO_ROOT_PASSWORD"} {
		if strings.Contains(text, forbidden) {
			return fmt.Errorf("manifest contains forbidden environment key %s", forbidden)
		}
	}
	return nil
}

func readManifest(path string) (Manifest, []byte, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return Manifest{}, nil, err
	}
	var manifest Manifest
	if err := json.Unmarshal(contents, &manifest); err != nil {
		return Manifest{}, nil, err
	}
	return manifest, contents, nil
}

func verifyManifestFile(outputRoot string, manifest Manifest, relativePath, expectedHash string, expectedSize int64) error {
	if len(manifest.GitCommit) < 7 {
		return errors.New("manifest Git commit is too short")
	}
	packageRoot := filepath.Join(outputRoot, "kundi-backend-"+manifest.GitCommit[:7])
	path := filepath.Join(packageRoot, filepath.FromSlash(relativePath))
	hash, size, err := fileSHA256(path)
	if err != nil {
		return err
	}
	if hash != expectedHash {
		return fmt.Errorf("SHA-256=%s, manifest=%s", hash, expectedHash)
	}
	if expectedSize >= 0 && size != expectedSize {
		return fmt.Errorf("size=%d, manifest=%d", size, expectedSize)
	}
	return nil
}

func requireClean(directory string) error {
	status, err := gitOutput(directory, "status", "--porcelain=v1", "--untracked-files=all")
	if err != nil {
		return err
	}
	if status != "" {
		return fmt.Errorf("Git working tree is dirty:\n%s", status)
	}
	return nil
}

func gitOutput(directory string, args ...string) (string, error) {
	return commandOutput(directory, nil, "git", args...)
}

func gitBytes(directory string, args ...string) ([]byte, error) {
	command := exec.Command("git", args...)
	command.Dir = directory
	output, err := command.Output()
	if err != nil {
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			return nil, fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(exitError.Stderr)))
		}
		return nil, fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return output, nil
}

func commandOutput(directory string, environment []string, name string, args ...string) (string, error) {
	command := exec.Command(name, args...)
	command.Dir = directory
	if environment != nil {
		command.Env = environment
	}
	output, err := command.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
	return strings.TrimSpace(string(output)), nil
}

func readGoDirective(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open go.mod: %w", err)
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) == 2 && fields[0] == "go" {
			return fields[1], nil
		}
	}
	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("read go.mod: %w", err)
	}
	return "", errors.New("go.mod has no go directive")
}

func normalizeRepository(remote string) (string, error) {
	remote = strings.TrimSpace(remote)
	if parsed, err := url.Parse(remote); err == nil && parsed.Scheme != "" {
		parsed.User = nil
		parsed.RawQuery = ""
		parsed.Fragment = ""
		parsed.Path = strings.TrimSuffix(parsed.Path, ".git")
		return strings.TrimSuffix(parsed.String(), "/"), nil
	}
	if at := strings.Index(remote, "@"); at >= 0 {
		remote = remote[at+1:]
	}
	remote = strings.Replace(remote, ":", "/", 1)
	remote = strings.TrimSuffix(remote, ".git")
	if remote == "" {
		return "", errors.New("empty repository remote")
	}
	return remote, nil
}

func pathInside(parent, candidate string) (bool, error) {
	relative, err := filepath.Rel(parent, candidate)
	if err != nil {
		return false, fmt.Errorf("compare paths: %w", err)
	}
	return relative == "." || (relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator))), nil
}

func fileSHA256(path string) (string, int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", 0, fmt.Errorf("open %s for hashing: %w", path, err)
	}
	defer file.Close()
	hash := sha256.New()
	size, err := io.Copy(hash, file)
	if err != nil {
		return "", 0, fmt.Errorf("hash %s: %w", path, err)
	}
	return hex.EncodeToString(hash.Sum(nil)), size, nil
}
