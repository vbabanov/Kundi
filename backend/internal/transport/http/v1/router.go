package v1

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kundi/kundi/backend/internal/app"
	"github.com/kundi/kundi/backend/internal/contracts"
	"github.com/kundi/kundi/backend/internal/integrations/providerstatus"
	"github.com/kundi/kundi/backend/internal/modules/academic"
	assistantmodule "github.com/kundi/kundi/backend/internal/modules/assistant"
	assistantsafety "github.com/kundi/kundi/backend/internal/modules/assistant/safety"
	authmodule "github.com/kundi/kundi/backend/internal/modules/auth"
	ingestmodule "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	platformauth "github.com/kundi/kundi/backend/internal/platform/auth"
	httpx "github.com/kundi/kundi/backend/internal/platform/http"
)

type API struct {
	deps *app.Bootstrap
}

func NewRouter(deps *app.Bootstrap) http.Handler {
	mux := http.NewServeMux()
	api := &API{deps: deps}

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		httpx.JSON(w, http.StatusOK, map[string]any{"status": "ok", "service": deps.Config.App.Name})
	})
	mux.HandleFunc("GET /readyz", api.ready)

	mux.HandleFunc("POST /v1/auth/login", api.login)
	mux.HandleFunc("POST /v1/auth/refresh", api.refreshToken)

	withAuth := func(fn http.HandlerFunc) http.Handler {
		return platformauth.Middleware(deps.AccessTokens, http.HandlerFunc(fn))
	}

	mux.Handle("POST /v1/ingest/bundle", withAuth(api.ingestBundle))
	mux.Handle("POST /v2/ingest/bundle", withAuth(api.ingestBundleV2))
	mux.Handle("GET /v1/profile", withAuth(api.profile))
	mux.Handle("GET /v2/profile", withAuth(api.profileV2))
	mux.Handle("GET /v2/results", withAuth(api.resultsV2))
	mux.Handle("GET /v2/academic/overview", withAuth(api.academicOverviewV2))
	mux.Handle("GET /v1/lessons", withAuth(api.lessons))
	mux.Handle("GET /v1/homework", withAuth(api.homework))
	mux.Handle("GET /v1/grades", withAuth(api.grades))
	mux.Handle("GET /v1/attendance", withAuth(api.attendance))
	mux.Handle("PUT /v1/profile/local", withAuth(api.updateLocalAppProfile))
	mux.Handle("POST /v1/assistant/message", withAuth(api.assistantMessage))
	mux.Handle("POST /v1/assistant/sessions", withAuth(api.createAssistantSession))
	mux.Handle("GET /v1/assistant/sessions", withAuth(api.listAssistantSessions))
	mux.Handle("GET /v1/assistant/sessions/{sessionID}/messages", withAuth(api.listAssistantMessages))
	mux.Handle("POST /v1/assistant/sessions/{sessionID}/messages", withAuth(api.sendAssistantMessage))
	mux.Handle("POST /v1/assistant/sessions/{sessionID}/messages/{messageID}/speech-authorization", speechNoStore(withAuth(api.speechAuthorization)))
	mux.Handle("DELETE /v1/assistant/sessions/{sessionID}", withAuth(api.deleteAssistantSession))
	mux.Handle("POST /v1/whatsapp/send-homework", withAuth(api.sendHomeworkDigest))
	mux.Handle("POST /v1/whatsapp/send-photo", withAuth(api.sendHomeworkPhoto))
	mux.Handle("GET /v1/whatsapp/jobs/{jobID}", withAuth(api.whatsappJobStatus))

	return mux
}

func (a *API) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	var dbErr error
	if a.deps.Pool != nil {
		dbErr = a.deps.Pool.Ping(ctx)
	}
	providers := providerstatus.Build(a.deps.Config)

	statusCode := http.StatusOK
	if dbErr != nil || providers.HasMisconfiguredProvider() {
		statusCode = http.StatusServiceUnavailable
	}

	checks := map[string]any{
		"database": map[string]any{
			"status": map[bool]string{true: "ok", false: "error"}[dbErr == nil],
		},
	}
	if dbErr != nil {
		checks["database"].(map[string]any)["reason"] = dbErr.Error()
	}

	httpx.JSON(w, statusCode, map[string]any{
		"status": map[int]string{
			http.StatusOK:                 "ready",
			http.StatusServiceUnavailable: "degraded",
		}[statusCode],
		"service":   a.deps.Config.App.Name,
		"checks":    checks,
		"providers": providers,
	})
}

