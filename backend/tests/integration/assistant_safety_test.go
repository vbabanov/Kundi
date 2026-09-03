package integration

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
	"github.com/kundi/kundi/backend/internal/modules/assistant/ratelimit"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/transport/http/v1"
)

type integrationCountingLLM struct {
	text  string
	calls int
}

func (f *integrationCountingLLM) Generate(context.Context, llm.Request) (llm.Response, error) {
	f.calls++
	return llm.Response{Text: f.text}, nil
}

type integrationCountingTTS struct {
	calls int
}

func (f *integrationCountingTTS) Render(context.Context, string) (string, error) {
	f.calls++
	return "", nil
}

func TestAssistantEndpointPreservesAuthenticationAndSafetyContract(t *testing.T) {
	tokens := platformauth.NewAccessTokenService("secret-key", 20*time.Minute)
	studentID := uuid.MustParse("8d8d8ec8-27e6-4623-a325-c2e7e9db2da2")
	provider := &integrationCountingLLM{text: "must not be called"}
	speech := &integrationCountingTTS{}
	deps := &app.Bootstrap{
		Config:       config.Config{App: config.AppConfig{Name: "test"}},
		AccessTokens: tokens,
		AssistantService: assistantmodule.NewService(
			persona.NewService(),
			provider,
			speech,
		),
	}
	router := v1.NewRouter(deps)
	body := []byte(`{"mode":"tutor","grade_level":7,"text":"Я хочу покончить с собой","history":[]}`)

	unauthorized := httptest.NewRequest(http.MethodPost, "/v1/assistant/message", bytes.NewReader(body))
	unauthorizedResponse := httptest.NewRecorder()
	router.ServeHTTP(unauthorizedResponse, unauthorized)
	if unauthorizedResponse.Code != http.StatusUnauthorized || provider.calls != 0 {
		t.Fatalf("authentication was not preserved: status=%d llm_calls=%d", unauthorizedResponse.Code, provider.calls)
	}

	token := issueAccessToken(t, tokens, studentID)
	authorized := httptest.NewRequest(http.MethodPost, "/v1/assistant/message", bytes.NewReader(body))
	authorized.Header.Set("Authorization", "Bearer "+token)
	authorized.Header.Set("Content-Type", "application/json")
	authorizedResponse := httptest.NewRecorder()
	router.ServeHTTP(authorizedResponse, authorized)
	if authorizedResponse.Code != http.StatusOK {
		t.Fatalf("expected safe response status 200, got %d body=%s", authorizedResponse.Code, authorizedResponse.Body.String())
	}
	if provider.calls != 0 || speech.calls != 0 {
		t.Fatalf("moderation block reached providers: llm=%d tts=%d", provider.calls, speech.calls)
	}
	var envelope struct {
		Data assistantmodule.Response `json:"data"`
	}
	if err := json.Unmarshal(authorizedResponse.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("invalid safe response: %v", err)
	}
	if envelope.Data.Text == "" || !envelope.Data.Pedagogy.SafetyIntervention || envelope.Data.AudioStatus != assistantmodule.AudioStatusUnavailable {
		t.Fatalf("safe response contract is incomplete: %#v", envelope.Data)
	}
}

func TestAssistantEndpointRateLimitReturnsTyped429WithoutSecondProviderCall(t *testing.T) {
	tokens := platformauth.NewAccessTokenService("secret-key", 20*time.Minute)
	studentID := uuid.MustParse("8d8d8ec8-27e6-4623-a325-c2e7e9db2da2")
	token := issueAccessToken(t, tokens, studentID)
	provider := &integrationCountingLLM{text: "A safe answer."}
	speech := &integrationCountingTTS{}
	service := assistantmodule.NewServiceWithOptions(persona.NewService(), provider, speech, assistantmodule.Options{
		RateLimiter: ratelimit.NewInMemory(ratelimit.Config{Limit: 1, Window: time.Minute, MaxIdentities: 10}),
	})
	router := v1.NewRouter(&app.Bootstrap{
		Config:           config.Config{App: config.AppConfig{Name: "test"}},
		AccessTokens:     tokens,
		AssistantService: service,
	})
	body := []byte(`{"mode":"tutor","grade_level":7,"text":"Explain fractions","history":[]}`)

	request := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/v1/assistant/message", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		resp := httptest.NewRecorder()
		router.ServeHTTP(resp, req)
		return resp
	}
	if first := request(); first.Code != http.StatusOK {
		t.Fatalf("first request failed: %d %s", first.Code, first.Body.String())
	}
	second := request()
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d body=%s", second.Code, second.Body.String())
	}
	var envelope struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(second.Body.Bytes(), &envelope); err != nil || envelope.Error.Code != "assistant_rate_limited" {
		t.Fatalf("expected typed rate limit error, body=%s err=%v", second.Body.String(), err)
	}
	if provider.calls != 1 || speech.calls != 1 {
		t.Fatalf("limited request reached providers: llm=%d tts=%d", provider.calls, speech.calls)
	}
}
