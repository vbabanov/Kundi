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
	"github.com/kundi/kundi/backend/internal/modules/assistant/safety"
	"github.com/kundi/kundi/backend/internal/modules/persona"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/transport/http/v1"
)

func TestAssistantEndpointHappyPath(t *testing.T) {
	tokens := platformauth.NewAccessTokenService("secret-key", 20*time.Minute)
	studentID := uuid.MustParse("8d8d8ec8-27e6-4623-a325-c2e7e9db2da2")
	token := issueAccessToken(t, tokens, studentID)

	deps := &app.Bootstrap{
		Config:       config.Config{App: config.AppConfig{Name: "test"}},
		AccessTokens: tokens,
		AssistantService: assistantmodule.NewServiceWithOptions(
			persona.NewService(),
			llm.NewDeterministicProvider(),
			integrationTrustedTTS{},
			assistantmodule.Options{AudioURLValidator: safety.NewAudioURLValidator([]string{"media.example.com"})},
		),
	}

	router := v1.NewRouter(deps)
	raw, _ := json.Marshal(map[string]any{
		"mode":        "tutor",
		"grade_level": 4,
		"text":        "Help me with fractions",
		"history":     []map[string]string{{"role": "user", "text": "Hello"}},
	})
	req := httptest.NewRequest(http.MethodPost, "/v1/assistant/message", bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp := httptest.NewRecorder()
	router.ServeHTTP(resp, req)
	if resp.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d, body=%s", resp.Code, resp.Body.String())
	}

	var envelope map[string]map[string]any
	if err := json.Unmarshal(resp.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("invalid response body: %v", err)
	}
	data := envelope["data"]
	if data == nil {
		t.Fatalf("expected response data envelope")
	}
	if data["text"] == "" {
		t.Fatalf("assistant response text is required")
	}
	if data["audioUrl"] == "" {
		t.Fatalf("assistant response audioUrl is required")
	}
	if data["audio_status"] != "ready" {
		t.Fatalf("expected audio_status=ready, got %#v", data["audio_status"])
	}
	if data["avatar_emotion"] == "" {
		t.Fatalf("assistant response avatar emotion is required")
	}
	if _, ok := data["visemes"].([]any); !ok {
		t.Fatalf("assistant response visemes must be an array")
	}
	behavior, ok := data["behavior"].(map[string]any)
	if !ok {
		t.Fatalf("assistant response behavior meta is required")
	}
	if behavior["grade_band"] != "primary" {
		t.Fatalf("expected primary grade_band, got %#v", behavior["grade_band"])
	}
}

type integrationTrustedTTS struct{}

func (integrationTrustedTTS) Render(context.Context, string) (string, error) {
	return "https://media.example.com/audio/assistant.mp3", nil
}