func (a *API) login(w http.ResponseWriter, r *http.Request) {
	var req contracts.LoginRequest
	if err := decodeJSONStrict(r, &req); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	result, err := a.deps.AuthService.Login(r.Context(), authCommandFromLoginRequest(req, r))
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, contracts.LoginResponse{
		StudentID:    result.StudentID,
		AccessToken:  result.AccessToken,
		RefreshToken: result.RefreshToken,
		ExpiresAt:    result.ExpiresAtISO,
	})
}

func (a *API) refreshToken(w http.ResponseWriter, r *http.Request) {
	var req contracts.RefreshRequest
	if err := decodeJSONStrict(r, &req); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	if strings.TrimSpace(req.RefreshToken) == "" {
		httpx.JSONError(w, apperrors.BadRequest("refresh_token_required", "refresh_token is required"))
		return
	}
	result, err := a.deps.AuthService.RotateRefreshToken(
		r.Context(),
		req.RefreshToken,
		strings.TrimSpace(r.UserAgent()),
		clientIP(r),
	)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, contracts.LoginResponse{
		StudentID:    result.StudentID,
		AccessToken:  result.AccessToken,
		RefreshToken: result.RefreshToken,
		ExpiresAt:    result.ExpiresAtISO,
	})
}

func (a *API) ingestBundle(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	var bundle ingestmodule.CanonicalIngestBundle
	if err := decodeJSONStrict(r, &bundle); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	if strings.TrimSpace(bundle.IdempotencyKey) == "" {
		bundle.IdempotencyKey = strings.TrimSpace(r.Header.Get("X-Idempotency-Key"))
	}
	result, err := a.deps.IngestService.IngestBundle(r.Context(), studentID, bundle)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	if a.deps.AuditService != nil {
		_ = a.deps.AuditService.Log(r.Context(), "ingest_bundle", "ingest_batch", result.BatchID, studentID.String(), map[string]any{
			"source":            bundle.Source,
			"already_processed": result.AlreadyProcessed,
		})
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) ingestBundleV2(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	var bundle ingestmodule.CanonicalIngestBundleV2
	if err := decodeJSONStrict(r, &bundle); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	if strings.TrimSpace(bundle.IdempotencyKey) == "" {
		bundle.IdempotencyKey = strings.TrimSpace(r.Header.Get("X-Idempotency-Key"))
	}
	result, err := a.deps.IngestService.IngestBundleV2(r.Context(), studentID, bundle)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	if a.deps.AuditService != nil {
		_ = a.deps.AuditService.Log(r.Context(), "ingest_bundle_v2", "ingest_batch", result.BatchID, studentID.String(), map[string]any{
			"source":            bundle.Source,
			"already_processed": result.AlreadyProcessed,
		})
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) profile(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	result, err := a.deps.ProfilesService.Get(r.Context(), studentID)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) profileV2(w http.ResponseWriter, r *http.Request) {
	startedAt := time.Now()
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	window, err := readWindowFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	result, err := a.deps.AcademicService.ProfileV2(r.Context(), studentID, window)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("profile_v2_load_failed", "failed to load v2 profile", err))
		return
	}
	if a.deps.Logger != nil {
		traceID := strings.TrimSpace(r.Header.Get("X-Trace-Id"))
		a.deps.Logger.Info(
			"v2_read_profile",
			slog.String("read_mode", "v2"),
			slog.String("trace_id", traceID),
			slog.String("provider", result.Window.Provider),
			slog.String("window_key", result.Window.WindowKey),
			slog.String("snapshot_at", result.Window.SnapshotAt),
			slog.Bool("has_local_app_profile", result.LocalAppProfile != nil),
			slog.Int64("latency_ms", time.Since(startedAt).Milliseconds()),
		)
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) resultsV2(w http.ResponseWriter, r *http.Request) {
	startedAt := time.Now()
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	window, err := readWindowFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	limit := 300
	limitRaw := strings.TrimSpace(r.URL.Query().Get("limit"))
	if limitRaw != "" {
		parsed, parseErr := strconv.Atoi(limitRaw)
		if parseErr != nil || parsed <= 0 || parsed > 1000 {
			httpx.JSONError(w, apperrors.BadRequest("invalid_limit", "limit must be between 1 and 1000"))
			return
		}
		limit = parsed
	}
	result, err := a.deps.AcademicService.ResultsV2(r.Context(), studentID, window, limit)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("results_v2_load_failed", "failed to load v2 results", err))
		return
	}
	if a.deps.Logger != nil {
		traceID := strings.TrimSpace(r.Header.Get("X-Trace-Id"))
		a.deps.Logger.Info(
			"v2_read_results",
			slog.String("read_mode", "v2"),
			slog.String("trace_id", traceID),
			slog.String("provider", result.Window.Provider),
			slog.String("window_key", result.Window.WindowKey),
			slog.String("snapshot_at", result.Window.SnapshotAt),
			slog.Int("results_count", len(result.Results)),
			slog.Int("aggregates_count", len(result.Aggregates)),
			slog.Int("lessons_count", len(result.Lessons)),
			slog.Int("attendance_count", len(result.Attendance)),
			slog.Int64("latency_ms", time.Since(startedAt).Milliseconds()),
		)
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) academicOverviewV2(w http.ResponseWriter, r *http.Request) {
	startedAt := time.Now()
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	window, err := readWindowFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	result, err := a.deps.AcademicService.OverviewV2(r.Context(), studentID, window)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("overview_v2_load_failed", "failed to load v2 overview", err))
		return
	}
	if a.deps.Logger != nil {
		traceID := strings.TrimSpace(r.Header.Get("X-Trace-Id"))
		a.deps.Logger.Info(
			"v2_read_overview",
			slog.String("read_mode", "v2"),
			slog.String("trace_id", traceID),
			slog.String("provider", result.Window.Provider),
			slog.String("window_key", result.Window.WindowKey),
			slog.String("snapshot_at", result.Window.SnapshotAt),
			slog.Int("results_in_window", result.Counts.ResultsInWindow),
			slog.Int("lessons_in_window", result.Counts.LessonsInWindow),
			slog.Int("aggregates_in_window", result.Counts.AggregatesInWindow),
			slog.Int("attendance_alerts", result.Counts.AttendanceAlerts),
			slog.Int64("latency_ms", time.Since(startedAt).Milliseconds()),
		)
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) lessons(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	items, err := a.deps.AcademicService.Lessons(r.Context(), studentID)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("lessons_load_failed", "failed to load lessons", err))
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items})
}

