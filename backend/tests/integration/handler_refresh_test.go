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
	authmodule "github.com/kundi/kundi/backend/internal/modules/auth"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/platform/crypto"
	"github.com/kundi/kundi/backend/internal/transport/http/v1"
)

type refreshAccountRepo struct{}

func (refreshAccountRepo) UpsertDiaryAccount(_ context.Context, _ string, _ string, _ []byte, _ []byte) (uuid.UUID, uuid.UUID, error) {
	return uuid.MustParse("8d8d8ec8-27e6-4623-a325-c2e7e9db2da2"), uuid.New(), nil
}

type refreshSessionStore struct{}

func (refreshSessionStore) Create(_ context.Context, _ uuid.UUID, _ string, _ string, _ string, _ time.Time) error {
	return nil
}

func (refreshSessionStore) Revoke(_ context.Context, _ string) error { return nil }

func (refreshSessionStore) ResolveStudentID(_ context.Context, _ string) (uuid.UUID, error) {
	return uuid.MustParse("8d8d8ec8-27e6-4623-a325-c2e7e9db2da2"), nil
}

func TestRefreshHandler(t *testing.T) {
	cipher, err := crypto.NewFieldCipher("0123456789abcdef0123456789abcdef")
	if err != nil {
		t.Fatalf("cipher init failed: %v", err)
	}
	tokens := platformauth.NewAccessTokenService("secret-key", 20*time.Minute)
	authService := authmodule.NewService(refreshAccountRepo{}, cipher, tokens, refreshSessionStore{}, 24*time.Hour)

	deps := &app.Bootstrap{
		Config:       config.Config{App: config.AppConfig{Name: "test"}},
		AuthService:  authService,
		AccessTokens: tokens,
	}
	router := v1.NewRouter(deps)

	raw, _ := json.Marshal(map[string]string{"refresh_token": "refresh-raw-token"})
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/refresh", bytes.NewReader(raw))
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
		t.Fatalf("expected data envelope")
	}
	if data["refresh_token"] == "" {
		t.Fatalf("refresh_token must be present in refresh response")
	}
}
