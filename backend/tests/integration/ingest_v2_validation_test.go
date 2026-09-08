package integration

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/app"
	ingestmodule "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/transport/http/v1"
)

func TestIngestV2RejectsMalformedJSONBeforeMerge(t *testing.T) {
	tokens := platformauth.NewAccessTokenService("secret-key", 20*time.Minute)
	studentID := uuid.MustParse("77dd24fa-95af-4ace-9a9a-b4b7a923e367")
	token := issueAccessToken(t, tokens, studentID)
	repo := newMemoryIngestRepository()
	router := v1.NewRouter(&app.Bootstrap{
		Config:        config.Config{App: config.AppConfig{Name: "test"}},
		AccessTokens:  tokens,
		IngestService: ingestmodule.NewService(repo),
	})

	req := httptest.NewRequest(
		http.MethodPost,
		"/v2/ingest/bundle",
		bytes.NewBufferString(`{"contract_version":2,"source":"kundelik"`),
	)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected malformed v2 payload to return 400, got %d body=%s", response.Code, response.Body.String())
	}
	var envelope struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	if envelope.Error.Code != "invalid_json" {
		t.Fatalf("expected invalid_json, got %q", envelope.Error.Code)
	}
}