func (a *API) homework(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	items, err := a.deps.AcademicService.Homework(r.Context(), studentID)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("homework_load_failed", "failed to load homework", err))
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items})
}

func (a *API) grades(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	items, err := a.deps.AcademicService.Grades(r.Context(), studentID)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("grades_load_failed", "failed to load grades", err))
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items})
}

func (a *API) attendance(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	items, err := a.deps.AcademicService.Attendance(r.Context(), studentID)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("attendance_load_failed", "failed to load attendance", err))
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items})
}

func (a *API) assistantMessage(w http.ResponseWriter, r *http.Request) {
	if !a.assistantEnabled(w) {
		return
	}
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	var req struct {
		Mode       string                       `json:"mode"`
		GradeLevel int                          `json:"grade_level"`
		Text       string                       `json:"text"`
		History    []assistantmodule.ChatRecord `json:"history"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, assistantsafety.DefaultMaxRequestBodyBytes)
	if err := decodeJSONStrict(r, &req); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	result, err := a.deps.AssistantService.Message(r.Context(), assistantmodule.MessageCommand{
		StudentID:        studentID.String(),
		Mode:             assistantmodule.Mode(strings.TrimSpace(req.Mode)),
		GradeLevel:       req.GradeLevel,
		Text:             req.Text,
		History:          req.History,
		EnforceRateLimit: true,
	})
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) createAssistantSession(w http.ResponseWriter, r *http.Request) {
	if !a.assistantEnabled(w) {
		return
	}
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4*1024)
	var req struct{}
	if err := decodeJSONStrict(r, &req); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	result, err := a.deps.AssistantService.CreateSession(r.Context(), studentID.String())
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, result)
}

func (a *API) listAssistantSessions(w http.ResponseWriter, r *http.Request) {
	if !a.assistantEnabled(w) {
		return
	}
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	limit, err := assistantPageLimit(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	result, err := a.deps.AssistantService.ListSessions(r.Context(), studentID.String(), limit, r.URL.Query().Get("cursor"))
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) listAssistantMessages(w http.ResponseWriter, r *http.Request) {
	if !a.assistantEnabled(w) {
		return
	}
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	limit, err := assistantPageLimit(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	result, err := a.deps.AssistantService.ListSessionMessages(r.Context(), studentID.String(), r.PathValue("sessionID"), limit, r.URL.Query().Get("cursor"))
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) sendAssistantMessage(w http.ResponseWriter, r *http.Request) {
	if !a.assistantEnabled(w) {
		return
	}
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	var req struct {
		ClientMessageID string `json:"client_message_id"`
		Text            string `json:"text"`
		InputMode       string `json:"input_mode,omitempty"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, assistantsafety.DefaultMaxRequestBodyBytes)
	if err := decodeJSONStrict(r, &req); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	result, err := a.deps.AssistantService.SendSessionMessage(r.Context(), assistantmodule.SendSessionMessageCommand{
		StudentID: studentID.String(), SessionID: r.PathValue("sessionID"), ClientMessageID: req.ClientMessageID, Text: req.Text, InputMode: req.InputMode,
	})
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, result)
}

