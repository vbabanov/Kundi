package assistant

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tutoring"
	"github.com/kundi/kundi/backend/internal/modules/persona"
)

func TestSessionMessageUsesServerGradeAndGuardsReadyAnswerIdempotently(t *testing.T) {
	studentID := uuid.New()
	sessionID := uuid.New()
	clientID := uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 3)
	provider := &capturingSessionProvider{text: "Ответ: 42. Полное решение готово."}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{
		Enabled: &enabled, SessionRepository: repo,
		AcademicContext: staticAcademicContext{context: AcademicContext{
			Locale: "ru-KZ", GradeLevel: 3,
			UnfinishedHomework: []ContextHomework{{Subject: "Математика", Description: "Решить задачу 42 про дроби"}},
		}},
	})

	command := SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(),
		ClientMessageID: clientID.String(), Text: "Дай готовое полное решение этого домашнего задания...",
	}
	first, err := service.SendSessionMessage(context.Background(), command)
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if strings.Contains(first.AssistantMessage.Content, "42") || !strings.Contains(first.AssistantMessage.Content, "первый шаг") || strings.TrimSpace(first.FollowUpQuestion) == "" {
		t.Fatalf("ready answer was persisted: %q", first.AssistantMessage.Content)
	}
	if provider.calls != 1 || !strings.Contains(provider.prompt, "Authenticated grade: 3") {
		t.Fatalf("server grade was not used: calls=%d prompt=%q", provider.calls, provider.prompt)
	}
	if strings.Contains(string(repo.lastPolicy), "system") || strings.Contains(repo.lastAssistant.Content, provider.text) {
		t.Fatalf("unsafe intermediate or system prompt was persisted")
	}
	var policy map[string]any
	if err := json.Unmarshal(repo.lastPolicy, &policy); err != nil || policy["intent"] != string(tutoring.IntentRequestReadyAnswer) || policy["ready_answer_risk"] != true {
		t.Fatalf("ready-answer policy metadata was not persisted: policy=%v err=%v", policy, err)
	}

	second, err := service.SendSessionMessage(context.Background(), command)
	if err != nil {
		t.Fatalf("idempotent send: %v", err)
	}
	if second.AssistantMessage.ID != first.AssistantMessage.ID || provider.calls != 1 {
		t.Fatalf("idempotency failed: first=%s second=%s calls=%d", first.AssistantMessage.ID, second.AssistantMessage.ID, provider.calls)
	}
}

func TestFactualQuestionIsNotMisclassifiedAsHomework(t *testing.T) {
	studentID := uuid.New()
	sessionID := uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 7)
	provider := &capturingSessionProvider{text: "Париж."}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{Enabled: &enabled, SessionRepository: repo})

	result, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(), Text: "Столица Франции?",
	})
	if err != nil || provider.calls != 1 || result.AssistantMessage.Content != "Париж." {
		t.Fatalf("factual question was blocked: result=%#v calls=%d err=%v", result, provider.calls, err)
	}
	var policy map[string]any
	if err := json.Unmarshal(repo.lastPolicy, &policy); err != nil || policy["ready_answer_risk"] != false {
		t.Fatalf("factual question received homework risk: policy=%v err=%v", policy, err)
	}
}

func TestSessionIsolationBlocksOtherStudent(t *testing.T) {
	owner := uuid.New()
	sessionID := uuid.New()
	repo := newMemorySessionRepository(owner, sessionID, 7)
	provider := &capturingSessionProvider{text: "Париж."}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{Enabled: &enabled, SessionRepository: repo})

	_, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: uuid.NewString(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(), Text: "Столица Франции?",
	})
	if err == nil || provider.calls != 0 {
		t.Fatalf("cross-student access was not blocked: err=%v calls=%d", err, provider.calls)
	}
}

func TestUnsafeInputNeverReachesProviderAndOnlySafeResponseIsStored(t *testing.T) {
	studentID := uuid.New()
	sessionID := uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 7)
	provider := &capturingSessionProvider{text: "must not be called"}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{Enabled: &enabled, SessionRepository: repo})

	result, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(), Text: "мой пароль это 123456",
	})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if provider.calls != 0 || strings.Contains(result.AssistantMessage.Content, "123456") || repo.lastAssistant.SafetyCategory != "privacy_or_secrets" {
		t.Fatalf("unsafe input handling failed: calls=%d response=%q category=%q", provider.calls, result.AssistantMessage.Content, repo.lastAssistant.SafetyCategory)
	}
}

