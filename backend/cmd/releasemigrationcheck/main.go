package main

import (
	"context"
	"crypto/sha256"
	"debug/buildinfo"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type releaseManifest struct {
	GitCommit string `json:"git_commit"`
	GOOS      string `json:"goos"`
	GOARCH    string `json:"goarch"`
	Binaries  []struct {
		Name        string `json:"name"`
		SHA256      string `json:"sha256"`
		VCSRevision string `json:"vcs_revision"`
		VCSModified bool   `json:"vcs_modified"`
	} `json:"binaries"`
	Migrations []struct {
		Filename string `json:"filename"`
	} `json:"migrations"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "release migration check: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var packageRoot string
	var expectedSHA string
	flag.StringVar(&packageRoot, "package-root", "", "unmodified Build A package root")
	flag.StringVar(&expectedSHA, "expected-sha", "", "expected full source SHA")
	flag.Parse()
	if packageRoot == "" || len(expectedSHA) != 40 {
		return errors.New("package-root and a full expected-sha are required")
	}
	packageRoot, err := filepath.Abs(packageRoot)
	if err != nil {
		return fmt.Errorf("resolve package root: %w", err)
	}
	migratorPath := filepath.Join(packageRoot, "bin", "migrator")

	manifest, err := readManifest(filepath.Join(packageRoot, "RELEASE_MANIFEST.json"))
	if err != nil {
		return err
	}
	if err := verifyManifest(manifest, expectedSHA); err != nil {
		return err
	}
	migratorSHA, revision, modified, err := inspectMigrator(migratorPath, manifest, expectedSHA)
	if err != nil {
		return err
	}

	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if databaseURL == "" {
		return errors.New("DATABASE_URL is required")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return fmt.Errorf("connect disposable PostgreSQL: %w", err)
	}
	defer pool.Close()

	var serverVersion string
	if err := pool.QueryRow(ctx, `SHOW server_version`).Scan(&serverVersion); err != nil {
		return fmt.Errorf("read PostgreSQL server version: %w", err)
	}
	if strings.SplitN(serverVersion, ".", 2)[0] != "16" {
		return fmt.Errorf("PostgreSQL server version is %s, require major 16", serverVersion)
	}

	pre0009Root, cleanup, err := makePre0009Package(packageRoot, migratorPath)
	if err != nil {
		return err
	}
	defer cleanup()
	if err := runMigrator(pre0009Root); err != nil {
		return fmt.Errorf("run packaged migrator through 0008: %w", err)
	}
	if err := requireMigrationCount(ctx, pool, 8); err != nil {
		return err
	}

	if err := runMigrator(packageRoot); err != nil {
		return fmt.Errorf("run full packaged migrator: %w", err)
	}
	if err := requireMigrationCount(ctx, pool, 11); err != nil {
		return err
	}
	if err := verifyMigrationNames(ctx, pool); err != nil {
		return err
	}
	if err := verifyConstraints(ctx, pool); err != nil {
		return err
	}
	if err := verifyOwnershipWrites(ctx, pool); err != nil {
		return err
	}

	firstSignature, err := schemaSignature(ctx, pool)
	if err != nil {
		return err
	}
	if err := runMigrator(packageRoot); err != nil {
		return fmt.Errorf("rerun full packaged migrator: %w", err)
	}
	if err := requireMigrationCount(ctx, pool, 11); err != nil {
		return err
	}
	secondSignature, err := schemaSignature(ctx, pool)
	if err != nil {
		return err
	}
	if firstSignature != secondSignature {
		return errors.New("second packaged migrator run changed the schema signature")
	}

	fmt.Printf("postgres_server_version=%s\n", serverVersion)
	fmt.Printf("migrator_sha256=%s\n", migratorSHA)
	fmt.Printf("migrator_vcs_revision=%s\n", revision)
	fmt.Printf("migrator_vcs_modified=%t\n", modified)
	fmt.Println("pre0009_migration_count=8")
	fmt.Println("full_migration_count=11")
	fmt.Println("second_migration_count=11")
	fmt.Println("second_run_schema_unchanged=true")
	fmt.Println("ownership_mismatch_sqlstate=23503")
	fmt.Println("input_mode_invalid_sqlstate=23514")
	fmt.Println("session_delete_cascade=true")
	fmt.Println("canonical_migrator_runs=3")
	return nil
}

func readManifest(path string) (releaseManifest, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return releaseManifest{}, fmt.Errorf("read release manifest: %w", err)
	}
	var manifest releaseManifest
	if err := json.Unmarshal(raw, &manifest); err != nil {
		return releaseManifest{}, fmt.Errorf("decode release manifest: %w", err)
	}
	return manifest, nil
}

func verifyManifest(manifest releaseManifest, expectedSHA string) error {
	if manifest.GitCommit != expectedSHA || manifest.GOOS != "linux" || manifest.GOARCH != "amd64" {
		return fmt.Errorf("manifest provenance is commit=%s target=%s/%s", manifest.GitCommit, manifest.GOOS, manifest.GOARCH)
	}
	if len(manifest.Binaries) != 5 {
		return fmt.Errorf("manifest binary count = %d, want 5", len(manifest.Binaries))
	}
	if len(manifest.Migrations) != 11 {
		return fmt.Errorf("manifest migration count = %d, want 11", len(manifest.Migrations))
	}
	for index, migration := range manifest.Migrations {
		wantPrefix := fmt.Sprintf("%04d_", index+1)
		if !strings.HasPrefix(migration.Filename, wantPrefix) {
			return fmt.Errorf("manifest migration %d is %s, want prefix %s", index+1, migration.Filename, wantPrefix)
		}
	}
	return nil
}

func inspectMigrator(path string, manifest releaseManifest, expectedSHA string) (string, string, bool, error) {
	info, err := buildinfo.ReadFile(path)
	if err != nil {
		return "", "", false, fmt.Errorf("read packaged migrator build info: %w", err)
	}
	settings := make(map[string]string, len(info.Settings))
	for _, setting := range info.Settings {
		settings[setting.Key] = setting.Value
	}
	if settings["GOOS"] != "linux" || settings["GOARCH"] != "amd64" {
		return "", "", false, fmt.Errorf("packaged migrator target is %s/%s", settings["GOOS"], settings["GOARCH"])
	}
	if settings["vcs.revision"] != expectedSHA || settings["vcs.modified"] != "false" {
		return "", "", false, fmt.Errorf("packaged migrator VCS is revision=%s modified=%s", settings["vcs.revision"], settings["vcs.modified"])
	}
	hash, err := fileSHA256(path)
	if err != nil {
		return "", "", false, err
	}
	for _, binary := range manifest.Binaries {
		if binary.Name == "migrator" {
			if binary.SHA256 != hash || binary.VCSRevision != expectedSHA || binary.VCSModified {
				return "", "", false, errors.New("packaged migrator does not match its manifest record")
			}
			return hash, settings["vcs.revision"], false, nil
		}
	}
	return "", "", false, errors.New("migrator is absent from release manifest")
}

func makePre0009Package(packageRoot, migratorPath string) (string, func(), error) {
	root, err := os.MkdirTemp("", "kundi-pre0009-")
	if err != nil {
		return "", func() {}, fmt.Errorf("create pre-0009 package: %w", err)
	}
	cleanup := func() { _ = os.RemoveAll(root) }
	if err := os.MkdirAll(filepath.Join(root, "bin"), 0o755); err != nil {
		cleanup()
		return "", func() {}, err
	}
	if err := os.MkdirAll(filepath.Join(root, "migrations"), 0o755); err != nil {
		cleanup()
		return "", func() {}, err
	}
	if err := copyFile(migratorPath, filepath.Join(root, "bin", "migrator"), 0o755); err != nil {
		cleanup()
		return "", func() {}, err
	}
	entries, err := os.ReadDir(filepath.Join(packageRoot, "migrations"))
	if err != nil {
		cleanup()
		return "", func() {}, fmt.Errorf("list packaged migrations: %w", err)
	}
	copied := 0
	for _, entry := range entries {
		if entry.IsDir() || len(entry.Name()) < 5 || entry.Name()[:4] > "0008" {
			continue
		}
		if err := copyFile(
			filepath.Join(packageRoot, "migrations", entry.Name()),
			filepath.Join(root, "migrations", entry.Name()),
			0o644,
		); err != nil {
			cleanup()
			return "", func() {}, err
		}
		copied++
	}
	if copied != 8 {
		cleanup()
		return "", func() {}, fmt.Errorf("pre-0009 migration count = %d, want 8", copied)
	}
	return root, cleanup, nil
}

func copyFile(source, destination string, mode os.FileMode) error {
	input, err := os.Open(source)
	if err != nil {
		return fmt.Errorf("open %s: %w", source, err)
	}
	defer input.Close()
	output, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
	if err != nil {
		return fmt.Errorf("create %s: %w", destination, err)
	}
	if _, err := io.Copy(output, input); err != nil {
		_ = output.Close()
		return fmt.Errorf("copy %s: %w", source, err)
	}
	if err := output.Close(); err != nil {
		return fmt.Errorf("close %s: %w", destination, err)
	}
	return nil
}

func runMigrator(packageRoot string) error {
	command := exec.Command(filepath.Join(packageRoot, "bin", "migrator"))
	command.Dir = packageRoot
	command.Env = os.Environ()
	output, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func requireMigrationCount(ctx context.Context, pool *pgxpool.Pool, want int) error {
	var count int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM schema_migrations`).Scan(&count); err != nil {
		return fmt.Errorf("count schema migrations: %w", err)
	}
	if count != want {
		return fmt.Errorf("schema migration count = %d, want %d", count, want)
	}
	return nil
}

