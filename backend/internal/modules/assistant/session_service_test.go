package assistant

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tutoring"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

func TestSessionInputModePolicyAndPersistence(t *testing.T) {
	studentID, sessionID := uuid.New(), uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 7)
	provider := &capturingSessionProvider{text: "Начни с первого шага."}
	enabled, voiceEnabled := true, true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{
		Enabled: &enabled, VoiceInputEnabled: &voiceEnabled, SessionRepository: repo,
	})

	textResult, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(), Text: "Объясни дроби",
	})
	if err != nil || textResult.UserMessage.InputMode != InputModeText {
		t.Fatalf("default text mode failed: mode=%q err=%v", textResult.UserMessage.InputMode, err)
	}

	voiceID := uuid.NewString()
	voiceCommand := SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: voiceID,
		Text: "Реши за меня: 2 + 2", InputMode: InputModeVoice,
	}
	voiceResult, err := service.SendSessionMessage(context.Background(), voiceCommand)
	if err != nil || voiceResult.UserMessage.InputMode != InputModeVoice || strings.Contains(voiceResult.AssistantMessage.Content, "42") {
		t.Fatalf("voice policy/persistence failed: result=%#v err=%v", voiceResult, err)
	}
	replayed, err := service.SendSessionMessage(context.Background(), voiceCommand)
	if err != nil || replayed.UserMessage.InputMode != InputModeVoice || replayed.UserMessage.ID != voiceResult.UserMessage.ID {
		t.Fatalf("voice replay did not preserve exchange: result=%#v err=%v", replayed, err)
	}
}

func TestVoiceInputRequiresFlagAndRejectsInvalidMode(t *testing.T) {
	studentID, sessionID := uuid.New(), uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 7)
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), &capturingSessionProvider{text: "Подсказка."}, nil, Options{
		Enabled: &enabled, SessionRepository: repo,
	})

	base := SendSessionMessageCommand{StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(), Text: "Объясни дроби"}
	base.InputMode = InputModeVoice
	if _, err := service.SendSessionMessage(context.Background(), base); !apperrors.Is(err, "assistant_voice_input_disabled") {
		t.Fatalf("voice without flag: %v", err)
	}
	base.ClientMessageID = uuid.NewString()
	base.InputMode = "audio"
	if _, err := service.SendSessionMessage(context.Background(), base); !apperrors.Is(err, "assistant_input_mode_invalid") {
		t.Fatalf("invalid input mode: %v", err)
	}
}

func TestAssistantSessionGradeRangeIsOneThroughEleven(t *testing.T) {
	enabled := true
	for _, grade := range []int{1, 11} {
		repo := newMemorySessionRepository(uuid.New(), uuid.New(), grade)
		service := NewServiceWithOptions(persona.NewService(), nil, nil, Options{Enabled: &enabled, SessionRepository: repo})
		if _, err := service.CreateSession(context.Background(), repo.owner.String()); err != nil {
			t.Fatalf("grade %d should be accepted: %v", grade, err)
		}
	}
	for _, grade := range []int{0, 12} {
		repo := newMemorySessionRepository(uuid.New(), uuid.New(), grade)
		service := NewServiceWithOptions(persona.NewService(), nil, nil, Options{Enabled: &enabled, SessionRepository: repo})
		if _, err := service.CreateSession(context.Background(), repo.owner.String()); err == nil {
			t.Fatalf("grade %d should be rejected", grade)
		}
	}
}

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
	if provider.callCount() != 1 || !strings.Contains(provider.prompt, "Authenticated grade: 3") {
		t.Fatalf("server grade was not used: calls=%d prompt=%q", provider.callCount(), provider.prompt)
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
	if first.Replayed || !second.Replayed {
		t.Fatal("replay marker is incorrect")
	}
	second.Replayed = false
	if !reflect.DeepEqual(second, first) || provider.callCount() != 1 {
		t.Fatalf("idempotency failed: equal=%v calls=%d\nfirst=%#v\nsecond=%#v", reflect.DeepEqual(second, first), provider.callCount(), first, second)
	}
	if first.Session == nil || first.Session.Title != command.Text {
		t.Fatalf("updated session snapshot was not returned: %#v", first.Session)
	}
}

func TestExplicitReadyAnswerWithoutAcademicMatchIsReplaced(t *testing.T) {
	studentID, sessionID := uuid.New(), uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 7)
	provider := &capturingSessionProvider{text: "Ответ: 42. Полное решение готово."}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{
		Enabled: &enabled, SessionRepository: repo,
		AcademicContext: staticAcademicContext{context: AcademicContext{Locale: "ru-KZ", GradeLevel: 7}},
	})
	result, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: uuid.NewString(), Text: "Реши за меня: 2 + 2",
	})
	if err != nil || strings.Contains(result.AssistantMessage.Content, "42") || !strings.Contains(result.AssistantMessage.Content, "первый шаг") {
		t.Fatalf("unmatched explicit answer was not replaced: result=%#v err=%v", result, err)
	}
}

