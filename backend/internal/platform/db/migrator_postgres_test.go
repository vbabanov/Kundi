package db

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestMigrationsFresh0001Through0011(t *testing.T) {
	pool := newMigrationTestPool(t)
	ctx := context.Background()

	if err := RunMigrations(ctx, pool, migrationsPath(t)); err != nil {
		t.Fatalf("run fresh migration chain: %v", err)
	}
	first := migrationRecords(t, pool)
	if len(first) != 11 {
		t.Fatalf("fresh migration record count = %d, want 11", len(first))
	}
	assertOwnershipConstraints(t, pool)

	if err := RunMigrations(ctx, pool, migrationsPath(t)); err != nil {
		t.Fatalf("rerun fresh migration chain: %v", err)
	}
	second := migrationRecords(t, pool)
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("second migration run changed records: first=%v second=%v", first, second)
	}
}

func TestMigrationsUpgrade0001Through0008To0011(t *testing.T) {
	pool := newMigrationTestPool(t)
	ctx := context.Background()

	if err := RunMigrations(ctx, pool, migrationSubset(t, 8)); err != nil {
		t.Fatalf("run migrations 0001-0008: %v", err)
	}
	if count := len(migrationRecords(t, pool)); count != 8 {
		t.Fatalf("pre-0009 migration record count = %d, want 8", count)
	}
	if err := RunMigrations(ctx, pool, migrationsPath(t)); err != nil {
		t.Fatalf("upgrade through 0011: %v", err)
	}
	if count := len(migrationRecords(t, pool)); count != 11 {
		t.Fatalf("upgraded migration record count = %d, want 11", count)
	}
	assertOwnershipConstraints(t, pool)
}

func TestMigration0011PreservesValidRows(t *testing.T) {
	pool := newMigrationTestPool(t)
	ctx := context.Background()

	if err := RunMigrations(ctx, pool, migrationSubset(t, 10)); err != nil {
		t.Fatalf("run migrations 0001-0010: %v", err)
	}
	studentID, sessionID, messageID := insertPre0011Message(t, pool, false)

	if err := RunMigrations(ctx, pool, migrationsPath(t)); err != nil {
		t.Fatalf("apply 0011 to valid rows: %v", err)
	}
	var count int
	if err := pool.QueryRow(ctx, `
		SELECT count(*)
		FROM assistant_messages
		WHERE id = $1 AND session_id = $2 AND student_id = $3
	`, messageID, sessionID, studentID).Scan(&count); err != nil {
		t.Fatalf("read preserved valid row: %v", err)
	}
	if count != 1 {
		t.Fatalf("preserved valid row count = %d, want 1", count)
	}
	assertOwnershipConstraints(t, pool)
}

