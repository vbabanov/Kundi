package assistant

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/modules/assistant/llm"
	"github.com/kundi/kundi/backend/internal/modules/assistant/safety"
	"github.com/kundi/kundi/backend/internal/modules/assistant/tutoring"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

const (
	DefaultSessionPageSize = 20
	MaximumSessionPageSize = 50
	SessionHistoryLimit    = 20
)

type SessionPage struct {
	Items      []AssistantSession `json:"items"`
	NextCursor string             `json:"next_cursor,omitempty"`
}

type MessagePage struct {
	Items      []SessionMessage `json:"items"`
	NextCursor string           `json:"next_cursor,omitempty"`
}

type SendSessionMessageCommand struct {
	StudentID       string
	SessionID       string
	ClientMessageID string
	Text            string
}

type SessionMessageResult struct {
	UserMessage      SessionMessage `json:"user_message"`
	AssistantMessage SessionMessage `json:"assistant_message"`
	ResponseMode     string         `json:"response_mode"`
	HelpLevel        string         `json:"help_level"`
	FollowUpQuestion string         `json:"follow_up_question,omitempty"`
	Emotion          string         `json:"emotion"`
	AnimationCue     string         `json:"animation_cue"`
	Suggestions      []string       `json:"suggestions"`
}

func (s *Service) CreateSession(ctx context.Context, studentIDRaw string) (AssistantSession, error) {
	studentID, err := s.sessionStudentID(studentIDRaw)
	if err != nil {
		return AssistantSession{}, err
	}
	profile, err := s.sessions.StudentProfile(ctx, studentID)
	if err != nil {
		return AssistantSession{}, apperrors.Internal("assistant_profile_load_failed", "failed to load assistant profile", err)
	}
	locale := strings.TrimSpace(profile.Locale)
	if locale == "" {
		locale = "ru-KZ"
	}
	if profile.GradeLevel < 1 || profile.GradeLevel > 12 {
		return AssistantSession{}, apperrors.Internal("assistant_profile_invalid", "assistant profile is invalid", errors.New("grade level is outside supported range"))
	}
	item, err := s.sessions.CreateSession(ctx, studentID, locale, profile.GradeLevel)
	if err != nil {
		return AssistantSession{}, apperrors.Internal("assistant_session_create_failed", "failed to create assistant session", err)
	}
	return item, nil
}

func (s *Service) ListSessions(ctx context.Context, studentIDRaw string, limit int, cursorRaw string) (SessionPage, error) {
	studentID, err := s.sessionStudentID(studentIDRaw)
	if err != nil {
		return SessionPage{}, err
	}
	limit = boundedPageSize(limit)
	cursor, err := decodePageCursor(cursorRaw)
	if err != nil {
		return SessionPage{}, apperrors.BadRequest("assistant_cursor_invalid", "cursor is invalid")
	}
	items, err := s.sessions.ListSessions(ctx, studentID, limit+1, cursor)
	if err != nil {
		return SessionPage{}, apperrors.Internal("assistant_sessions_load_failed", "failed to load assistant sessions", err)
	}
	page := SessionPage{Items: items}
	if len(items) > limit {
		page.Items = items[:limit]
		last := page.Items[len(page.Items)-1]
		page.NextCursor = encodePageCursor(last.LastMessageAt, last.ID)
	}
	return page, nil
}

func (s *Service) ListSessionMessages(ctx context.Context, studentIDRaw, sessionIDRaw string, limit int, cursorRaw string) (MessagePage, error) {
	studentID, sessionID, err := s.sessionIDs(studentIDRaw, sessionIDRaw)
	if err != nil {
		return MessagePage{}, err
	}
	limit = boundedPageSize(limit)
	cursor, err := decodePageCursor(cursorRaw)
	if err != nil {
		return MessagePage{}, apperrors.BadRequest("assistant_cursor_invalid", "cursor is invalid")
	}
	items, err := s.sessions.ListMessages(ctx, studentID, sessionID, limit+1, cursor)
	if errors.Is(err, ErrSessionNotFound) {
		return MessagePage{}, apperrors.NotFound("assistant_session_not_found", "assistant session was not found")
	}
	if err != nil {
		return MessagePage{}, apperrors.Internal("assistant_messages_load_failed", "failed to load assistant messages", err)
	}
	page := MessagePage{Items: items}
	if len(items) > limit {
		page.Items = items[:limit]
		last := page.Items[len(page.Items)-1]
		page.NextCursor = encodePageCursor(last.CreatedAt, last.ID)
	}
	return page, nil
}

