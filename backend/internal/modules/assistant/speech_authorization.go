package assistant

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/kundi/kundi/backend/internal/modules/assistant/speechauth"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
)

const MaxSpeechMessageRunes = 16000

// A separate read-only interface keeps Phase 2A persistence unchanged.
type SpeechMessageRepository interface {
	SpeechMessage(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) (SessionMessage, string, error)
}

func (r *PostgresSessionRepository) SpeechMessage(ctx context.Context, studentID, sessionID, messageID uuid.UUID) (SessionMessage, string, error) {
	var m SessionMessage
	var inputMode string
	err := r.pool.QueryRow(ctx, `
  SELECT a.id::text,a.session_id::text,a.role,a.content,u.input_mode
  FROM assistant_sessions s
  JOIN assistant_messages a ON a.session_id=s.id AND a.student_id=s.student_id
  JOIN assistant_messages u ON u.session_id=a.session_id AND u.student_id=a.student_id
    AND u.client_message_id=a.client_message_id AND u.role='user'
  WHERE s.id=$1 AND s.student_id=$2 AND a.id=$3 AND a.role='assistant'
 `, sessionID, studentID, messageID).Scan(&m.ID, &m.SessionID, &m.Role, &m.Content, &inputMode)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrSessionNotFound
	}
	return m, inputMode, err
}

func (s *Service) SpeechAuthorization(ctx context.Context, studentRaw, sessionRaw, messageRaw string) (speechauth.Authorization, error) {
	if !s.Enabled() || !s.voiceEnabled || s.speechBroker == nil || !s.speechBroker.Enabled() {
		return speechauth.Authorization{}, apperrors.NotFound("assistant_tts_disabled", "speech is not enabled")
	}
	student, session, err := s.sessionIDs(studentRaw, sessionRaw)
	if err != nil {
		return speechauth.Authorization{}, err
	}
	message, err := uuid.Parse(messageRaw)
	if err != nil {
		return speechauth.Authorization{}, apperrors.BadRequest("assistant_message_id_invalid", "message id must be a UUID")
	}
	if !s.speechBroker.AllowRequest(student.String()) {
		return speechauth.Authorization{}, apperrors.New(429, "speech_rate_limited", "speech authorization rate limited", nil)
	}
	stored, err := s.sessions.GetSession(ctx, student, session)
	if errors.Is(err, ErrSessionNotFound) {
		return speechauth.Authorization{}, apperrors.NotFound("assistant_message_not_found", "message not found")
	}
	if err != nil {
		return speechauth.Authorization{}, apperrors.New(503, "speech_message_unavailable", "message unavailable", nil)
	}
	repo, ok := s.sessions.(SpeechMessageRepository)
	if !ok {
		return speechauth.Authorization{}, apperrors.New(503, "speech_message_unavailable", "message unavailable", nil)
	}
	m, inputMode, err := repo.SpeechMessage(ctx, student, session, message)
	if errors.Is(err, ErrSessionNotFound) || (err == nil && (m.ID != message.String() || m.SessionID != session.String() || m.Role != "assistant" || inputMode != InputModeVoice)) {
		return speechauth.Authorization{}, apperrors.NotFound("assistant_message_not_found", "message not found")
	}
	if err != nil {
		return speechauth.Authorization{}, apperrors.New(503, "speech_message_unavailable", "message unavailable", nil)
	}
	if strings.TrimSpace(m.Content) == "" || utf8.RuneCountInString(m.Content) > MaxSpeechMessageRunes {
		return speechauth.Authorization{}, apperrors.BadRequest("speech_content_invalid", "message cannot be synthesized")
	}
	hash := sha256.Sum256([]byte(m.Content))
	return s.speechBroker.Authorize(ctx, student.String(), message.String(), stored.Locale, hex.EncodeToString(hash[:]))
}