func TestMigration0011RejectsMismatchedOwnership(t *testing.T) {
	pool := newMigrationTestPool(t)
	ctx := context.Background()

	if err := RunMigrations(ctx, pool, migrationSubset(t, 10)); err != nil {
		t.Fatalf("run migrations 0001-0010: %v", err)
	}
	_, _, messageID := insertPre0011Message(t, pool, true)
	contentExistedBefore, contentValidatedBefore := contentConstraintState(t, pool)

	err := RunMigrations(ctx, pool, migrationsPath(t))
	var postgresErr *pgconn.PgError
	if !errors.As(err, &postgresErr) || postgresErr.Code != "23503" {
		t.Fatalf("0011 mismatch error = %v, want SQLSTATE 23503", err)
	}
	if count := len(migrationRecords(t, pool)); count != 10 {
		t.Fatalf("migration record count after failed 0011 = %d, want 10", count)
	}

	var rowCount int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM assistant_messages WHERE id = $1`, messageID).Scan(&rowCount); err != nil {
		t.Fatalf("read mismatched row after failed 0011: %v", err)
	}
	if rowCount != 1 {
		t.Fatalf("mismatched row count after failed 0011 = %d, want 1", rowCount)
	}

	contentExistsAfter, contentValidatedAfter := contentConstraintState(t, pool)
	if contentExistsAfter != contentExistedBefore || contentValidatedAfter != contentValidatedBefore {
		t.Fatalf(
			"failed 0011 changed content constraint state: before=(%v,%v) after=(%v,%v)",
			contentExistedBefore, contentValidatedBefore, contentExistsAfter, contentValidatedAfter,
		)
	}

	var newConstraintCount int
	if err := pool.QueryRow(ctx, `
		SELECT count(*)
		FROM pg_constraint
		WHERE conrelid IN ('assistant_sessions'::regclass, 'assistant_messages'::regclass)
		  AND conname IN ('uq_assistant_sessions_id_student_id', 'fk_assistant_messages_session_owner')
	`).Scan(&newConstraintCount); err != nil {
		t.Fatalf("read ownership constraints after rollback: %v", err)
	}
	if newConstraintCount != 0 {
		t.Fatalf("ownership constraints after failed 0011 = %d, want 0", newConstraintCount)
	}
}

func TestMigration0011RejectsInvalidExistingContent(t *testing.T) {
	pool := newMigrationTestPool(t)
	ctx := context.Background()

	if err := RunMigrations(ctx, pool, migrationSubset(t, 8)); err != nil {
		t.Fatalf("run migrations 0001-0008: %v", err)
	}
	studentID := uuid.New()
	sessionID := uuid.New()
	messageID := uuid.New()
	if _, err := pool.Exec(ctx, `INSERT INTO students(id, external_student_ref) VALUES ($1, $2)`, studentID, "invalid-content-"+studentID.String()); err != nil {
		t.Fatalf("insert student: %v", err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO assistant_sessions(id, student_id, mode) VALUES ($1, $2, 'tutor')`, sessionID, studentID); err != nil {
		t.Fatalf("insert session: %v", err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO assistant_messages(id, session_id, student_id, role, text_content)
		VALUES ($1, $2, $3, 'user', '')
	`, messageID, sessionID, studentID); err != nil {
		t.Fatalf("insert pre-0009 empty message: %v", err)
	}
	if err := RunMigrations(ctx, pool, migrationSubset(t, 10)); err != nil {
		t.Fatalf("upgrade invalid-content schema through 0010: %v", err)
	}
	contentExistedBefore, contentValidatedBefore := contentConstraintState(t, pool)

	err := RunMigrations(ctx, pool, migrationsPath(t))
	var postgresErr *pgconn.PgError
	if !errors.As(err, &postgresErr) || postgresErr.Code != "23514" {
		t.Fatalf("0011 invalid content error = %v, want SQLSTATE 23514", err)
	}
	if count := len(migrationRecords(t, pool)); count != 10 {
		t.Fatalf("migration record count after invalid-content 0011 = %d, want 10", count)
	}
	var content string
	if err := pool.QueryRow(ctx, `SELECT content FROM assistant_messages WHERE id = $1`, messageID).Scan(&content); err != nil {
		t.Fatalf("read invalid row after failed 0011: %v", err)
	}
	if content != "" {
		t.Fatalf("invalid content was modified to %q", content)
	}
	contentExistsAfter, contentValidatedAfter := contentConstraintState(t, pool)
	if contentExistsAfter != contentExistedBefore || contentValidatedAfter != contentValidatedBefore {
		t.Fatalf(
			"failed content validation changed constraint state: before=(%v,%v) after=(%v,%v)",
			contentExistedBefore, contentValidatedBefore, contentExistsAfter, contentValidatedAfter,
		)
	}
}

func TestMigrationsCrossSchemaConstraintRepair(t *testing.T) {
	dsn := migrationTestDSN(t)
	ctx := context.Background()
	publicPool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect public test schema: %v", err)
	}
	defer publicPool.Close()
	if err := RunMigrations(ctx, publicPool, migrationsPath(t)); err != nil {
		t.Fatalf("migrate public schema: %v", err)
	}

	targetPool := newMigrationTestPool(t)
	if err := RunMigrations(ctx, targetPool, migrationsPath(t)); err != nil {
		t.Fatalf("migrate second schema after public: %v", err)
	}
	if count := len(migrationRecords(t, targetPool)); count != 11 {
		t.Fatalf("second-schema migration record count = %d, want 11", count)
	}
	assertOwnershipConstraints(t, targetPool)
}

type migrationRecord struct {
	Name      string
	AppliedAt time.Time
}

func migrationRecords(t *testing.T, pool *pgxpool.Pool) []migrationRecord {
	t.Helper()
	rows, err := pool.Query(context.Background(), `SELECT name, applied_at FROM schema_migrations ORDER BY name`)
	if err != nil {
		t.Fatalf("list migration records: %v", err)
	}
	defer rows.Close()

	var records []migrationRecord
	for rows.Next() {
		var record migrationRecord
		if err := rows.Scan(&record.Name, &record.AppliedAt); err != nil {
			t.Fatalf("scan migration record: %v", err)
		}
		records = append(records, record)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate migration records: %v", err)
	}
	return records
}

func contentConstraintState(t *testing.T, pool *pgxpool.Pool) (bool, bool) {
	t.Helper()
	var exists bool
	var validated bool
	if err := pool.QueryRow(context.Background(), `
		SELECT count(*) = 1, COALESCE(bool_and(convalidated), false)
		FROM pg_constraint
		WHERE conname = 'chk_assistant_messages_content_length'
		  AND conrelid = 'assistant_messages'::regclass
	`).Scan(&exists, &validated); err != nil {
		t.Fatalf("read content constraint state: %v", err)
	}
	return exists, validated
}

func assertOwnershipConstraints(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	checks := []struct {
		relation   string
		name       string
		kind       string
		validated  bool
		definition string
	}{
		{"assistant_sessions", "chk_assistant_sessions_grade_level", "c", true, "CHECK"},
		{"assistant_sessions", "chk_assistant_sessions_locale_length", "c", true, "CHECK"},
		{"assistant_sessions", "chk_assistant_sessions_title_length", "c", true, "CHECK"},
		{"assistant_messages", "chk_assistant_messages_content_length", "c", true, "CHECK"},
		{"assistant_sessions", "uq_assistant_sessions_id_student_id", "u", true, "UNIQUE (id, student_id)"},
		{"assistant_messages", "fk_assistant_messages_session_owner", "f", true, "FOREIGN KEY (session_id, student_id) REFERENCES assistant_sessions(id, student_id) ON DELETE CASCADE"},
	}
	for _, check := range checks {
		var kind string
		var validated bool
		var definition string
		err := pool.QueryRow(context.Background(), `
			SELECT contype::text, convalidated, pg_get_constraintdef(oid)
			FROM pg_constraint
			WHERE conname = $1 AND conrelid = $2::regclass
		`, check.name, check.relation).Scan(&kind, &validated, &definition)
		if err != nil {
			t.Fatalf("read constraint %s on %s: %v", check.name, check.relation, err)
		}
		if kind != check.kind || validated != check.validated || !strings.Contains(definition, check.definition) {
			t.Fatalf("constraint %s on %s: kind=%s validated=%v definition=%q", check.name, check.relation, kind, validated, definition)
		}
	}
}

func insertPre0011Message(t *testing.T, pool *pgxpool.Pool, mismatched bool) (uuid.UUID, uuid.UUID, uuid.UUID) {
	t.Helper()
	ctx := context.Background()
	studentA := uuid.New()
	studentB := uuid.New()
	for _, studentID := range []uuid.UUID{studentA, studentB} {
		if _, err := pool.Exec(ctx, `INSERT INTO students(id, external_student_ref) VALUES ($1, $2)`, studentID, "migration-owner-"+studentID.String()); err != nil {
			t.Fatalf("insert student: %v", err)
		}
	}
	sessionID := uuid.New()
	if _, err := pool.Exec(ctx, `
		INSERT INTO assistant_sessions(id, student_id, mode)
		VALUES ($1, $2, 'tutor')
	`, sessionID, studentA); err != nil {
		t.Fatalf("insert pre-0011 session: %v", err)
	}
	messageStudentID := studentA
	if mismatched {
		messageStudentID = studentB
	}
	messageID := uuid.New()
	if _, err := pool.Exec(ctx, `
		INSERT INTO assistant_messages(id, session_id, student_id, role, text_content, content)
		VALUES ($1, $2, $3, 'user', 'synthetic', 'synthetic')
	`, messageID, sessionID, messageStudentID); err != nil {
		t.Fatalf("insert pre-0011 message: %v", err)
	}
	return studentA, sessionID, messageID
}

func newMigrationTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := migrationTestDSN(t)
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect migration test database: %v", err)
	}
	schema := "migration_test_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	if _, err := admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		admin.Close()
		t.Fatalf("create disposable schema: %v", err)
	}

	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		admin.Close()
		t.Fatalf("parse migration test database URL: %v", err)
	}
	config.ConnConfig.RuntimeParams["search_path"] = schema + ",public"
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		_, _ = admin.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE")
		admin.Close()
		t.Fatalf("connect disposable schema: %v", err)
	}
	t.Cleanup(func() {
		pool.Close()
		if _, err := admin.Exec(context.Background(), "DROP SCHEMA "+schema+" CASCADE"); err != nil {
			t.Errorf("drop disposable schema: %v", err)
		}
		admin.Close()
	})
	return pool
}

func migrationTestDSN(t *testing.T) string {
	t.Helper()
	dsn := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set; skipping PostgreSQL migration-chain test")
	}
	return dsn
}

func migrationsPath(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve migration test source path")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", "migrations"))
}

func migrationSubset(t *testing.T, through int) string {
	t.Helper()
	destination := t.TempDir()
	entries, err := os.ReadDir(migrationsPath(t))
	if err != nil {
		t.Fatalf("list migrations: %v", err)
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sql") || len(entry.Name()) < 5 {
			continue
		}
		number, err := strconv.Atoi(entry.Name()[:4])
		if err != nil || number > through {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(migrationsPath(t), entry.Name()))
		if err != nil {
			t.Fatalf("read migration %s: %v", entry.Name(), err)
		}
		if err := os.WriteFile(filepath.Join(destination, entry.Name()), raw, 0o600); err != nil {
			t.Fatalf("copy migration %s: %v", entry.Name(), err)
		}
	}
	if count, err := os.ReadDir(destination); err != nil || len(count) != through {
		t.Fatalf("migration subset through %04d has %d files: %v", through, len(count), err)
	}
	return destination
}