func (s *Service) DeleteSession(ctx context.Context, studentIDRaw, sessionIDRaw string) error {
	studentID, sessionID, err := s.sessionIDs(studentIDRaw, sessionIDRaw)
	if err != nil {
		return err
	}
	err = s.sessions.DeleteSession(ctx, studentID, sessionID)
	if errors.Is(err, ErrSessionNotFound) {
		return apperrors.NotFound("assistant_session_not_found", "assistant session was not found")
	}
	if err != nil {
		return apperrors.Internal("assistant_session_delete_failed", "failed to delete assistant session", err)
	}
	return nil
}

func (s *Service) SendSessionMessage(ctx context.Context, cmd SendSessionMessageCommand) (SessionMessageResult, error) {
	startedAt := time.Now()
	studentID, sessionID, err := s.sessionIDs(cmd.StudentID, cmd.SessionID)
	if err != nil {
		return SessionMessageResult{}, err
	}
	clientMessageID, err := uuid.Parse(strings.TrimSpace(cmd.ClientMessageID))
	if err != nil {
		return SessionMessageResult{}, apperrors.BadRequest("assistant_client_message_id_invalid", "client_message_id must be a UUID")
	}

	existing, found, err := s.sessions.FindExchange(ctx, studentID, sessionID, clientMessageID)
	if errors.Is(err, ErrSessionNotFound) {
		return SessionMessageResult{}, apperrors.NotFound("assistant_session_not_found", "assistant session was not found")
	}
	if err != nil {
		return SessionMessageResult{}, apperrors.Internal("assistant_idempotency_lookup_failed", "failed to check assistant message", err)
	}
	if found {
		return resultFromExchange(existing, nil, "", ""), nil
	}

	session, err := s.sessions.GetSession(ctx, studentID, sessionID)
	if errors.Is(err, ErrSessionNotFound) {
		return SessionMessageResult{}, apperrors.NotFound("assistant_session_not_found", "assistant session was not found")
	}
	if err != nil {
		return SessionMessageResult{}, apperrors.Internal("assistant_session_load_failed", "failed to load assistant session", err)
	}

	historyItems, err := s.sessions.ListMessages(ctx, studentID, sessionID, SessionHistoryLimit, nil)
	if err != nil {
		return SessionMessageResult{}, apperrors.Internal("assistant_history_load_failed", "failed to load assistant history", err)
	}
	history := make([]safety.HistoryMessage, 0, len(historyItems))
	for i := len(historyItems) - 1; i >= 0; i-- {
		history = append(history, safety.HistoryMessage{Role: historyItems[i].Role, Text: historyItems[i].Content})
	}
	validated, err := s.validator.Validate(safety.Input{Mode: string(ModeTutor), GradeLevel: session.GradeLevel, Text: cmd.Text, History: history})
	if err != nil {
		return SessionMessageResult{}, validationAppError(err)
	}
	if !s.rateLimiter.Allow(studentID.String()).Allowed {
		return SessionMessageResult{}, apperrors.New(http.StatusTooManyRequests, "assistant_rate_limited", s.safeResponses.ForRateLimit(safety.DetectLanguage(validated.Text)).Text, nil)
	}

	language := safety.DetectLanguage(validated.Text)
	inputSafety, err := s.moderator.Moderate(ctx, validated.Text)
	if err != nil {
		return SessionMessageResult{}, apperrors.New(http.StatusServiceUnavailable, "assistant_safety_unavailable", "assistant safety check is temporarily unavailable", nil)
	}
	if !inputSafety.Allowed {
		safe := s.safeResponses.ForModeration(inputSafety)
		analysis := tutoring.Analysis{Intent: tutoring.IntentGeneralQuestion, ResponseMode: tutoring.ResponseModeSafety, HelpLevel: "safety", GradeBand: tutoring.GradeBand(session.GradeLevel)}
		return s.persistSessionDraft(ctx, studentID, sessionID, clientMessageID, validated.Text, tutoring.TutorResponseDraft{Answer: safe.Text, ResponseMode: tutoring.ResponseModeSafety, HelpLevel: "safety", Emotion: "neutral", AnimationCue: "standing"}, analysis, "", "", string(inputSafety.Category), nil)
	}

	academic := AcademicContext{Locale: session.Locale, GradeLevel: session.GradeLevel}
	contextFailed := false
	if s.academic != nil {
		loaded, contextErr := s.academic.Build(ctx, studentID)
		if contextErr != nil {
			contextFailed = true
			s.logger.Warn("assistant_academic_context_degraded", slog.String("student_id", studentID.String()), slog.String("error_code", "academic_context_load_failed"))
		} else {
			academic = loaded
		}
	}
	activeHomework := academic.MatchesActiveHomework(validated.Text) || tutoring.LooksLikeHomework(validated.Text)
	analysis := s.tutoring.Analyze(inputSafety.SanitizedText, session.GradeLevel, activeHomework)
	prompt := s.tutoring.BuildPrompt(inputSafety.SanitizedText, session.GradeLevel, analysis, academic.Render(), renderSessionHistory(history))

	llmCtx, cancel := context.WithTimeout(ctx, s.llmTimeout)
	providerResponse, providerErr := s.llm.Generate(llmCtx, llm.Request{Mode: string(ModeTutor), Prompt: prompt, PersonaTone: "supportive", Style: "age_adapted"})
	cancel()
	if providerErr != nil || strings.TrimSpace(providerResponse.Text) == "" {
		s.logSessionEvent(startedAt, studentID.String(), sessionID.String(), analysis, contextFailed, "provider_failed")
		return SessionMessageResult{}, sessionProviderError(providerErr)
	}

	outputSafety, err := s.output.Validate(ctx, providerResponse.Text)
	if err != nil {
		return SessionMessageResult{}, apperrors.New(http.StatusServiceUnavailable, "assistant_safety_unavailable", "assistant safety check is temporarily unavailable", nil)
	}
	raw := providerResponse.Text
	safetyCategory := ""
	if !outputSafety.Allowed {
		safe := s.safeResponses.ForModeration(outputSafety)
		raw = safe.Text
		safetyCategory = string(outputSafety.Category)
	}
	draft := s.tutoring.Finalize(raw, analysis, string(language))
	if !outputSafety.Allowed {
		draft.ResponseMode = tutoring.ResponseModeSafety
		draft.HelpLevel = "safety"
	}
	result, err := s.persistSessionDraft(ctx, studentID, sessionID, clientMessageID, validated.Text, draft, analysis, providerResponse.Provider, providerResponse.Model, safetyCategory, academic.Suggestions())
	if err == nil {
		s.logSessionEvent(startedAt, studentID.String(), sessionID.String(), analysis, contextFailed, "ok")
	}
	return result, err
}

