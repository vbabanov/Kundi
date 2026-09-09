package gamification

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kundi/kundi/backend/internal/platform/db"
)

type testClock struct{ now time.Time }

func (c *testClock) Now() time.Time { return c.now }

func TestPostgresGamificationReconcileIsIdempotentOwnedAndFiltered(t *testing.T) {
	pool := gamificationTestPool(t)
	ctx := context.Background()
	studentA, studentB := insertStudents(t, pool)
	studentTimezone := insertStudent(t, pool)
	clock := &testClock{now: time.Date(2026, 9, 1, 19, 30, 0, 0, time.UTC)} // 00:30 in Asia/Almaty.
	service, err := NewServiceWithClock(pool, DefaultTimezone, clock)
	if err != nil {
		t.Fatal(err)
	}

	first, err := service.RecordActivity(ctx, studentA)
	if err != nil {
		t.Fatal(err)
	}
	second, err := service.RecordActivity(ctx, studentA)
	if err != nil {
		t.Fatal(err)
	}
	if first.CurrentStreak != 1 || second.Points != first.Points || second.AchievementsUnlocked != first.AchievementsUnlocked {
		t.Fatalf("same-day activity was not idempotent: first=%#v second=%#v", first, second)
	}
	var dayCount int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM gamification_activity_days WHERE student_id=$1`, studentA).Scan(&dayCount); err != nil || dayCount != 1 {
		t.Fatalf("activity days=%d err=%v", dayCount, err)
	}

	clock.now = clock.now.Add(24 * time.Hour)
	if _, err := service.RecordActivity(ctx, studentA); err != nil {
		t.Fatal(err)
	}
	clock.now = clock.now.Add(24 * time.Hour)
	third, err := service.RecordActivity(ctx, studentA)
	if err != nil || third.CurrentStreak != 3 || third.LongestStreak != 3 {
		t.Fatalf("three-day streak=%#v err=%v", third, err)
	}
	clock.now = clock.now.Add(48 * time.Hour)
	gapped, err := service.RecordActivity(ctx, studentA)
	if err != nil || gapped.CurrentStreak != 1 || gapped.LongestStreak != 3 {
		t.Fatalf("gap streak=%#v err=%v", gapped, err)
	}

	clock.now = time.Date(2026, 9, 10, 18, 59, 0, 0, time.UTC)
	if _, err := service.RecordActivity(ctx, studentTimezone); err != nil {
		t.Fatal(err)
	}
	clock.now = time.Date(2026, 9, 10, 19, 1, 0, 0, time.UTC)
	timezoneBoundary, err := service.RecordActivity(ctx, studentTimezone)
	if err != nil || timezoneBoundary.CurrentStreak != 2 || timezoneBoundary.LongestStreak != 2 {
		t.Fatalf("timezone boundary streak=%#v err=%v", timezoneBoundary, err)
	}

	insertCanonicalGrades(t, pool, studentA, 0, 1)
	oneGrade, err := service.GetProfile(ctx, studentA)
	if err != nil {
		t.Fatal(err)
	}
	assertProgress(t, oneGrade, "grade_five_1", 1, true)
	assertProgress(t, oneGrade, "grade_five_5", 1, false)
	if _, err := pool.Exec(ctx, `UPDATE academic_results SET updated_at=NOW() WHERE student_id=$1`, studentA); err != nil {
		t.Fatal(err)
	}
	afterDuplicateRefresh, err := service.GetProfile(ctx, studentA)
	if err != nil {
		t.Fatal(err)
	}
	assertProgress(t, afterDuplicateRefresh, "grade_five_1", 1, true)

	insertCanonicalGrades(t, pool, studentA, 1, 4)
	fiveGrades, err := service.GetProfile(ctx, studentA)
	if err != nil {
		t.Fatal(err)
	}
	assertProgress(t, fiveGrades, "grade_five_5", 5, true)
	assertProgress(t, fiveGrades, "grade_five_10", 5, false)

	insertCanonicalGrades(t, pool, studentA, 5, 5)
	insertAssistantEvidence(t, pool, studentA)
	before, err := service.GetProfile(ctx, studentA)
	if err != nil {
		t.Fatal(err)
	}
	after, err := service.GetProfile(ctx, studentA)
	if err != nil {
		t.Fatal(err)
	}
	if before.Points != after.Points || before.AchievementsUnlocked != after.AchievementsUnlocked {
		t.Fatalf("reconcile replay changed totals: before=%#v after=%#v", before, after)
	}
	assertProgress(t, after, "grade_five_1", 10, true)
	assertProgress(t, after, "grade_five_5", 10, true)
	assertProgress(t, after, "grade_five_10", 10, true)
	assertProgress(t, after, "learning_question_1", 10, true)
	assertProgress(t, after, "learning_question_10", 10, true)
	assertProgress(t, after, "learning_question_50", 10, false)
	assertProgress(t, after, "attempt_check_1", 20, true)
	assertProgress(t, after, "attempt_check_5", 20, true)
	assertProgress(t, after, "attempt_check_20", 20, true)
	if after.Points < 0 {
		t.Fatalf("negative points: %d", after.Points)
	}

	if _, err := pool.Exec(ctx, `DELETE FROM academic_results WHERE student_id=$1`, studentA); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM assistant_messages WHERE student_id=$1`, studentA); err != nil {
		t.Fatal(err)
	}
	emptySnapshot, err := service.GetProfile(ctx, studentA)
	if err != nil {
		t.Fatal(err)
	}
	if emptySnapshot.Points != after.Points || emptySnapshot.AchievementsUnlocked != after.AchievementsUnlocked {
		t.Fatalf("empty sources erased durable progress: before=%#v after=%#v", after, emptySnapshot)
	}

	other, err := service.GetProfile(ctx, studentB)
	if err != nil {
		t.Fatal(err)
	}
	if other.Points != 0 || other.AchievementsUnlocked != 0 {
		t.Fatalf("ownership leak: %#v", other)
	}

	codes := make([]string, 0, len(after.PendingUnlocks))
	for _, item := range after.PendingUnlocks {
		codes = append(codes, item.Code)
	}
	if err := service.Acknowledge(ctx, studentA, codes); err != nil {
		t.Fatal(err)
	}
	acknowledged, err := service.GetProfile(ctx, studentA)
	if err != nil || len(acknowledged.PendingUnlocks) != 0 {
		t.Fatalf("ack pending=%d err=%v", len(acknowledged.PendingUnlocks), err)
	}
}