func speechNoStore(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Pragma", "no-cache")
		next.ServeHTTP(w, r)
	})
}

func (a *API) speechAuthorization(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Pragma", "no-cache")
	if !a.assistantEnabled(w) {
		return
	}
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	result, err := a.deps.AssistantService.SpeechAuthorization(r.Context(), studentID.String(), r.PathValue("sessionID"), r.PathValue("messageID"))
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (a *API) deleteAssistantSession(w http.ResponseWriter, r *http.Request) {
	if !a.assistantEnabled(w) {
		return
	}
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	if err := a.deps.AssistantService.DeleteSession(r.Context(), studentID.String(), r.PathValue("sessionID")); err != nil {
		httpx.JSONError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) assistantEnabled(w http.ResponseWriter) bool {
	if a.deps.AssistantService != nil && a.deps.AssistantService.Enabled() {
		return true
	}
	httpx.JSONError(w, apperrors.NotFound("assistant_disabled", "assistant is not enabled"))
	return false
}

func assistantPageLimit(r *http.Request) (int, error) {
	raw := strings.TrimSpace(r.URL.Query().Get("limit"))
	if raw == "" {
		return assistantmodule.DefaultSessionPageSize, nil
	}
	limit, err := strconv.Atoi(raw)
	if err != nil || limit < 1 {
		return 0, apperrors.BadRequest("assistant_limit_invalid", "limit must be a positive integer")
	}
	return limit, nil
}

func (a *API) sendHomeworkDigest(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	req, err := decodeSendHomeworkDigestRequest(r)
	if err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	idempotencyKey := strings.TrimSpace(r.Header.Get("X-Idempotency-Key"))
	if idempotencyKey == "" {
		idempotencyKey = "wh-homework-" + studentID.String() + "-" + strings.ReplaceAll(req.Date, "-", "")
	}
	mode := strings.TrimSpace(strings.ToLower(req.Mode))
	if mode == "" {
		mode = strings.TrimSpace(strings.ToLower(r.URL.Query().Get("mode")))
	}
	if mode == "" {
		mode = "homework"
	}
	date := strings.TrimSpace(req.Date)
	if date == "" {
		date = strings.TrimSpace(r.URL.Query().Get("date"))
	}
	if date == "" {
		date = time.Now().UTC().Format("2006-01-02")
	}
	sendDate, parseErr := time.Parse("2006-01-02", date)
	if parseErr != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_date", "date must be in YYYY-MM-DD format"))
		return
	}
	digestText, err := a.deps.AcademicService.BuildHomeworkDigest(
		r.Context(),
		studentID,
		sendDate,
		mode,
	)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("digest_build_failed", "failed to build homework digest", err))
		return
	}
	parentPhones, err := loadParentPhonesForStudent(r.Context(), a.deps.Pool, studentID)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	jobID, created, err := a.deps.WhatsAppService.SendHomeworkDigestWithMessage(
		r.Context(),
		studentID.String(),
		date,
		mode,
		digestText,
		idempotencyKey,
		parentPhones,
	)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusAccepted, map[string]any{
		"job_id":  jobID,
		"created": created,
		"status":  "queued",
	})
}