func (s *Service) persistSessionDraft(ctx context.Context, studentID, sessionID, clientMessageID uuid.UUID, userText string, draft tutoring.TutorResponseDraft, analysis tutoring.Analysis, provider, model, category string, suggestions []string) (SessionMessageResult, error) {
	policy, _ := json.Marshal(map[string]any{"intent": analysis.Intent, "help_level": draft.HelpLevel, "ready_answer_risk": draft.ReadyAnswerRisk, "active_homework": analysis.ActiveHomework, "grade_band": analysis.GradeBand})
	exchange, err := s.sessions.SaveExchange(ctx, studentID, sessionID, clientMessageID, userText, SessionMessage{Content: draft.Answer, Provider: provider, Model: model, ResponseMode: string(draft.ResponseMode), TutoringPolicy: policy, SafetyCategory: category})
	if err != nil {
		return SessionMessageResult{}, apperrors.Internal("assistant_message_save_failed", "failed to save assistant message", err)
	}
	return resultFromExchange(exchange, suggestions, draft.HelpLevel, draft.FollowUpQuestion), nil
}

func resultFromExchange(exchange StoredExchange, suggestions []string, helpLevel, followUp string) SessionMessageResult {
	if suggestions == nil {
		suggestions = []string{}
	}
	return SessionMessageResult{UserMessage: exchange.User, AssistantMessage: exchange.Assistant, ResponseMode: exchange.Assistant.ResponseMode, HelpLevel: helpLevel, FollowUpQuestion: followUp, Emotion: "neutral", AnimationCue: "standing", Suggestions: suggestions}
}

