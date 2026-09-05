package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kundi/kundi/backend/internal/app"
	"github.com/kundi/kundi/backend/internal/modules/academic"
	"github.com/kundi/kundi/backend/internal/modules/jobs"
	whatsappmodule "github.com/kundi/kundi/backend/internal/modules/whatsapp"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/transport/http/v1"
)

func TestWhatsAppHandlerCreatesJobAndHonorsIdempotency(t *testing.T) {
	dsn := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set; skipping whatsapp handler integration test")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	defer pool.Close()

	repo := newMemoryJobsRepository(time.Date(2026, 3, 30, 12, 0, 0, 0, time.UTC))
	jobsSvc := jobs.NewService(repo)
	whatsappSvc := whatsappmodule.NewService(jobsSvc)
	tokens := platformauth.NewAccessTokenService("secret-key", 20*time.Minute)
	studentID := uuid.New()
	if _, err := pool.Exec(ctx,
		`INSERT INTO students(id, external_student_ref) VALUES ($1, $2)`,
		studentID, "whatsapp-handler-"+studentID.String(),
	); err != nil {
		t.Fatalf("seed student failed: %v", err)
	}
	defer func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cleanupCancel()
		if _, err := pool.Exec(cleanupCtx, `DELETE FROM students WHERE id = $1`, studentID); err != nil {
			t.Errorf("cleanup student failed: %v", err)
		}
	}()

	if _, err := pool.Exec(
		ctx,
		`
		INSERT INTO student_app_profiles(student_id, shift, parent_phone_1, parent_phone_2, updated_at)
		VALUES ($1, 1, '+77771234567', '', NOW())
		ON CONFLICT (student_id) DO UPDATE
		SET shift = EXCLUDED.shift,
			parent_phone_1 = EXCLUDED.parent_phone_1,
			parent_phone_2 = EXCLUDED.parent_phone_2,
			updated_at = NOW()
		`,
		studentID,
	); err != nil {
		t.Fatalf("seed student_app_profiles failed: %v", err)
	}
	token := issueAccessToken(t, tokens, studentID)

	deps := &app.Bootstrap{
		Config:          config.Config{App: config.AppConfig{Name: "test"}},
		Pool:            pool,
		AccessTokens:    tokens,
		AcademicService: academic.NewService(pool),
		WhatsAppService: whatsappSvc,
	}
	router := v1.NewRouter(deps)

	first := postDigestRequest(t, router, token, "digest-handler-key")
	if first.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d body=%s", first.Code, first.Body.String())
	}
	firstData := readDataEnvelope(t, first.Body.Bytes())
	if firstData["created"] != true {
		t.Fatalf("expected created=true on first request")
	}

	second := postDigestRequest(t, router, token, "digest-handler-key")
	if second.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d body=%s", second.Code, second.Body.String())
	}
	secondData := readDataEnvelope(t, second.Body.Bytes())
	if secondData["created"] != false {
		t.Fatalf("expected created=false on duplicate idempotency request")
	}
}

func postDigestRequest(t *testing.T, router http.Handler, token string, idempotency string) *httptest.ResponseRecorder {
	t.Helper()
	raw, _ := json.Marshal(map[string]string{"date": "2026-03-30"})
	req := httptest.NewRequest(http.MethodPost, "/v1/whatsapp/send-homework", bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Idempotency-Key", idempotency)
	resp := httptest.NewRecorder()
	router.ServeHTTP(resp, req)
	return resp
}
