package releaseartifact

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestProductionTargetsAreExact(t *testing.T) {
	want := []string{"api", "migrator", "worker_ai", "worker_jobs", "worker_whatsapp"}
	if got := ProductionTargets(); !reflect.DeepEqual(got, want) {
		t.Fatalf("ProductionTargets() = %v, want %v", got, want)
	}
	got := ProductionTargets()
	got[0] = "mutated"
	if ProductionTargets()[0] != "api" {
		t.Fatal("ProductionTargets returned mutable package state")
	}
}

func TestBuildFlagsAreExact(t *testing.T) {
	want := []string{"-mod=readonly", "-trimpath", "-buildvcs=true", "-ldflags=-buildid="}
	if got := BuildFlags(); !reflect.DeepEqual(got, want) {
		t.Fatalf("BuildFlags() = %v, want %v", got, want)
	}
}

func TestMigrationFilesRequireOrdered0001Through0010(t *testing.T) {
	directory := t.TempDir()
	for number := 1; number <= 10; number++ {
		name := filepath.Join(directory, formatMigrationName(number))
		if err := os.WriteFile(name, []byte("SELECT 1;\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	files, err := migrationFiles(directory)
	if err != nil {
		t.Fatalf("migrationFiles() error = %v", err)
	}
	if len(files) != 10 || filepath.Base(files[0]) != "0001_test.sql" || filepath.Base(files[9]) != "0010_test.sql" {
		t.Fatalf("unexpected migration order: %v", files)
	}
	if err := os.Rename(filepath.Join(directory, "0005_test.sql"), filepath.Join(directory, "0011_test.sql")); err != nil {
		t.Fatal(err)
	}
	if _, err := migrationFiles(directory); err == nil || !strings.Contains(err.Error(), "sequence mismatch") {
		t.Fatalf("migrationFiles() error = %v, want sequence mismatch", err)
	}
}

func TestManifestIsStableAndDoesNotLeakEnvironmentOrPaths(t *testing.T) {
	t.Setenv("OPENAI_API_KEY", "must-never-appear-in-the-manifest")
	manifest := Manifest{
		SchemaVersion:   SchemaVersion,
		Repository:      "https://github.com/vbabanov/Kundi",
		SourceBranch:    "ui/reference-polish-pass-2",
		GitCommit:       strings.Repeat("a", 40),
		GitTree:         strings.Repeat("b", 40),
		GitCommitTime:   "2026-09-06T11:55:35+05:00",
		GoVersion:       RequiredGoVersion,
		GOOS:            TargetGOOS,
		GOARCH:          TargetGOARCH,
		GOAMD64:         TargetGOAMD64,
		CGOEnabled:      TargetCGOEnabled,
		BuildFlags:      BuildFlags(),
		Binaries:        []Binary{{Name: "api", Path: "bin/api", Size: 42, SHA256: strings.Repeat("c", 64), VCSRevision: strings.Repeat("a", 40)}},
		Migrations:      []Migration{{Filename: "0001_test.sql", SHA256: strings.Repeat("d", 64)}},
		PackageFilename: "kundi-backend-aaaaaaa-linux-amd64.tar.gz",
	}
	first, err := marshalManifest(manifest)
	if err != nil {
		t.Fatal(err)
	}
	second, err := marshalManifest(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if string(first) != string(second) {
		t.Fatal("manifest serialization is not stable")
	}
	cfg := Config{SourceRoot: `C:\private\source`, OutputRoot: `D:\private\output`, GoCache: `D:\private\cache`}
	if err := validateManifestPrivacy(first, cfg); err != nil {
		t.Fatalf("validateManifestPrivacy() error = %v", err)
	}
	for _, forbidden := range []string{cfg.SourceRoot, cfg.OutputRoot, cfg.GoCache, "must-never-appear-in-the-manifest", "OPENAI_API_KEY"} {
		if strings.Contains(string(first), forbidden) {
			t.Fatalf("manifest contains forbidden value %q", forbidden)
		}
	}
}

func TestValidateBuildSettings(t *testing.T) {
	sha := strings.Repeat("a", 40)
	valid := map[string]string{
		"GOOS":         TargetGOOS,
		"GOARCH":       TargetGOARCH,
		"GOAMD64":      TargetGOAMD64,
		"CGO_ENABLED":  TargetCGOEnabled,
		"vcs.revision": sha,
		"vcs.modified": "false",
	}
	if err := validateBuildSettings(valid, sha); err != nil {
		t.Fatalf("valid settings rejected: %v", err)
	}
	for name, mutate := range map[string]func(map[string]string){
		"missing revision": func(settings map[string]string) { delete(settings, "vcs.revision") },
		"dirty source":     func(settings map[string]string) { settings["vcs.modified"] = "true" },
		"wrong target":     func(settings map[string]string) { settings["GOARCH"] = "arm64" },
	} {
		t.Run(name, func(t *testing.T) {
			settings := make(map[string]string, len(valid))
			for key, value := range valid {
				settings[key] = value
			}
			mutate(settings)
			if err := validateBuildSettings(settings, sha); err == nil {
				t.Fatal("invalid build settings accepted")
			}
		})
	}
}

func TestDeterministicArchiveMetadata(t *testing.T) {
	fixedTime := time.Unix(1788677735, 0).UTC()
	firstArchive := createTestArchive(t, "first", fixedTime, time.Unix(100, 0))
	secondArchive := createTestArchive(t, "second", fixedTime, time.Unix(200, 0))
	firstHash, firstSize, err := fileSHA256(firstArchive)
	if err != nil {
		t.Fatal(err)
	}
	secondHash, secondSize, err := fileSHA256(secondArchive)
	if err != nil {
		t.Fatal(err)
	}
	if firstSize != secondSize || firstHash != secondHash {
		t.Fatalf("archives differ: %d/%s != %d/%s", firstSize, firstHash, secondSize, secondHash)
	}

	file, err := os.Open(firstArchive)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	gzipReader, err := gzip.NewReader(file)
	if err != nil {
		t.Fatal(err)
	}
	defer gzipReader.Close()
	if !gzipReader.ModTime.IsZero() || gzipReader.Name != "" || gzipReader.Comment != "" {
		t.Fatalf("gzip metadata is not normalized: %+v", gzipReader.Header)
	}
	tarReader := tar.NewReader(gzipReader)
	var names []string
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		names = append(names, header.Name)
		if header.Uid != 0 || header.Gid != 0 || header.Uname != "" || header.Gname != "" {
			t.Fatalf("owner metadata is not normalized for %s", header.Name)
		}
		if !header.ModTime.Equal(fixedTime) {
			t.Fatalf("mtime for %s = %s, want %s", header.Name, header.ModTime, fixedTime)
		}
		wantMode := int64(0o644)
		if strings.Contains(header.Name, "/bin/") {
			wantMode = 0o755
		}
		if header.Mode != wantMode {
			t.Fatalf("mode for %s = %o, want %o", header.Name, header.Mode, wantMode)
		}
	}
	wantNames := []string{
		"kundi-backend-aaaaaaa/RELEASE_MANIFEST.json",
		"kundi-backend-aaaaaaa/SHA256SUMS",
		"kundi-backend-aaaaaaa/bin/api",
		"kundi-backend-aaaaaaa/migrations/0001_test.sql",
	}
	if !reflect.DeepEqual(names, wantNames) {
		t.Fatalf("archive paths = %v, want sorted %v", names, wantNames)
	}
}

func TestNormalizeRepositoryRemovesCredentials(t *testing.T) {
	got, err := normalizeRepository("https://user:secret@example.com/org/repo.git?token=bad#fragment")
	if err != nil {
		t.Fatal(err)
	}
	if got != "https://example.com/org/repo" {
		t.Fatalf("normalizeRepository() = %q", got)
	}
}

func createTestArchive(t *testing.T, directoryName string, fixedTime, fileTime time.Time) string {
	t.Helper()
	directory := filepath.Join(t.TempDir(), directoryName)
	packageRoot := filepath.Join(directory, "kundi-backend-aaaaaaa")
	for _, subdirectory := range []string{"bin", "migrations"} {
		if err := os.MkdirAll(filepath.Join(packageRoot, subdirectory), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	files := map[string]string{
		"bin/api":                  "binary contents",
		"migrations/0001_test.sql": "SELECT 1;\n",
		"RELEASE_MANIFEST.json":    "{}\n",
		"SHA256SUMS":               "checksum data\n",
	}
	for relativePath, contents := range files {
		path := filepath.Join(packageRoot, filepath.FromSlash(relativePath))
		if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(path, fileTime, fileTime); err != nil {
			t.Fatal(err)
		}
	}
	archivePath := filepath.Join(directory, "artifact.tar.gz")
	if err := writeArchive(packageRoot, archivePath, "kundi-backend-aaaaaaa", fixedTime); err != nil {
		t.Fatal(err)
	}
	return archivePath
}

func formatMigrationName(number int) string {
	return fmt.Sprintf("%04d_test.sql", number)
}