func TestAcademicContextFailureDegradesWithoutChangingServerGrade(t *testing.T) {
	studentID := uuid.New()
	sessionID := uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 9)
	provider := &capturingSessionProvider{text: "Париж."}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{
		Enabled: &enabled, SessionRepository: repo,
		AcademicContext: staticAcademicContext{err: errors.New("database unavailable")},
	})

	result, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(), Text: "Столица Франции?",
	})
	if err != nil || result.AssistantMessage.Content != "Париж." || !strings.Contains(provider.prompt, "Authenticated grade: 9") {
		t.Fatalf("graceful context degradation failed: result=%#v err=%v prompt=%q", result, err, provider.prompt)
	}
}

type staticAcademicContext struct {
	context AcademicContext
	err     error
}

func (s staticAcademicContext) Build(context.Context, uuid.UUID) (AcademicContext, error) {
	return s.context, s.err
}

type capturingSessionProvider struct {
	text, prompt string
	calls        int
}

func (p *capturingSessionProvider) Generate(_ context.Context, req llm.Request) (llm.Response, error) {
	p.calls++
	p.prompt = req.Prompt
	return llm.Response{Text: p.text, Provider: "alem", Model: "exact-model"}, nil
}

type memorySessionRepository struct {
	owner         uuid.UUID
	session       AssistantSession
	exchanges     map[uuid.UUID]StoredExchange
	lastAssistant SessionMessage
	lastPolicy    []byte
}

func newMemorySessionRepository(owner, sessionID uuid.UUID, grade int) *memorySessionRepository {
	now := time.Now().UTC()
	return &memorySessionRepository{owner: owner, session: AssistantSession{ID: sessionID.String(), Locale: "ru-KZ", GradeLevel: grade, CreatedAt: now, UpdatedAt: now, LastMessageAt: now}, exchanges: make(map[uuid.UUID]StoredExchange)}
}

func (r *memorySessionRepository) StudentProfile(context.Context, uuid.UUID) (StudentAssistantProfile, error) {
	return StudentAssistantProfile{Locale: r.session.Locale, GradeLevel: r.session.GradeLevel}, nil
}
func (r *memorySessionRepository) CreateSession(context.Context, uuid.UUID, string, int) (AssistantSession, error) {
	return r.session, nil
}
func (r *memorySessionRepository) GetSession(_ context.Context, studentID, sessionID uuid.UUID) (AssistantSession, error) {
	if studentID != r.owner || sessionID.String() != r.session.ID {
		return AssistantSession{}, ErrSessionNotFound
	}
	return r.session, nil
}
func (r *memorySessionRepository) ListSessions(_ context.Context, studentID uuid.UUID, _ int, _ *PageCursor) ([]AssistantSession, error) {
	if studentID != r.owner {
		return nil, nil
	}
	return []AssistantSession{r.session}, nil
}
func (r *memorySessionRepository) ListMessages(_ context.Context, studentID, sessionID uuid.UUID, _ int, _ *PageCursor) ([]SessionMessage, error) {
	if _, err := r.GetSession(context.Background(), studentID, sessionID); err != nil {
		return nil, err
	}
	out := make([]SessionMessage, 0, len(r.exchanges)*2)
	for _, exchange := range r.exchanges {
		out = append(out, exchange.Assistant, exchange.User)
	}
	return out, nil
}
func (r *memorySessionRepository) DeleteSession(_ context.Context, studentID, sessionID uuid.UUID) error {
	if _, err := r.GetSession(context.Background(), studentID, sessionID); err != nil {
		return err
	}
	return nil
}
func (r *memorySessionRepository) FindExchange(_ context.Context, studentID, sessionID, clientID uuid.UUID) (StoredExchange, bool, error) {
	if _, err := r.GetSession(context.Background(), studentID, sessionID); err != nil {
		return StoredExchange{}, false, err
	}
	exchange, ok := r.exchanges[clientID]
	return exchange, ok, nil
}
func (r *memorySessionRepository) SaveExchange(_ context.Context, studentID, sessionID, clientID uuid.UUID, text string, assistant SessionMessage) (StoredExchange, error) {
	if existing, ok := r.exchanges[clientID]; ok {
		return existing, nil
	}
	if _, err := r.GetSession(context.Background(), studentID, sessionID); err != nil {
		return StoredExchange{}, err
	}
	now := time.Now().UTC()
	user := SessionMessage{ID: uuid.NewString(), SessionID: sessionID.String(), Role: "user", Content: text, InputMode: "text", CreatedAt: now}
	assistant.ID, assistant.SessionID, assistant.Role, assistant.InputMode, assistant.CreatedAt = uuid.NewString(), sessionID.String(), "assistant", "text", now.Add(time.Millisecond)
	exchange := StoredExchange{User: user, Assistant: assistant}
	r.exchanges[clientID] = exchange
	r.lastAssistant = assistant
	r.lastPolicy = append([]byte(nil), assistant.TutoringPolicy...)
	return exchange, nil
}