func verifyMigrationNames(ctx context.Context, pool *pgxpool.Pool) error {
	rows, err := pool.Query(ctx, `SELECT name FROM schema_migrations ORDER BY name`)
	if err != nil {
		return fmt.Errorf("list schema migrations: %w", err)
	}
	defer rows.Close()
	var names []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return err
		}
		names = append(names, name)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if len(names) != 11 {
		return fmt.Errorf("unique schema migration names = %d, want 11", len(names))
	}
	for index, name := range names {
		if !strings.HasPrefix(name, fmt.Sprintf("%04d_", index+1)) {
			return fmt.Errorf("schema migration %d is %s", index+1, name)
		}
	}
	return nil
}

func verifyConstraints(ctx context.Context, pool *pgxpool.Pool) error {
	wants := []struct {
		relation   string
		name       string
		kind       string
		definition string
	}{
		{"assistant_sessions", "uq_assistant_sessions_id_student_id", "u", "UNIQUE (id, student_id)"},
		{"assistant_messages", "fk_assistant_messages_session_owner", "f", "FOREIGN KEY (session_id, student_id) REFERENCES assistant_sessions(id, student_id) ON DELETE CASCADE"},
		{"assistant_messages", "chk_assistant_messages_content_length", "c", "CHECK"},
		{"assistant_messages", "chk_assistant_messages_input_mode", "c", "CHECK"},
	}
	for _, want := range wants {
		var kind string
		var validated bool
		var definition string
		err := pool.QueryRow(ctx, `
			SELECT contype::text, convalidated, pg_get_constraintdef(oid)
			FROM pg_constraint
			WHERE conname = $1 AND conrelid = $2::regclass
		`, want.name, want.relation).Scan(&kind, &validated, &definition)
		if err != nil {
			return fmt.Errorf("read constraint %s: %w", want.name, err)
		}
		if kind != want.kind || !validated || !strings.Contains(definition, want.definition) {
			return fmt.Errorf("constraint %s is kind=%s validated=%t definition=%q", want.name, kind, validated, definition)
		}
	}
	return nil
}

