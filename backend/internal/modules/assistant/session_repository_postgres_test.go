package assistant

import (
	"context"
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kundi/kundi/backend/internal/modules/persona"
)

func TestPostgresSessionReplaySnapshotAndConcurrentDuplicate(t *testing.T) {
	dsn := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set; skipping PostgreSQL assistant-session test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	defer pool.Close()

	studentID := uuid.New()
	if _, err := pool.Exec(ctx, `INSERT INTO students(id, external_student_ref) VALUES ($1, $2)`, studentID, "assistant-session-"+studentID.String()); err != nil {
		t.Fatalf("insert student: %v", err)
	}
	defer func() { _, _ = pool.Exec(context.Background(), `DELETE FROM students WHERE id = $1`, studentID) }()
	if _, err := pool.Exec(ctx, `INSERT INTO student_profiles(student_id, grade_level, class_label, locale) VALUES ($1, 7, '7A', 'ru-KZ')`, studentID); err != nil {
		t.Fatalf("insert profile: %v", err)
	}

	repository := NewPostgresSessionRepository(pool)
	session, err := repository.CreateSession(ctx, studentID, "ru-KZ", 7)
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	provider := &capturingSessionProvider{text: "Начни с общего знаменателя."}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{CanaryGate: AllowAllCanaryGate(),
		Enabled: &enabled, SessionRepository: repository,
		AcademicContext: staticAcademicContext{context: AcademicContext{Locale: "ru-KZ", GradeLevel: 7}},
	})
	clientID := uuid.New()
	command := SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: session.ID,
		ClientMessageID: clientID.String(), Text: "Объясни сложение дробей",
	}
	first, err := service.SendSessionMessage(ctx, command)
	if err != nil {
		t.Fatalf("first send: %v", err)
	}
	replayed, err := service.SendSessionMessage(ctx, command)
	if err != nil {
		t.Fatalf("replay send: %v", err)
	}
	if first.Replayed || !replayed.Replayed {
		t.Fatal("incorrect replay flag")
	}
	replayed.Replayed = false
	if provider.callCount() != 1 || !reflect.DeepEqual(first, replayed) {
		t.Fatalf("response replay mismatch: calls=%d equal=%v", provider.callCount(), reflect.DeepEqual(first, replayed))
	}
	if first.Session == nil || first.Session.Title != command.Text {
		t.Fatalf("updated session snapshot missing: %#v", first.Session)
	}
	if first.HelpLevel != "guided" || first.Emotion != "neutral" || first.AnimationCue != "standing" || len(first.Suggestions) != 3 {
		t.Fatalf("response metadata was not restored: %#v", first)
	}
	stored, found, err := repository.FindExchange(ctx, studentID, uuid.MustParse(session.ID), clientID)
	if err != nil || !found || stored.Assistant.Provider != "alem" || stored.Assistant.Model != "exact-model" || stored.Assistant.ResponseMode != "explanation" || len(stored.Assistant.TutoringPolicy) == 0 {
		t.Fatalf("stored exchange metadata incomplete: found=%v exchange=%#v err=%v", found, stored, err)
	}

	secondSession, err := repository.CreateSession(ctx, studentID, "ru-KZ", 7)
	if err != nil {
		t.Fatalf("create second session: %v", err)
	}
	duplicateID := uuid.New()
	policy, _ := json.Marshal(sessionResponseMetadata{
		SchemaVersion: sessionResponseMetadataVersion,
		HelpLevel:     "guided", Emotion: "neutral", AnimationCue: "standing",
		Suggestions: []string{"Объясни тему"},
	})
	assistantMessage := SessionMessage{Content: "Подсказка", Provider: "test", Model: "test-model", ResponseMode: "explanation", TutoringPolicy: policy}
	results := make(chan StoredExchange, 2)
	errs := make(chan error, 2)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			exchange, saveErr := repository.SaveExchange(ctx, studentID, uuid.MustParse(secondSession.ID), duplicateID, "Второй вопрос", InputModeText, assistantMessage)
			results <- exchange
			errs <- saveErr
		}()
	}
	wg.Wait()
	close(results)
	close(errs)
	for saveErr := range errs {
		if saveErr != nil {
			t.Fatalf("concurrent duplicate save: %v", saveErr)
		}
	}
	var assistantID string
	for exchange := range results {
		if assistantID == "" {
			assistantID = exchange.Assistant.ID
		} else if exchange.Assistant.ID != assistantID {
			t.Fatalf("concurrent duplicate created different exchanges")
		}
	}
	var messageCount int
	if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM assistant_messages WHERE session_id = $1 AND client_message_id = $2`, secondSession.ID, duplicateID).Scan(&messageCount); err != nil || messageCount != 2 {
		t.Fatalf("duplicate message pair count=%d err=%v", messageCount, err)
	}
	sessions, err := repository.ListSessions(ctx, studentID, 10, nil)
	if err != nil || len(sessions) != 2 || sessions[0].ID != secondSession.ID || sessions[0].Title != "Второй вопрос" {
		t.Fatalf("session title/order mismatch: sessions=%#v err=%v", sessions, err)
	}
}
