package v1

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/kundi/kundi/backend/internal/app"
	"github.com/kundi/kundi/backend/internal/platform/config"
)

func TestReadyReportsAzureSpeechConfigurationWithoutLeakingKeys(t *testing.T) {
	const secret = "primary-key-must-never-appear-in-readyz"
	valid := azureReadyConfig(secret)
	for _, test := range []struct {
		name       string
		mutate     func(*config.Config)
		statusCode int
	}{
		{name: "valid Azure configuration", statusCode: http.StatusOK},
		{name: "invalid Azure configuration", mutate: func(c *config.Config) { c.AI.AzureSpeechRegion = "not-a-region" }, statusCode: http.StatusServiceUnavailable},
	} {
		t.Run(test.name, func(t *testing.T) {
			cfg := valid
			if test.mutate != nil {
				test.mutate(&cfg)
			}
			recorder := httptest.NewRecorder()
			NewRouter(&app.Bootstrap{Config: cfg}).ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/readyz", nil))
			if recorder.Code != test.statusCode {
				t.Fatalf("expected status %d, got %d: %s", test.statusCode, recorder.Code, recorder.Body.String())
			}
			if strings.Contains(recorder.Body.String(), secret) {
				t.Fatalf("readyz response leaked Azure key: %s", recorder.Body.String())
			}
		})
	}
}

func azureReadyConfig(key string) config.Config {
	return config.Config{
		App: config.AppConfig{Name: "test"},
		AI: config.AIConfig{
			KundiTTSEnabled:       true,
			AssistantEnabled:      true,
			VoiceInputEnabled:     true,
			AzureSpeechKeyPrimary: key,
			AzureSpeechRegion:     "westus",
			AzureSpeechVoiceRU:    "ru-RU-SvetlanaNeural",
			AzureSpeechVoiceKK:    "kk-KZ-AigulNeural",
			AlemBaseURL:           "https://llm.example/v1",
			AlemPrimaryAPIKey:     "test-alem-key",
			AlemPrimaryModel:      "test-model",
		},
	}
}
