package v1

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/kundi/kundi/backend/internal/app"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
)

func TestGamificationRoutesRequireAuthentication(t *testing.T) {
	tokens := platformauth.NewAccessTokenService("test-secret", time.Hour)
	router := NewRouter(&app.Bootstrap{
		Config:       config.Config{App: config.AppConfig{Name: "test"}},
		AccessTokens: tokens,
	})
	for _, testCase := range []struct {
		method string
		path   string
	}{
		{http.MethodGet, "/v1/gamification/profile"},
		{http.MethodGet, "/v1/gamification/achievements"},
		{http.MethodPost, "/v1/gamification/activity"},
		{http.MethodPost, "/v1/gamification/achievements/ack"},
	} {
		t.Run(testCase.method+" "+testCase.path, func(t *testing.T) {
			response := httptest.NewRecorder()
			router.ServeHTTP(response, httptest.NewRequest(testCase.method, testCase.path, nil))
			if response.Code != http.StatusUnauthorized {
				t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
			}
		})
	}
}