func decodeSendHomeworkDigestRequest(r *http.Request) (contracts.SendHomeworkDigestRequest, error) {
	var req contracts.SendHomeworkDigestRequest
	body, err := io.ReadAll(r.Body)
	if err != nil {
		return req, err
	}
	trimmedBody := bytes.TrimSpace(body)
	if len(trimmedBody) == 0 {
		return req, nil
	}

	r.Body = io.NopCloser(bytes.NewReader(body))
	if err := decodeJSONStrict(r, &req); err == nil {
		return req, nil
	}

	// Transitional fallback for runtimes that send urlencoded payloads.
	if formValues, parseErr := url.ParseQuery(string(trimmedBody)); parseErr == nil && len(formValues) > 0 {
		req.Date = strings.TrimSpace(formValues.Get("date"))
		req.Mode = strings.TrimSpace(formValues.Get("mode"))
		return req, nil
	}

	// Transitional fallback for runtimes that still post a reduced JSON payload.
	var raw map[string]any
	if err := json.Unmarshal(trimmedBody, &raw); err != nil {
		return contracts.SendHomeworkDigestRequest{}, err
	}
	if date, ok := raw["date"].(string); ok {
		req.Date = strings.TrimSpace(date)
	}
	if mode, ok := raw["mode"].(string); ok {
		req.Mode = strings.TrimSpace(mode)
	}
	return req, nil
}

func (a *API) sendHomeworkPhoto(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	var req contracts.SendHomeworkPhotoRequest
	if err := decodeJSONStrict(r, &req); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	photoPayload := strings.TrimSpace(req.FileBase64)
	if photoPayload == "" {
		httpx.JSONError(w, apperrors.BadRequest("photo_required", "photo payload is required"))
		return
	}
	photoBytes, err := base64.StdEncoding.DecodeString(photoPayload)
	if err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_photo_payload", "file_base64 is not valid base64"))
		return
	}
	if len(photoBytes) == 0 {
		httpx.JSONError(w, apperrors.BadRequest("invalid_photo_payload", "file_base64 is empty"))
		return
	}
	idempotencyKey := strings.TrimSpace(r.Header.Get("X-Idempotency-Key"))
	if idempotencyKey == "" {
		idempotencyKey = "wh-photo-" + studentID.String() + "-" + req.HomeworkID
	}
	objectKey, err := storeHomeworkPhotoObject(studentID.String(), req.FileName, idempotencyKey, photoBytes)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("photo_temp_store_failed", "failed to persist temporary homework photo", err))
		return
	}
	jobID, created, err := a.deps.WhatsAppService.SendHomeworkPhoto(
		r.Context(),
		studentID.String(),
		req.HomeworkID,
		req.FileName,
		objectKey,
		req.Caption,
		idempotencyKey,
		req.ParentPhones,
	)
	if err != nil {
		_ = removeHomeworkPhotoObject(objectKey)
		httpx.JSONError(w, err)
		return
	}
	httpx.JSON(w, http.StatusAccepted, map[string]any{
		"job_id":  jobID,
		"created": created,
		"status":  "queued",
	})
}

