package assistant

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestPostgresAcademicContextUsesCurrentLearningWindows(t *testing.T) {
	dsn := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set; skipping PostgreSQL academic-context test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	defer pool.Close()

	studentID := uuid.New()
	if _, err := pool.Exec(ctx, `INSERT INTO students(id, external_student_ref) VALUES ($1, $2)`, studentID, "assistant-context-"+studentID.String()); err != nil {
		t.Fatalf("insert student: %v", err)
	}
	defer func() { _, _ = pool.Exec(context.Background(), `DELETE FROM students WHERE id = $1`, studentID) }()
	if _, err := pool.Exec(ctx, `INSERT INTO student_profiles(student_id, grade_level, class_label, locale) VALUES ($1, 7, '7A', 'ru-KZ')`, studentID); err != nil {
		t.Fatalf("insert profile: %v", err)
	}

	insertHomework := func(name string, dueDays *int, updatedDays int) {
		t.Helper()
		lessonID := insertContextLesson(t, ctx, pool, studentID, name, "Математика")
		var due any
		if dueDays != nil {
			due = time.Now().UTC().AddDate(0, 0, *dueDays)
		}
		if _, err := pool.Exec(ctx, `
			INSERT INTO homeworks(student_id, lesson_id, source_homework_key, description, due_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, NOW() - ($6::integer * INTERVAL '1 day'))
		`, studentID, lessonID, "hw-"+name, name, due, updatedDays); err != nil {
			t.Fatalf("insert homework %s: %v", name, err)
		}
	}
	today, upcoming, overdue, old := 0, 3, -5, -40
	insertHomework("today", &today, 0)
	insertHomework("upcoming", &upcoming, 0)
	insertHomework("recent-overdue", &overdue, 0)
	insertHomework("old-overdue", &old, 0)
	insertHomework("recent-undated", nil, 2)
	insertHomework("old-undated", nil, 40)

	insertResult := func(topic, suffix string, recordedDays int) {
		t.Helper()
		lessonID := insertContextLesson(t, ctx, pool, studentID, "result-"+suffix, "Математика")
		if _, err := pool.Exec(ctx, `INSERT INTO lesson_topics(lesson_id, topic_index, title) VALUES ($1, 1, $2)`, lessonID, topic); err != nil {
			t.Fatalf("insert topic %s: %v", suffix, err)
		}
		if _, err := pool.Exec(ctx, `
			INSERT INTO academic_results(
				student_id, provider, lesson_id, result_kind, provider_subject_id, subject_name,
				provider_work_id, provider_mark_id, source_result_key, value_text, resolved_mood, recorded_on
			) VALUES ($1, 'kundelik', $2, 'regular', 'math', 'Математика', $3, $4, $5, '2', 'negative', CURRENT_DATE - $6::integer)
		`, studentID, lessonID, "work-"+suffix, "mark-"+suffix, "result-"+suffix, recordedDays); err != nil {
			t.Fatalf("insert result %s: %v", suffix, err)
		}
	}
	insertResult("Свежая слабая тема", "fresh-1", 2)
	insertResult("Свежая слабая тема", "fresh-2", 4)
	insertResult("Одиночный сигнал", "single", 3)
	insertResult("Старая тема", "old-1", 140)
	insertResult("Старая тема", "old-2", 150)

	provider := NewPostgresAcademicContextProvider(pool)
	got, err := provider.Build(ctx, studentID)
	if err != nil {
		t.Fatalf("build context: %v", err)
	}
	descriptions := make([]string, 0, len(got.UnfinishedHomework))
	for _, homework := range got.UnfinishedHomework {
		descriptions = append(descriptions, homework.Description)
	}
	wantOrder := []string{"today", "upcoming", "recent-overdue", "recent-undated"}
	if strings.Join(descriptions, ",") != strings.Join(wantOrder, ",") {
		t.Fatalf("unexpected homework window/order: got %#v want %#v", descriptions, wantOrder)
	}
	if len(got.WeakTopics) != 1 || got.WeakTopics[0] != "Свежая слабая тема" {
		t.Fatalf("unexpected current weak topics: %#v", got.WeakTopics)
	}
	if len(got.RecentResults) != 3 {
		t.Fatalf("old results leaked into current context: %#v", got.RecentResults)
	}
}

func insertContextLesson(t *testing.T, ctx context.Context, pool *pgxpool.Pool, studentID uuid.UUID, suffix, subject string) uuid.UUID {
	t.Helper()
	id := uuid.New()
	if _, err := pool.Exec(ctx, `
		INSERT INTO lessons(id, student_id, source_lesson_key, lesson_date, lesson_number, subject_name)
		VALUES ($1, $2, $3, CURRENT_DATE, 1, $4)
	`, id, studentID, fmt.Sprintf("assistant-context-%s-%s", suffix, id), subject); err != nil {
		t.Fatalf("insert lesson %s: %v", suffix, err)
	}
	return id
}
