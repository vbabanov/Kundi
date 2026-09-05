package v1

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/app"
	assistantmodule "github.com/kundi/kundi/backend/internal/modules/assistant"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/speechauth"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
)

type canaryCountingLLM struct{ calls int }

func (p *canaryCountingLLM) Generate(context.Context, llm.Request) (llm.Response, error) {
	p.calls++
	return llm.Response{Text: "Synthetic answer.", Provider: "test", Model: "test"}, nil
}

type canarySpeechAuthorizer struct {
	allowCalls     int
	authorizeCalls int
}

func (*canarySpeechAuthorizer) Enabled() bool { return true }
func (s *canarySpeechAuthorizer) AllowRequest(string) bool {
	s.allowCalls++
	return true
}
func (s *canarySpeechAuthorizer) Authorize(context.Context, string, string, string, string) (speechauth.Authorization, error) {
	s.authorizeCalls++
	return speechauth.Authorization{}, nil
}

func TestAssistantCanaryDeniedAcrossAllHTTPEntryPointsBeforeDependencies(t *testing.T) {
	allowedStudent := uuid.New()
	deniedStudent := uuid.New()
	sessionID := uuid.New()
	messageID := uuid.New()
	gate, err := assistantmodule.NewCanaryGate(assistantmodule.RolloutModeAllowlist, []uuid.UUID{allowedStudent})
	if err != nil {
		t.Fatal(err)
	}
	repository := &apiSessionRepository{owner: deniedStudent, sessionID: sessionID}
	provider := &canaryCountingLLM{}
	speech := &canarySpeechAuthorizer{}
	enabled := true
	service := assistantmodule.NewServiceWithOptions(persona.NewService(), provider, nil, assistantmodule.Options{
		Enabled: &enabled, VoiceInputEnabled: &enabled, CanaryGate: gate,
		SessionRepository: repository, SpeechBroker: speech,
	})
	tokens := platformauth.NewAccessTokenService("test-secret", time.Hour)
	token, _, err := tokens.Issue(deniedStudent, time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	router := NewRouter(&app.Bootstrap{
		Config:       config.Config{App: config.AppConfig{Name: "test"}},
		AccessTokens: tokens, AssistantService: service,
	})

	requests := []struct {
		method string
		path   string
		body   string
	}{
		{http.MethodPost, "/v1/assistant/message", `{"mode":"tutor","grade_level":7,"text":"synthetic"}`},
		{http.MethodPost, "/v1/assistant/sessions", `{}`},
		{http.MethodGet, "/v1/assistant/sessions", ""},
		{http.MethodGet, "/v1/assistant/sessions/" + sessionID.String() + "/messages", ""},
		{http.MethodPost, "/v1/assistant/sessions/" + sessionID.String() + "/messages", `{"client_message_id":"` + uuid.NewString() + `","text":"synthetic"}`},
		{http.MethodDelete, "/v1/assistant/sessions/" + sessionID.String(), ""},
		{http.MethodPost, "/v1/assistant/sessions/" + sessionID.String() + "/messages/" + messageID.String() + "/speech-authorization", ""},
	}
	for _, request := range requests {
		response := performRequest(router, token, request.method, request.path, request.body)
		if response.Code != http.StatusNotFound {
			t.Fatalf("%s %s: got %d body=%s", request.method, request.path, response.Code, response.Body.String())
		}
		var envelope struct {
			Error struct {
				Code string `json:"code"`
			} `json:"error"`
		}
		if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil || envelope.Error.Code != "assistant_unavailable" {
			t.Fatalf("denial leaked cohort state or changed code: body=%s err=%v", response.Body.String(), err)
		}
	}
	if repository.calls != 0 || provider.calls != 0 || speech.allowCalls != 0 || speech.authorizeCalls != 0 {
		t.Fatalf("denied requests reached dependencies: repo=%d llm=%d speech_allow=%d speech_issue=%d", repository.calls, provider.calls, speech.allowCalls, speech.authorizeCalls)
	}
}

func TestAssistantCanaryAllowedStudentKeepsHappyPath(t *testing.T) {
	studentID := uuid.New()
	gate, err := assistantmodule.NewCanaryGate(assistantmodule.RolloutModeAllowlist, []uuid.UUID{studentID})
	if err != nil {
		t.Fatal(err)
	}
	provider := &canaryCountingLLM{}
	enabled := true
	service := assistantmodule.NewServiceWithOptions(persona.NewService(), provider, nil, assistantmodule.Options{Enabled: &enabled, CanaryGate: gate})
	tokens := platformauth.NewAccessTokenService("test-secret", time.Hour)
	token, _, _ := tokens.Issue(studentID, time.Now().UTC())
	router := NewRouter(&app.Bootstrap{Config: config.Config{App: config.AppConfig{Name: "test"}}, AccessTokens: tokens, AssistantService: service})
	response := performRequest(router, token, http.MethodPost, "/v1/assistant/message", `{"mode":"tutor","grade_level":7,"text":"synthetic"}`)
	if response.Code != http.StatusOK || provider.calls != 1 {
		t.Fatalf("allowed canary request failed: status=%d calls=%d body=%s", response.Code, provider.calls, response.Body.String())
	}
}