func (a *API) whatsappJobStatus(w http.ResponseWriter, r *http.Request) {
	jobID := strings.TrimSpace(r.PathValue("jobID"))
	record, err := a.deps.JobsService.GetStatus(r.Context(), jobID)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	if record == nil {
		httpx.JSONError(w, apperrors.NotFound("job_not_found", "job was not found"))
		return
	}
	dispatchStatus := "queued"
	switch record.Status {
	case "succeeded":
		dispatchStatus = "sent"
	case "failed", "dead_letter":
		dispatchStatus = "failed"
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"job_id":       record.ID,
		"job_status":   record.Status,
		"status":       dispatchStatus,
		"attempts":     record.Attempts,
		"max_attempts": record.MaxAttempts,
		"last_error":   strings.TrimSpace(record.LastError),
		"finished_at":  record.FinishedAt.UTC().Format(time.RFC3339Nano),
	})
}

func storeHomeworkPhotoObject(studentID, fileName, idempotencyKey string, data []byte) (string, error) {
	safeName := sanitizeHomeworkPhotoFileName(fileName)
	objectName := strings.TrimSpace(idempotencyKey)
	objectName = strings.NewReplacer("/", "_", "\\", "_", ":", "_", "..", "_").Replace(objectName)
	if objectName == "" {
		objectName = uuid.NewString()
	}
	fileNameWithMeta := studentID + "-" + objectName + "-" + safeName
	attemptErrors := make([]string, 0, 4)
	for _, rootDir := range homeworkPhotoTempRoots() {
		trimmedRoot := strings.TrimSpace(rootDir)
		if trimmedRoot == "" {
			continue
		}
		if err := os.MkdirAll(trimmedRoot, 0o700); err != nil {
			attemptErrors = append(attemptErrors, trimmedRoot+": mkdir failed: "+err.Error())
			continue
		}
		targetPath := filepath.Join(trimmedRoot, fileNameWithMeta)
		if err := os.WriteFile(targetPath, data, 0o600); err != nil {
			attemptErrors = append(attemptErrors, targetPath+": write failed: "+err.Error())
			continue
		}
		return "file://" + targetPath, nil
	}
	if tempPath, err := writeHomeworkPhotoTempFile(safeName, data); err == nil {
		return "file://" + tempPath, nil
	} else {
		attemptErrors = append(attemptErrors, "os.CreateTemp fallback failed: "+err.Error())
	}
	if len(attemptErrors) == 0 {
		return "", errors.New("no writable temporary directory configured")
	}
	return "", errors.New(strings.Join(attemptErrors, "; "))
}

func writeHomeworkPhotoTempFile(fileName string, data []byte) (string, error) {
	extension := filepath.Ext(strings.TrimSpace(fileName))
	if extension == "" {
		extension = ".jpg"
	}
	tempFile, err := os.CreateTemp("", "kundi-homework-photo-*"+extension)
	if err != nil {
		return "", err
	}
	path := tempFile.Name()
	if _, err := tempFile.Write(data); err != nil {
		_ = tempFile.Close()
		_ = os.Remove(path)
		return "", err
	}
	if err := tempFile.Close(); err != nil {
		_ = os.Remove(path)
		return "", err
	}
	return path, nil
}