func insertCanonicalGrades(t *testing.T, pool *pgxpool.Pool, studentID uuid.UUID, startIndex, count int) {
	t.Helper()
	ctx := context.Background()
	for index := 0; index < count; index++ {
		_, err := pool.Exec(ctx, `INSERT INTO academic_results(student_id, provider, result_kind, subject_name, provider_mark_id, value_text, value_numeric, recorded_on) VALUES($1,'kundelik','regular','synthetic',$2,'5',5,$3)`, studentID, uuid.NewString(), time.Date(2026, 8, startIndex+index+1, 0, 0, 0, 0, time.UTC))
		if err != nil {
			t.Fatal(err)
		}
	}
	_, err := pool.Exec(ctx, `INSERT INTO academic_results(student_id, provider, result_kind, subject_name, provider_mark_id, value_text, value_numeric, recorded_on) VALUES($1,'kundelik','sor','synthetic',$2,'5',5,'2026-08-20'),($1,'kundelik','regular','synthetic',$3,'4',4,'2026-08-21')`, studentID, uuid.NewString(), uuid.NewString())
	if err != nil {
		t.Fatal(err)
	}
}

func insertAssistantEvidence(t *testing.T, pool *pgxpool.Pool, studentID uuid.UUID) {
	t.Helper()
	ctx := context.Background()
	sessionID := uuid.New()
	if _, err := pool.Exec(ctx, `INSERT INTO assistant_sessions(id, student_id, mode, locale, grade_level) VALUES($1,$2,'tutor','ru-KZ',7)`, sessionID, studentID); err != nil {
		t.Fatal(err)
	}
	validPolicy, _ := json.Marshal(map[string]any{"schema_version": 1, "ready_answer_risk": false})
	readyPolicy, _ := json.Marshal(map[string]any{"schema_version": 1, "ready_answer_risk": true})
	insert := func(mode, provider, safety string, policy []byte, count int) {
		for index := 0; index < count; index++ {
			_, err := pool.Exec(ctx, `INSERT INTO assistant_messages(session_id, student_id, role, text_content, content, input_mode, provider, response_mode, tutoring_policy_result, safety_category, created_at) VALUES($1,$2,'assistant','synthetic','synthetic','text',$3,$4,$5,NULLIF($6,''),$7)`, sessionID, studentID, provider, mode, policy, safety, time.Date(2026, 8, (index%25)+1, 10, 0, 0, 0, time.UTC))
			if err != nil {
				t.Fatal(err)
			}
		}
	}
	insert("explanation", "alem", "", validPolicy, 10)
	insert("attempt_check", "alem", "", validPolicy, 20)
	insert("hint", "alem", "", readyPolicy, 1)
	insert("explanation", "alem", "self_harm", validPolicy, 1)
	insert("explanation", "", "", validPolicy, 1)
}

func assertProgress(t *testing.T, profile Profile, code string, current int, unlocked bool) {
	t.Helper()
	for _, item := range profile.Achievements {
		if item.Code == code {
			if item.Current != current || item.Unlocked != unlocked {
				t.Fatalf("%s=%d/%v want %d/%v", code, item.Current, item.Unlocked, current, unlocked)
			}
			return
		}
	}
	t.Fatalf("missing achievement %s", code)
}

func gamificationTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	schema := "gamification_test_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	if _, err := admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		admin.Close()
		t.Fatal(err)
	}
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	config.ConnConfig.RuntimeParams["search_path"] = schema + ",public"
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	_, file, _, _ := runtime.Caller(0)
	migrations := filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", "migrations"))
	if err := db.RunMigrations(ctx, pool, migrations); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		pool.Close()
		_, _ = admin.Exec(context.Background(), "DROP SCHEMA "+schema+" CASCADE")
		admin.Close()
	})
	return pool
}

func insertStudents(t *testing.T, pool *pgxpool.Pool) (uuid.UUID, uuid.UUID) {
	t.Helper()
	return insertStudent(t, pool), insertStudent(t, pool)
}

func insertStudent(t *testing.T, pool *pgxpool.Pool) uuid.UUID {
	t.Helper()
	id := uuid.New()
	if _, err := pool.Exec(context.Background(), `INSERT INTO students(id, external_student_ref) VALUES($1,$2)`, id, "gamification-"+id.String()); err != nil {
		t.Fatal(err)
	}
	return id
}