func TestMalformedLegacyReplayDegradesWithoutCallingProvider(t *testing.T) {
	studentID, sessionID, clientID := uuid.New(), uuid.New(), uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 7)
	now := time.Now().UTC()
	repo.exchanges[clientID] = StoredExchange{
		User:      SessionMessage{ID: uuid.NewString(), SessionID: sessionID.String(), Role: "user", Content: "Старый вопрос", InputMode: "text", CreatedAt: now},
		Assistant: SessionMessage{ID: uuid.NewString(), SessionID: sessionID.String(), Role: "assistant", Content: "Сохранённый ответ", InputMode: "text", ResponseMode: "answer", TutoringPolicy: json.RawMessage(`[]`), CreatedAt: now},
		Session:   repo.session,
	}
	provider := &capturingSessionProvider{text: "must not be called"}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{Enabled: &enabled, SessionRepository: repo})
	result, err := service.SendSessionMessage(context.Background(), SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: clientID.String(), Text: "Старый вопрос",
	})
	if err != nil || result.AssistantMessage.Content != "Сохранённый ответ" || result.Emotion != "neutral" || result.AnimationCue != "standing" || provider.callCount() != 0 {
		t.Fatalf("legacy replay did not degrade safely: result=%#v calls=%d err=%v", result, provider.callCount(), err)
	}
}

func TestConcurrentDuplicatePersistsOneExchange(t *testing.T) {
	studentID, sessionID, clientID := uuid.New(), uuid.New(), uuid.New()
	repo := newMemorySessionRepository(studentID, sessionID, 7)
	provider := &capturingSessionProvider{text: "Подсказка.", delay: 20 * time.Millisecond}
	enabled := true
	service := NewServiceWithOptions(persona.NewService(), provider, nil, Options{Enabled: &enabled, SessionRepository: repo})
	command := SendSessionMessageCommand{StudentID: studentID.String(), SessionID: sessionID.String(), ClientMessageID: clientID.String(), Text: "Объясни дроби"}
	results := make(chan SessionMessageResult, 2)
	errs := make(chan error, 2)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			result, err := service.SendSessionMessage(context.Background(), command)
			results <- result
			errs <- err
		}()
	}
	wg.Wait()
	close(results)
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatalf("concurrent send: %v", err)
		}
	}
	var firstID string
	for result := range results {
		if firstID == "" {
			firstID = result.AssistantMessage.ID
		} else if result.AssistantMessage.ID != firstID {
			t.Fatalf("duplicate requests returned different exchanges: %s != %s", result.AssistantMessage.ID, firstID)
		}
	}
	repo.mu.Lock()
	exchangeCount := len(repo.exchanges)
	repo.mu.Unlock()
	if exchangeCount != 1 {
		t.Fatalf("duplicate request persisted %d exchanges", exchangeCount)
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
	if err != nil || provider.callCount() != 1 || result.AssistantMessage.Content != "Париж." {
		t.Fatalf("factual question was blocked: result=%#v calls=%d err=%v", result, provider.callCount(), err)
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
	if err == nil || provider.callCount() != 0 {
		t.Fatalf("cross-student access was not blocked: err=%v calls=%d", err, provider.callCount())
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
	if provider.callCount() != 0 || strings.Contains(result.AssistantMessage.Content, "123456") || repo.lastAssistant.SafetyCategory != "privacy_or_secrets" {
		t.Fatalf("unsafe input handling failed: calls=%d response=%q category=%q", provider.callCount(), result.AssistantMessage.Content, repo.lastAssistant.SafetyCategory)
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
	delay        time.Duration
	mu           sync.Mutex
}

func (p *capturingSessionProvider) Generate(_ context.Context, req llm.Request) (llm.Response, error) {
	p.mu.Lock()
	p.calls++
	p.prompt = req.Prompt
	p.mu.Unlock()
	if p.delay > 0 {
		time.Sleep(p.delay)
	}
	return llm.Response{Text: p.text, Provider: "alem", Model: "exact-model"}, nil
}

func (p *capturingSessionProvider) callCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.calls
}

type memorySessionRepository struct {
	mu            sync.Mutex
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
	r.mu.Lock()
	defer r.mu.Unlock()
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
	r.mu.Lock()
	defer r.mu.Unlock()
	if studentID != r.owner || sessionID.String() != r.session.ID {
		return nil, ErrSessionNotFound
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
	r.mu.Lock()
	defer r.mu.Unlock()
	if studentID != r.owner || sessionID.String() != r.session.ID {
		return StoredExchange{}, false, ErrSessionNotFound
	}
	exchange, ok := r.exchanges[clientID]
	exchange.Session = r.session
	return exchange, ok, nil
}
func (r *memorySessionRepository) SaveExchange(_ context.Context, studentID, sessionID, clientID uuid.UUID, text, inputMode string, assistant SessionMessage) (StoredExchange, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if existing, ok := r.exchanges[clientID]; ok {
		existing.Session = r.session
		return existing, nil
	}
	if studentID != r.owner || sessionID.String() != r.session.ID {
		return StoredExchange{}, ErrSessionNotFound
	}
	now := time.Now().UTC()
	user := SessionMessage{ID: uuid.NewString(), SessionID: sessionID.String(), Role: "user", Content: text, InputMode: inputMode, CreatedAt: now}
	assistant.ID, assistant.SessionID, assistant.Role, assistant.InputMode, assistant.CreatedAt = uuid.NewString(), sessionID.String(), "assistant", "text", now.Add(time.Millisecond)
	if r.session.Title == "" {
		r.session.Title = boundedTitle(text)
	}
	r.session.UpdatedAt = now
	r.session.LastMessageAt = now
	exchange := StoredExchange{User: user, Assistant: assistant, Session: r.session}
	r.exchanges[clientID] = exchange
	r.lastAssistant = assistant
	r.lastPolicy = append([]byte(nil), assistant.TutoringPolicy...)
	return exchange, nil
}