func removeHomeworkPhotoObject(objectKey string) error {
	trimmed := strings.TrimSpace(objectKey)
	const prefix = "file://"
	if !strings.HasPrefix(trimmed, prefix) {
		return nil
	}
	path := strings.TrimSpace(strings.TrimPrefix(trimmed, prefix))
	if path == "" {
		return nil
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func sanitizeHomeworkPhotoFileName(fileName string) string {
	trimmed := strings.TrimSpace(fileName)
	if trimmed == "" {
		return "homework.jpg"
	}
	base := filepath.Base(trimmed)
	base = strings.ReplaceAll(base, "\\", "_")
	base = strings.ReplaceAll(base, "/", "_")
	if !strings.Contains(base, ".") {
		base += ".jpg"
	}
	return base
}

func homeworkPhotoTempRoots() []string {
	candidates := make([]string, 0, 6)
	if configured := strings.TrimSpace(os.Getenv("KUNDI_HOMEWORK_PHOTO_TMP_DIR")); configured != "" {
		candidates = append(candidates, configured)
	}
	if tempDir := strings.TrimSpace(os.TempDir()); tempDir != "" {
		candidates = append(candidates, filepath.Join(tempDir, "kundi-homework-photo"))
	}
	if homeDir, err := os.UserHomeDir(); err == nil {
		trimmedHome := strings.TrimSpace(homeDir)
		if trimmedHome != "" {
			candidates = append(candidates, filepath.Join(trimmedHome, ".kundi", "homework-photo-tmp"))
		}
	}
	if runtimeDir := strings.TrimSpace(os.Getenv("KUNDI_RUNTIME_DIR")); runtimeDir != "" {
		candidates = append(candidates, filepath.Join(runtimeDir, "homework-photo-tmp"))
	}
	candidates = append(candidates, filepath.Join(".", "runtime-tmp", "homework-photo"))
	return dedupeNonEmptyPaths(candidates)
}

func dedupeNonEmptyPaths(paths []string) []string {
	if len(paths) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(paths))
	out := make([]string, 0, len(paths))
	for _, raw := range paths {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			continue
		}
		normalized := filepath.Clean(trimmed)
		if _, exists := seen[normalized]; exists {
			continue
		}
		seen[normalized] = struct{}{}
		out = append(out, normalized)
	}
	return out
}

func (a *API) updateLocalAppProfile(w http.ResponseWriter, r *http.Request) {
	studentID, err := studentIDFromRequest(r)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	var req contracts.UpdateLocalAppProfileRequest
	if err := decodeJSONStrict(r, &req); err != nil {
		httpx.JSONError(w, apperrors.BadRequest("invalid_json", "request body is not valid JSON"))
		return
	}
	if req.Shift == nil || (*req.Shift != 1 && *req.Shift != 2) {
		httpx.JSONError(w, apperrors.BadRequest("invalid_shift", "shift must be 1 or 2"))
		return
	}
	normalizedParent1, err := normalizeParentPhone(req.ParentPhone1, true)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	normalizedParent2, err := normalizeParentPhone(req.ParentPhone2, false)
	if err != nil {
		httpx.JSONError(w, err)
		return
	}
	_, err = a.deps.Pool.Exec(
		r.Context(),
		`
		INSERT INTO student_app_profiles(student_id, shift, parent_phone_1, parent_phone_2, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (student_id) DO UPDATE
		SET shift = EXCLUDED.shift,
		    parent_phone_1 = EXCLUDED.parent_phone_1,
		    parent_phone_2 = EXCLUDED.parent_phone_2,
		    updated_at = NOW()
		`,
		studentID,
		*req.Shift,
		normalizedParent1,
		normalizedParent2,
	)
	if err != nil {
		httpx.JSONError(w, apperrors.Internal("profile_local_update_failed", "failed to update local profile", err))
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"shift":          *req.Shift,
		"parent_phone_1": normalizedParent1,
		"parent_phone_2": normalizedParent2,
	})
}

func authCommandFromLoginRequest(req contracts.LoginRequest, r *http.Request) authmodule.LoginCommand {
	return authmodule.LoginCommand{
		Source:    req.Source,
		Login:     req.Login,
		Password:  req.Password,
		UserAgent: strings.TrimSpace(r.UserAgent()),
		IPAddress: clientIP(r),
	}
}

func studentIDFromRequest(r *http.Request) (uuid.UUID, error) {
	studentIDRaw, ok := platformauth.StudentIDFromContext(r.Context())
	if !ok {
		return uuid.Nil, apperrors.Unauthorized("unauthorized", "missing authorization context")
	}
	studentID, err := uuid.Parse(studentIDRaw)
	if err != nil {
		return uuid.Nil, apperrors.Unauthorized("unauthorized", "invalid authorization context")
	}
	return studentID, nil
}