func (s *Service) sessionStudentID(raw string) (uuid.UUID, error) {
	if !s.Enabled() {
		return uuid.Nil, apperrors.NotFound("assistant_disabled", "assistant is not enabled")
	}
	if s.sessions == nil {
		return uuid.Nil, apperrors.Internal("assistant_storage_unavailable", "assistant storage is unavailable", errors.New("session repository is nil"))
	}
	id, err := uuid.Parse(strings.TrimSpace(raw))
	if err != nil {
		return uuid.Nil, apperrors.Unauthorized("unauthorized", "invalid authorization context")
	}
	return id, nil
}

func (s *Service) sessionIDs(studentRaw, sessionRaw string) (uuid.UUID, uuid.UUID, error) {
	studentID, err := s.sessionStudentID(studentRaw)
	if err != nil {
		return uuid.Nil, uuid.Nil, err
	}
	sessionID, err := uuid.Parse(strings.TrimSpace(sessionRaw))
	if err != nil {
		return uuid.Nil, uuid.Nil, apperrors.BadRequest("assistant_session_id_invalid", "session id is invalid")
	}
	return studentID, sessionID, nil
}

func validationAppError(err error) error {
	var validationErr *safety.ValidationError
	if errors.As(err, &validationErr) {
		return apperrors.BadRequest(validationErr.Code, validationErr.Message)
	}
	return apperrors.BadRequest("assistant_input_invalid", "assistant input is invalid")
}

func sessionProviderError(err error) error {
	var providerErr *llm.ProviderError
	if errors.As(err, &providerErr) {
		switch providerErr.Kind {
		case llm.ErrorRateLimit:
			return apperrors.New(http.StatusTooManyRequests, "assistant_provider_rate_limited", "assistant provider is temporarily rate limited", nil)
		case llm.ErrorClient, llm.ErrorMalformed:
			return apperrors.New(http.StatusBadGateway, "assistant_provider_invalid_response", "assistant provider returned an invalid response", nil)
		}
	}
	return apperrors.New(http.StatusServiceUnavailable, "assistant_provider_unavailable", "assistant provider is temporarily unavailable", nil)
}

func renderSessionHistory(items []safety.HistoryMessage) string {
	parts := make([]string, 0, len(items))
	for _, item := range items {
		parts = append(parts, strings.ToUpper(item.Role)+": "+item.Text)
	}
	return boundContext(strings.Join(parts, "\n"), safety.DefaultMaxHistoryRunes)
}

func boundedPageSize(limit int) int {
	if limit <= 0 {
		return DefaultSessionPageSize
	}
	if limit > MaximumSessionPageSize {
		return MaximumSessionPageSize
	}
	return limit
}

type encodedCursor struct {
	At time.Time `json:"at"`
	ID string    `json:"id"`
}

func encodePageCursor(at time.Time, id string) string {
	raw, _ := json.Marshal(encodedCursor{At: at.UTC(), ID: id})
	return base64.RawURLEncoding.EncodeToString(raw)
}

func decodePageCursor(raw string) (*PageCursor, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, nil
	}
	decoded, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(raw))
	if err != nil {
		return nil, err
	}
	var cursor encodedCursor
	if err := json.Unmarshal(decoded, &cursor); err != nil {
		return nil, err
	}
	id, err := uuid.Parse(cursor.ID)
	if err != nil || cursor.At.IsZero() {
		return nil, errors.New("invalid cursor")
	}
	return &PageCursor{At: cursor.At.UTC(), ID: id}, nil
}

func (s *Service) logSessionEvent(started time.Time, studentID, sessionID string, analysis tutoring.Analysis, contextFailed bool, result string) {
	s.logger.Info("assistant_session_message", slog.String("student_id", studentID), slog.String("session_id", sessionID), slog.String("intent", string(analysis.Intent)), slog.String("response_mode", string(analysis.ResponseMode)), slog.Bool("academic_context_degraded", contextFailed), slog.String("result", result), slog.Int64("latency_ms", time.Since(started).Milliseconds()))
}