func verifyOwnershipWrites(ctx context.Context, pool *pgxpool.Pool) error {
	studentA := uuid.New()
	studentB := uuid.New()
	for _, studentID := range []uuid.UUID{studentA, studentB} {
		if _, err := pool.Exec(ctx, `INSERT INTO students(id, external_student_ref) VALUES ($1, $2)`, studentID, "release-check-"+studentID.String()); err != nil {
			return fmt.Errorf("insert synthetic student: %w", err)
		}
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM students WHERE id = ANY($1)`, []uuid.UUID{studentA, studentB})
	}()

	sessionID := uuid.New()
	if _, err := pool.Exec(ctx, `INSERT INTO assistant_sessions(id, student_id, mode) VALUES ($1, $2, 'tutor')`, sessionID, studentA); err != nil {
		return fmt.Errorf("insert synthetic session: %w", err)
	}
	for _, inputMode := range []string{"text", "voice"} {
		if _, err := pool.Exec(ctx, `
			INSERT INTO assistant_messages(id, session_id, student_id, role, text_content, content, input_mode)
			VALUES ($1, $2, $3, 'user', 'synthetic', 'synthetic', $4)
		`, uuid.New(), sessionID, studentA, inputMode); err != nil {
			return fmt.Errorf("insert %s input mode: %w", inputMode, err)
		}
	}
	_, invalidInputErr := pool.Exec(ctx, `
		INSERT INTO assistant_messages(id, session_id, student_id, role, text_content, content, input_mode)
		VALUES ($1, $2, $3, 'user', 'synthetic', 'synthetic', 'invalid')
	`, uuid.New(), sessionID, studentA)
	if err := requireSQLState(invalidInputErr, "23514"); err != nil {
		return fmt.Errorf("invalid input mode: %w", err)
	}
	_, mismatchedOwnershipErr := pool.Exec(ctx, `
		INSERT INTO assistant_messages(id, session_id, student_id, role, text_content, content, input_mode)
		VALUES ($1, $2, $3, 'user', 'synthetic', 'synthetic', 'text')
	`, uuid.New(), sessionID, studentB)
	if err := requireSQLState(mismatchedOwnershipErr, "23503"); err != nil {
		return fmt.Errorf("mismatched ownership: %w", err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM assistant_sessions WHERE id = $1 AND student_id = $2`, sessionID, studentA); err != nil {
		return fmt.Errorf("delete synthetic session: %w", err)
	}
	var remaining int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM assistant_messages WHERE session_id = $1`, sessionID).Scan(&remaining); err != nil {
		return fmt.Errorf("count synthetic messages after cascade: %w", err)
	}
	if remaining != 0 {
		return fmt.Errorf("synthetic messages after session delete = %d", remaining)
	}
	return nil
}

func requireSQLState(err error, want string) error {
	var postgresErr *pgconn.PgError
	if !errors.As(err, &postgresErr) {
		return fmt.Errorf("error = %v, want SQLSTATE %s", err, want)
	}
	if postgresErr.Code != want {
		return fmt.Errorf("SQLSTATE = %s, want %s", postgresErr.Code, want)
	}
	return nil
}

func schemaSignature(ctx context.Context, pool *pgxpool.Pool) (string, error) {
	queries := []string{
		`SELECT 'migration|' || name || '|' || applied_at::text FROM schema_migrations ORDER BY name`,
		`SELECT 'column|' || table_name || '|' || ordinal_position::text || '|' || column_name || '|' || data_type || '|' || is_nullable || '|' || COALESCE(column_default, '') FROM information_schema.columns WHERE table_schema = current_schema() ORDER BY table_name, ordinal_position`,
		`SELECT 'constraint|' || c.conrelid::regclass::text || '|' || c.conname || '|' || c.contype::text || '|' || c.convalidated::text || '|' || pg_get_constraintdef(c.oid) FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE n.nspname = current_schema() ORDER BY r.relname, c.conname`,
		`SELECT 'index|' || tablename || '|' || indexname || '|' || indexdef FROM pg_indexes WHERE schemaname = current_schema() ORDER BY tablename, indexname`,
	}
	hash := sha256.New()
	for _, query := range queries {
		rows, err := pool.Query(ctx, query)
		if err != nil {
			return "", fmt.Errorf("query schema signature: %w", err)
		}
		for rows.Next() {
			var value string
			if err := rows.Scan(&value); err != nil {
				rows.Close()
				return "", err
			}
			_, _ = io.WriteString(hash, value)
			_, _ = io.WriteString(hash, "\n")
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return "", err
		}
		rows.Close()
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func fileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open %s: %w", path, err)
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", fmt.Errorf("hash %s: %w", path, err)
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}
