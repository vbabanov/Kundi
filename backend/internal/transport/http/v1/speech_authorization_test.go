package v1

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/app"
	assistant "github.com/kundi/kundi/backend/internal/modules/assistant"
	"github.com/kundi/kundi/backend/internal/modules/assistant/speechauth"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
)

func TestSpeechAuthorizationAuthenticatedNoStoreAndOwnRateLimit(t *testing.T) {
	student, session := uuid.New(), uuid.New()
	repo := &apiSessionRepository{owner: student, sessionID: session}
	enabled := true
	service := assistant.NewServiceWithOptions(nil, nil, nil, assistant.Options{CanaryGate: assistant.AllowAllCanaryGate(),
		Enabled: &enabled, VoiceInputEnabled: &enabled, SessionRepository: repo,
		SpeechBroker: speechauth.New(speechauth.Config{Enabled: true}),
	})
	tokens := platformauth.NewAccessTokenService("fake-local-secret", time.Hour)
	token, _, _ := tokens.Issue(student, time.Now())
	router := NewRouter(&app.Bootstrap{Config: config.Config{App: config.AppConfig{Name: "test"}}, AccessTokens: tokens, AssistantService: service})
	path := "/v1/assistant/sessions/" + session.String() + "/messages/" + uuid.NewString() + "/speech-authorization"
	unauthorized := performRequest(router, "", http.MethodPost, path, "")
	if unauthorized.Code != 401 || unauthorized.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("auth or no-store missing")
	}
	invalidLocaleRequest := httptest.NewRequest(http.MethodPost, path, strings.NewReader(""))
	invalidLocaleRequest.Header.Set("Authorization", "Bearer "+token)
	invalidLocaleRequest.Header.Set("X-Kundi-Voice-Locale", "en-US")
	invalidLocaleResponse := httptest.NewRecorder()
	router.ServeHTTP(invalidLocaleResponse, invalidLocaleRequest)
	if invalidLocaleResponse.Code != http.StatusBadRequest ||
		!strings.Contains(invalidLocaleResponse.Body.String(), "speech_locale_invalid") {
		t.Fatalf("voice locale header was not enforced: status=%d body=%s", invalidLocaleResponse.Code, invalidLocaleResponse.Body.String())
	}
	// The authenticated invalid-locale request above consumes one endpoint
	// limiter slot even though the service rejects it before broker access.
	for i := 0; i < speechauth.RequestsPerMinute-1; i++ {
		response := performRequest(router, token, http.MethodPost, path, "")
		if response.Code == 429 || response.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("incorrect limiter or caching")
		}
	}
	limited := performRequest(router, token, http.MethodPost, path, "")
	if limited.Code != 429 || limited.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("separate speech limiter missing")
	}
}
