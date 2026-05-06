package integration

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/app"
	ingestmodule "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	"github.com/kundi/kundi/backend/internal/platform/config"
	"github.com/kundi/kundi/backend/internal/transport/http/v1"
)

type memoryIngestRepository struct {
	mu       sync.Mutex
	batches  map[string]uuid.UUID
	checksum map[string]string
	merged   map[string]bool
}

func newMemoryIngestRepository() *memoryIngestRepository {
	return &memoryIngestRepository{
		batches:  make(map[string]uuid.UUID),
		checksum: make(map[string]string),
		merged:   make(map[string]bool),
	}
}

func (m *memoryIngestRepository) CreateBatch(_ context.Context, studentID uuid.UUID, bundle ingestmodule.CanonicalIngestBundle, checksum string) (uuid.UUID, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := studentID.String() + ":" + bundle.IdempotencyKey
	if id, ok := m.batches[key]; ok {
		if m.checksum[key] != checksum {
			return id, false, ingestmodule.ErrIdempotencyConflict
		}
		return id, false, nil
	}
	id := uuid.New()
	m.batches[key] = id
	m.checksum[key] = checksum
	return id, true, nil
}

func (m *memoryIngestRepository) MergeBundle(_ context.Context, _ uuid.UUID, bundle ingestmodule.CanonicalIngestBundle) (int, int, error) {
	totalGrades := 0
	for _, lesson := range bundle.Lessons {
		totalGrades += len(lesson.Grades)
	}
	return len(bundle.Lessons), totalGrades, nil
}

func (m *memoryIngestRepository) MarkMerged(_ context.Context, batchID uuid.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.merged[batchID.String()] = true
	return nil
}

func TestIngestEndpointHappyPath(t *testing.T) {
	tokens := platformauth.NewAccessTokenService("secret-key", 20*time.Minute)
	studentID := uuid.MustParse("8d8d8ec8-27e6-4623-a325-c2e7e9db2da2")
	token := issueAccessToken(t, tokens, studentID)

	ingestRepo := newMemoryIngestRepository()
	deps := &app.Bootstrap{
		Config:        config.Config{App: config.AppConfig{Name: "test"}},
		AccessTokens:  tokens,
		IngestService: ingestmodule.NewService(ingestRepo),
	}
	router := v1.NewRouter(deps)

	bundle := map[string]any{
		"source":          "kundelik",
		"source_account":  "student-login",
		"idempotency_key": "ingest-key-20260330",
		"synced_at":       "2026-03-30T10:00:00Z",
		"source_ids":      map[string]string{"person_id": "123"},
		"profile": map[string]any{
			"first_name":  "Aruzhan",
			"last_name":   "K.",
			"grade_level": 7,
			"class_label": "7A",
			"school_name": "Kundi School",
		},
		"lessons": []map[string]any{
			{
				"source_lesson_key": "l1",
				"date":              "2026-03-30",
				"lesson_number":     1,
				"subject_name":      "Math",
				"start_time":        "08:30",
				"end_time":          "09:15",
				"topic_title":       "Linear equations",
				"homework": map[string]any{
					"source_homework_key": "hw1",
					"description":         "Solve 1-10",
					"requires_photo":      true,
				},
				"grades": []map[string]any{
					{"source_grade_key": "g1", "value": "5", "type": "regular"},
				},
			},
		},
		"attendance": []map[string]any{
			{"source_event_key": "a1", "date": "2026-03-30", "code": "present", "reason": ""},
		},
	}

	first := executeJSONRequest(t, router, token, bundle)
	if first.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", first.Code, first.Body.String())
	}
	firstData := readDataEnvelope(t, first.Body.Bytes())
	if firstData["already_processed"] != false {
		t.Fatalf("expected already_processed=false on first ingest")
	}
	if firstData["merged_lessons"] != float64(1) {
		t.Fatalf("expected merged_lessons=1, got %#v", firstData["merged_lessons"])
	}

	second := executeJSONRequest(t, router, token, bundle)
	if second.Code != http.StatusOK {
		t.Fatalf("expected 200 for replay, got %d body=%s", second.Code, second.Body.String())
	}
	secondData := readDataEnvelope(t, second.Body.Bytes())
	if secondData["already_processed"] != true {
		t.Fatalf("expected already_processed=true on idempotent replay")
	}
}

func executeJSONRequest(t *testing.T, router http.Handler, token string, payload map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	raw, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPost, "/v1/ingest/bundle", bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp := httptest.NewRecorder()
	router.ServeHTTP(resp, req)
	return resp
}

func readDataEnvelope(t *testing.T, body []byte) map[string]any {
	t.Helper()
	var envelope map[string]map[string]any
	if err := json.Unmarshal(body, &envelope); err != nil {
		t.Fatalf("invalid response json: %v", err)
	}
	data := envelope["data"]
	if data == nil {
		t.Fatalf("missing response data envelope")
	}
	return data
}

func digestPayload(payload map[string]any) string {
	raw, _ := json.Marshal(payload)
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}