func clientIP(r *http.Request) string {
	forwarded := strings.TrimSpace(r.Header.Get("X-Forwarded-For"))
	if forwarded != "" {
		parts := strings.Split(forwarded, ",")
		return strings.TrimSpace(parts[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func decodeJSONStrict(r *http.Request, out any) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(out); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return apperrors.BadRequest("invalid_json", "request body must contain exactly one JSON object")
	}
	return nil
}

func readWindowFromRequest(r *http.Request) (academic.ReadWindowV2, error) {
	query := r.URL.Query()
	window := academic.DefaultReadWindowV2(query.Get("provider"), time.Now().UTC())
	snapshotRaw := strings.TrimSpace(query.Get("snapshot_at"))
	if snapshotRaw != "" {
		snapshotAt, err := time.Parse(time.RFC3339Nano, snapshotRaw)
		if err != nil {
			return academic.ReadWindowV2{}, apperrors.BadRequest("invalid_snapshot_at", "snapshot_at must match RFC3339")
		}
		window.SnapshotAt = snapshotAt.UTC()
	}

	fromRaw := strings.TrimSpace(query.Get("window_from"))
	if fromRaw != "" {
		from, err := time.Parse("2006-01-02", fromRaw)
		if err != nil {
			return academic.ReadWindowV2{}, apperrors.BadRequest("invalid_window_from", "window_from must match YYYY-MM-DD")
		}
		window.WindowFrom = from.UTC()
	}

	toRaw := strings.TrimSpace(query.Get("window_to"))
	if toRaw != "" {
		to, err := time.Parse("2006-01-02", toRaw)
		if err != nil {
			return academic.ReadWindowV2{}, apperrors.BadRequest("invalid_window_to", "window_to must match YYYY-MM-DD")
		}
		window.WindowTo = to.UTC()
	}
	if window.WindowTo.Before(window.WindowFrom) {
		return academic.ReadWindowV2{}, apperrors.BadRequest("invalid_window_range", "window_to must be greater or equal to window_from")
	}
	return window, nil
}

var _nonDigitPhoneChars = regexp.MustCompile(`[^\d+]`)

func normalizeParentPhone(raw string, required bool) (string, error) {
	value := strings.TrimSpace(raw)
	if value == "" {
		if required {
			return "", apperrors.BadRequest("parent_phone_1_required", "parent_phone_1 is required")
		}
		return "", nil
	}
	value = strings.ReplaceAll(value, " ", "")
	value = strings.ReplaceAll(value, "-", "")
	value = strings.ReplaceAll(value, "(", "")
	value = strings.ReplaceAll(value, ")", "")
	value = _nonDigitPhoneChars.ReplaceAllString(value, "")
	if strings.Count(value, "+") > 1 || (strings.Contains(value, "+") && !strings.HasPrefix(value, "+")) {
		return "", apperrors.BadRequest("invalid_parent_phone", "phone number format is invalid")
	}
	digits := strings.TrimPrefix(value, "+")
	if len(digits) < 10 || len(digits) > 15 {
		return "", apperrors.BadRequest("invalid_parent_phone", "phone number must contain 10 to 15 digits")
	}
	if strings.HasPrefix(value, "+") {
		return "+" + digits, nil
	}
	return digits, nil
}

func loadParentPhonesForStudent(ctx context.Context, pool *pgxpool.Pool, studentID uuid.UUID) ([]string, error) {
	if pool == nil {
		return nil, apperrors.Internal("db_unavailable", "database is unavailable", errors.New("pool is nil"))
	}
	var parent1 string
	var parent2 string
	if err := pool.QueryRow(ctx, `
		SELECT COALESCE(parent_phone_1, ''), COALESCE(parent_phone_2, '')
		FROM student_app_profiles
		WHERE student_id = $1
	`, studentID).Scan(&parent1, &parent2); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, apperrors.BadRequest("parent_phone_1_required", "parent_phone_1 is required")
		}
		return nil, apperrors.Internal("profile_lookup_failed", "failed to load local profile", err)
	}

	normalized1, err := normalizeParentPhone(parent1, true)
	if err != nil {
		return nil, err
	}
	normalized2, err := normalizeParentPhone(parent2, false)
	if err != nil {
		return nil, err
	}

	result := []string{normalized1}
	if normalized2 != "" && normalized2 != normalized1 {
		result = append(result, normalized2)
	}
	return result, nil
}
