package v1

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/app"
	assistantmodule "github.com/kundi/kundi/backend/internal/modules/assistant"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
)

func TestAssistantSessionEndpointsCRUD(t *testing.T) {
	studentID := uuid.New()
	sessionID := uuid.New()
	repository := &apiSessionRepository{owner: studentID, sessionID: sessionID}
	enabled := true
	service := assistantmodule.NewServiceWithOptions(persona.NewService(), apiLLM{}, nil, assistantmodule.Options{CanaryGate: assistantmodule.AllowAllCanaryGate(),
		Enabled: &enabled, SessionRepository: repository,
	})
	tokens := platformauth.NewAccessTokenService("test-secret", time.Hour)
	token, _, err := tokens.Issue(studentID, time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	router := NewRouter(&app.Bootstrap{Config: config.Config{App: config.AppConfig{Name: "test"}}, AccessTokens: tokens, AssistantService: service})

	assertStatus(t, router, token, http.MethodPost, "/v1/assistant/sessions", `{}`, http.StatusCreated)
	assertStatus(t, router, token, http.MethodGet, "/v1/assistant/sessions?limit=10", "", http.StatusOK)
	assertStatus(t, router, token, http.MethodGet, "/v1/assistant/sessions/"+sessionID.String()+"/messages", "", http.StatusOK)
	response := performRequest(router, token, http.MethodPost, "/v1/assistant/sessions/"+sessionID.String()+"/messages", `{"client_message_id":"`+uuid.NewString()+`","text":"Столица Франции?"}`)
	if response.Code != http.StatusOK {
		t.Fatalf("message send: got %d body=%s", response.Code, response.Body.String())
	}
	var payload struct {
		Data struct {
			Session assistantmodule.AssistantSession `json:"session"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil || payload.Data.Session.Title != "Столица Франции?" {
		t.Fatalf("updated session snapshot missing: session=%#v err=%v", payload.Data.Session, err)
	}
	assertStatus(t, router, token, http.MethodDelete, "/v1/assistant/sessions/"+sessionID.String(), "", http.StatusNoContent)
	if !repository.deleted || len(repository.messages) != 2 {
		t.Fatalf("CRUD was incomplete: deleted=%v messages=%d", repository.deleted, len(repository.messages))
	}
}

func TestAssistantEndpointsAreDisabledWithoutFlag(t *testing.T) {
	studentID := uuid.New()
	tokens := platformauth.NewAccessTokenService("test-secret", time.Hour)
	token, _, _ := tokens.Issue(studentID, time.Now().UTC())
	disabled := false
	service := assistantmodule.NewServiceWithOptions(persona.NewService(), apiLLM{}, nil, assistantmodule.Options{CanaryGate: assistantmodule.AllowAllCanaryGate(), Enabled: &disabled, SessionRepository: &apiSessionRepository{owner: studentID, sessionID: uuid.New()}})
	router := NewRouter(&app.Bootstrap{Config: config.Config{App: config.AppConfig{Name: "test"}}, AccessTokens: tokens, AssistantService: service})
	assertStatus(t, router, token, http.MethodGet, "/v1/assistant/sessions", "", http.StatusNotFound)
}

func TestAssistantSessionVoiceInputContract(t *testing.T) {
	studentID, sessionID := uuid.New(), uuid.New()
	tokens := platformauth.NewAccessTokenService("test-secret", time.Hour)
	token, _, _ := tokens.Issue(studentID, time.Now().UTC())
	enabled, voiceDisabled := true, false
	disabledRepo := &apiSessionRepository{owner: studentID, sessionID: sessionID}
	disabledService := assistantmodule.NewServiceWithOptions(persona.NewService(), apiLLM{}, nil, assistantmodule.Options{CanaryGate: assistantmodule.AllowAllCanaryGate(),
		Enabled: &enabled, VoiceInputEnabled: &voiceDisabled, SessionRepository: disabledRepo,
	})
	disabledRouter := NewRouter(&app.Bootstrap{Config: config.Config{App: config.AppConfig{Name: "test"}}, AccessTokens: tokens, AssistantService: disabledService})
	voiceID := uuid.NewString()
	voiceBody := `{"client_message_id":"` + voiceID + `","text":"Объясни дроби","input_mode":"voice"}`
	assertStatus(t, disabledRouter, token, http.MethodPost, "/v1/assistant/sessions/"+sessionID.String()+"/messages", voiceBody, http.StatusNotFound)
	assertStatus(t, disabledRouter, token, http.MethodPost, "/v1/assistant/sessions/"+sessionID.String()+"/messages", `{"client_message_id":"`+uuid.NewString()+`","text":"Объясни дроби","input_mode":"audio"}`, http.StatusBadRequest)
	if len(disabledRepo.messages) != 0 {
		t.Fatal("disabled or invalid voice request persisted messages")
	}

	voiceEnabled := true
	enabledRepo := &apiSessionRepository{owner: studentID, sessionID: sessionID}
	enabledService := assistantmodule.NewServiceWithOptions(persona.NewService(), apiLLM{}, nil, assistantmodule.Options{CanaryGate: assistantmodule.AllowAllCanaryGate(),
		Enabled: &enabled, VoiceInputEnabled: &voiceEnabled, SessionRepository: enabledRepo,
	})
	enabledRouter := NewRouter(&app.Bootstrap{Config: config.Config{App: config.AppConfig{Name: "test"}}, AccessTokens: tokens, AssistantService: enabledService})
	first := performRequest(enabledRouter, token, http.MethodPost, "/v1/assistant/sessions/"+sessionID.String()+"/messages", voiceBody)
	if first.Code != http.StatusOK {
		t.Fatalf("voice send: got %d body=%s", first.Code, first.Body.String())
	}
	var payload struct {
		Data struct {
			User assistantmodule.SessionMessage `json:"user_message"`
		} `json:"data"`
	}
	if err := json.Unmarshal(first.Body.Bytes(), &payload); err != nil || payload.Data.User.InputMode != assistantmodule.InputModeVoice {
		t.Fatalf("voice mode was not returned: user=%#v err=%v", payload.Data.User, err)
	}
	replay := performRequest(enabledRouter, token, http.MethodPost, "/v1/assistant/sessions/"+sessionID.String()+"/messages", voiceBody)
	var replayPayload struct {
		Data struct {
			User assistantmodule.SessionMessage `json:"user_message"`
		} `json:"data"`
	}
	if replay.Code != http.StatusOK || json.Unmarshal(replay.Body.Bytes(), &replayPayload) != nil || replayPayload.Data.User.ID != payload.Data.User.ID || len(enabledRepo.messages) != 2 {
		t.Fatalf("voice replay duplicated exchange: status=%d messages=%d", replay.Code, len(enabledRepo.messages))
	}
}

func assertStatus(t *testing.T, router http.Handler, token, method, path, body string, want int) {
	t.Helper()
	response := performRequest(router, token, method, path, body)
	if response.Code != want {
		t.Fatalf("%s %s: got %d want %d body=%s", method, path, response.Code, want, response.Body.String())
	}
}

func performRequest(router http.Handler, token, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	req.Header.Set("Authorization", "Bearer "+token)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)
	return response
}

type apiLLM struct{}

func (apiLLM) Generate(context.Context, llm.Request) (llm.Response, error) {
	return llm.Response{Text: "Париж.", Provider: "alem", Model: "configured-model"}, nil
}

type apiSessionRepository struct {
	owner     uuid.UUID
	sessionID uuid.UUID
	messages  []assistantmodule.SessionMessage
	exchanges map[uuid.UUID]assistantmodule.StoredExchange
	deleted   bool
	title     string
	createdAt time.Time
	updatedAt time.Time
	calls     int
}

func (r *apiSessionRepository) StudentProfile(context.Context, uuid.UUID) (assistantmodule.StudentAssistantProfile, error) {
	r.calls++
	return assistantmodule.StudentAssistantProfile{Locale: "ru-KZ", GradeLevel: 7}, nil
}
func (r *apiSessionRepository) CreateSession(context.Context, uuid.UUID, string, int) (assistantmodule.AssistantSession, error) {
	r.calls++
	return r.session(), nil
}
func (r *apiSessionRepository) GetSession(_ context.Context, studentID, sessionID uuid.UUID) (assistantmodule.AssistantSession, error) {
	r.calls++
	if studentID != r.owner || sessionID != r.sessionID || r.deleted {
		return assistantmodule.AssistantSession{}, assistantmodule.ErrSessionNotFound
	}
	return r.session(), nil
}
func (r *apiSessionRepository) ListSessions(_ context.Context, studentID uuid.UUID, _ int, _ *assistantmodule.PageCursor) ([]assistantmodule.AssistantSession, error) {
	r.calls++
	if studentID != r.owner || r.deleted {
		return []assistantmodule.AssistantSession{}, nil
	}
	return []assistantmodule.AssistantSession{r.session()}, nil
}
func (r *apiSessionRepository) ListMessages(_ context.Context, studentID, sessionID uuid.UUID, _ int, _ *assistantmodule.PageCursor) ([]assistantmodule.SessionMessage, error) {
	r.calls++
	if _, err := r.GetSession(context.Background(), studentID, sessionID); err != nil {
		return nil, err
	}
	return append([]assistantmodule.SessionMessage(nil), r.messages...), nil
}
func (r *apiSessionRepository) DeleteSession(_ context.Context, studentID, sessionID uuid.UUID) error {
	r.calls++
	if _, err := r.GetSession(context.Background(), studentID, sessionID); err != nil {
		return err
	}
	r.deleted = true
	return nil
}
func (r *apiSessionRepository) FindExchange(_ context.Context, studentID, sessionID, clientID uuid.UUID) (assistantmodule.StoredExchange, bool, error) {
	r.calls++
	if _, err := r.GetSession(context.Background(), studentID, sessionID); err != nil {
		return assistantmodule.StoredExchange{}, false, err
	}
	value, ok := r.exchanges[clientID]
	value.Session = r.session()
	return value, ok, nil
}
func (r *apiSessionRepository) SaveExchange(_ context.Context, studentID, sessionID, clientID uuid.UUID, text, inputMode string, assistant assistantmodule.SessionMessage) (assistantmodule.StoredExchange, error) {
	r.calls++
	if r.exchanges == nil {
		r.exchanges = make(map[uuid.UUID]assistantmodule.StoredExchange)
	}
	if value, ok := r.exchanges[clientID]; ok {
		return value, nil
	}
	if _, err := r.GetSession(context.Background(), studentID, sessionID); err != nil {
		return assistantmodule.StoredExchange{}, err
	}
	now := time.Now().UTC()
	user := assistantmodule.SessionMessage{ID: uuid.NewString(), SessionID: sessionID.String(), Role: "user", Content: text, InputMode: inputMode, CreatedAt: now}
	assistant.ID, assistant.SessionID, assistant.Role, assistant.InputMode, assistant.CreatedAt = uuid.NewString(), sessionID.String(), "assistant", "text", now.Add(time.Millisecond)
	if r.title == "" {
		r.title = text
	}
	r.updatedAt = now
	exchange := assistantmodule.StoredExchange{User: user, Assistant: assistant, Session: r.session()}
	r.messages = append(r.messages, user, assistant)
	r.exchanges[clientID] = exchange
	return exchange, nil
}
func (r *apiSessionRepository) session() assistantmodule.AssistantSession {
	now := time.Now().UTC()
	if r.createdAt.IsZero() {
		r.createdAt = now
	}
	if r.updatedAt.IsZero() {
		r.updatedAt = r.createdAt
	}
	return assistantmodule.AssistantSession{ID: r.sessionID.String(), Locale: "ru-KZ", GradeLevel: 7, Title: r.title, CreatedAt: r.createdAt, UpdatedAt: r.updatedAt, LastMessageAt: r.updatedAt}
}
