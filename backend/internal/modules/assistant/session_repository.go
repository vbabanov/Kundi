package assistant

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrSessionNotFound = errors.New("assistant session not found")

type StudentAssistantProfile struct {
	Locale     string
	GradeLevel int
}

type AssistantSession struct {
	ID            string    `json:"id"`
	Locale        string    `json:"locale"`
	GradeLevel    int       `json:"grade_level"`
	Title         string    `json:"title"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
	LastMessageAt time.Time `json:"last_message_at"`
}

type SessionMessage struct {
	ID           string    `json:"id"`
	SessionID    string    `json:"session_id"`
	Role         string    `json:"role"`
	Content      string    `json:"content"`
	InputMode    string    `json:"input_mode"`
	ResponseMode string    `json:"response_mode,omitempty"`
	CreatedAt    time.Time `json:"created_at"`

	ClientMessageID string          `json:"-"`
	Provider        string          `json:"-"`
	Model           string          `json:"-"`
	TutoringPolicy  json.RawMessage `json:"-"`
	SafetyCategory  string          `json:"-"`
}

type PageCursor struct {
	At time.Time
	ID uuid.UUID
}

type StoredExchange struct {
	User      SessionMessage
	Assistant SessionMessage
}

type SessionRepository interface {
	StudentProfile(ctx context.Context, studentID uuid.UUID) (StudentAssistantProfile, error)
	CreateSession(ctx context.Context, studentID uuid.UUID, locale string, gradeLevel int) (AssistantSession, error)
	GetSession(ctx context.Context, studentID, sessionID uuid.UUID) (AssistantSession, error)
	ListSessions(ctx context.Context, studentID uuid.UUID, limit int, cursor *PageCursor) ([]AssistantSession, error)
	ListMessages(ctx context.Context, studentID, sessionID uuid.UUID, limit int, cursor *PageCursor) ([]SessionMessage, error)
	DeleteSession(ctx context.Context, studentID, sessionID uuid.UUID) error
	FindExchange(ctx context.Context, studentID, sessionID, clientMessageID uuid.UUID) (StoredExchange, bool, error)
	SaveExchange(ctx context.Context, studentID, sessionID, clientMessageID uuid.UUID, userText string, assistant SessionMessage) (StoredExchange, error)
}

type PostgresSessionRepository struct{ pool *pgxpool.Pool }

func NewPostgresSessionRepository(pool *pgxpool.Pool) *PostgresSessionRepository {
	return &PostgresSessionRepository{pool: pool}
}

func (r *PostgresSessionRepository) StudentProfile(ctx context.Context, studentID uuid.UUID) (StudentAssistantProfile, error) {
	var profile StudentAssistantProfile
	err := r.pool.QueryRow(ctx, `SELECT locale, grade_level FROM student_profiles WHERE student_id = $1`, studentID).Scan(&profile.Locale, &profile.GradeLevel)
	if errors.Is(err, pgx.ErrNoRows) {
		return StudentAssistantProfile{}, ErrSessionNotFound
	}
	return profile, err
}

func (r *PostgresSessionRepository) CreateSession(ctx context.Context, studentID uuid.UUID, locale string, gradeLevel int) (AssistantSession, error) {
	var item AssistantSession
	err := r.pool.QueryRow(ctx, `
		INSERT INTO assistant_sessions(student_id, mode, locale, grade_level, title, started_at, created_at, updated_at, last_message_at)
		VALUES ($1, 'tutor', $2, $3, '', NOW(), NOW(), NOW(), NOW())
		RETURNING id::text, locale, grade_level, title, created_at, updated_at, last_message_at
	`, studentID, locale, gradeLevel).Scan(&item.ID, &item.Locale, &item.GradeLevel, &item.Title, &item.CreatedAt, &item.UpdatedAt, &item.LastMessageAt)
	return item, err
}

func (r *PostgresSessionRepository) GetSession(ctx context.Context, studentID, sessionID uuid.UUID) (AssistantSession, error) {
	var item AssistantSession
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, locale, grade_level, title, created_at, updated_at, last_message_at
		FROM assistant_sessions WHERE id = $1 AND student_id = $2
	`, sessionID, studentID).Scan(&item.ID, &item.Locale, &item.GradeLevel, &item.Title, &item.CreatedAt, &item.UpdatedAt, &item.LastMessageAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return AssistantSession{}, ErrSessionNotFound
	}
	return item, err
}

func (r *PostgresSessionRepository) ListSessions(ctx context.Context, studentID uuid.UUID, limit int, cursor *PageCursor) ([]AssistantSession, error) {
	args := []any{studentID, limit}
	cursorSQL := ""
	if cursor != nil {
		cursorSQL = "AND (last_message_at, id) < ($3, $4)"
		args = append(args, cursor.At, cursor.ID)
	}
	rows, err := r.pool.Query(ctx, fmt.Sprintf(`
		SELECT id::text, locale, grade_level, title, created_at, updated_at, last_message_at
		FROM assistant_sessions
		WHERE student_id = $1 %s
		ORDER BY last_message_at DESC, id DESC LIMIT $2
	`, cursorSQL), args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]AssistantSession, 0, limit)
	for rows.Next() {
		var item AssistantSession
		if err := rows.Scan(&item.ID, &item.Locale, &item.GradeLevel, &item.Title, &item.CreatedAt, &item.UpdatedAt, &item.LastMessageAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *PostgresSessionRepository) ListMessages(ctx context.Context, studentID, sessionID uuid.UUID, limit int, cursor *PageCursor) ([]SessionMessage, error) {
	if _, err := r.GetSession(ctx, studentID, sessionID); err != nil {
		return nil, err
	}
	args := []any{sessionID, limit}
	cursorSQL := ""
	if cursor != nil {
		cursorSQL = "AND (created_at, id) < ($3, $4)"
		args = append(args, cursor.At, cursor.ID)
	}
	rows, err := r.pool.Query(ctx, fmt.Sprintf(`
		SELECT id::text, session_id::text, role, content, input_mode, response_mode, created_at
		FROM assistant_messages WHERE session_id = $1 %s
		ORDER BY created_at DESC, id DESC LIMIT $2
	`, cursorSQL), args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]SessionMessage, 0, limit)
	for rows.Next() {
		var item SessionMessage
		if err := rows.Scan(&item.ID, &item.SessionID, &item.Role, &item.Content, &item.InputMode, &item.ResponseMode, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *PostgresSessionRepository) DeleteSession(ctx context.Context, studentID, sessionID uuid.UUID) error {
	result, err := r.pool.Exec(ctx, `DELETE FROM assistant_sessions WHERE id = $1 AND student_id = $2`, sessionID, studentID)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return ErrSessionNotFound
	}
	return nil
}

func (r *PostgresSessionRepository) FindExchange(ctx context.Context, studentID, sessionID, clientMessageID uuid.UUID) (StoredExchange, bool, error) {
	if _, err := r.GetSession(ctx, studentID, sessionID); err != nil {
		return StoredExchange{}, false, err
	}
	var exchange StoredExchange
	err := r.pool.QueryRow(ctx, `
		SELECT u.id::text, u.session_id::text, u.role, u.content, u.input_mode, u.created_at,
		       a.id::text, a.session_id::text, a.role, a.content, a.input_mode, a.response_mode, a.created_at
		FROM assistant_messages u
		JOIN assistant_messages a
		  ON a.session_id = u.session_id AND a.role = 'assistant' AND a.client_message_id = u.client_message_id
		WHERE u.session_id = $1 AND u.student_id = $2 AND u.client_message_id = $3 AND u.role = 'user'
	`, sessionID, studentID, clientMessageID).Scan(
		&exchange.User.ID, &exchange.User.SessionID, &exchange.User.Role, &exchange.User.Content, &exchange.User.InputMode, &exchange.User.CreatedAt,
		&exchange.Assistant.ID, &exchange.Assistant.SessionID, &exchange.Assistant.Role, &exchange.Assistant.Content, &exchange.Assistant.InputMode, &exchange.Assistant.ResponseMode, &exchange.Assistant.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return StoredExchange{}, false, nil
	}
	return exchange, err == nil, err
}

func (r *PostgresSessionRepository) SaveExchange(ctx context.Context, studentID, sessionID, clientMessageID uuid.UUID, userText string, assistant SessionMessage) (StoredExchange, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return StoredExchange{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var exchange StoredExchange
	err = tx.QueryRow(ctx, `
		INSERT INTO assistant_messages(session_id, student_id, role, text_content, content, client_message_id, input_mode, created_at)
		VALUES ($1, $2, 'user', $3, $3, $4, 'text', NOW())
		ON CONFLICT (session_id, client_message_id) WHERE client_message_id IS NOT NULL AND role = 'user' DO NOTHING
		RETURNING id::text, session_id::text, role, content, input_mode, created_at
	`, sessionID, studentID, userText, clientMessageID).Scan(
		&exchange.User.ID, &exchange.User.SessionID, &exchange.User.Role, &exchange.User.Content, &exchange.User.InputMode, &exchange.User.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		_ = tx.Rollback(ctx)
		existing, found, lookupErr := r.FindExchange(ctx, studentID, sessionID, clientMessageID)
		if lookupErr != nil {
			return StoredExchange{}, lookupErr
		}
		if !found {
			return StoredExchange{}, errors.New("idempotent exchange is still incomplete")
		}
		return existing, nil
	}
	if err != nil {
		return StoredExchange{}, err
	}

	policy := assistant.TutoringPolicy
	if len(policy) == 0 {
		policy = json.RawMessage(`{}`)
	}
	err = tx.QueryRow(ctx, `
		INSERT INTO assistant_messages(
			session_id, student_id, role, text_content, content, client_message_id, input_mode, provider, model,
			response_mode, tutoring_policy_result, safety_category, created_at
		) VALUES ($1, $2, 'assistant', $3, $3, $4, 'text', $5, $6, $7, $8, NULLIF($9, ''), NOW())
		RETURNING id::text, session_id::text, role, content, input_mode, response_mode, created_at
	`, sessionID, studentID, assistant.Content, clientMessageID, assistant.Provider, assistant.Model, assistant.ResponseMode, policy, assistant.SafetyCategory).Scan(
		&exchange.Assistant.ID, &exchange.Assistant.SessionID, &exchange.Assistant.Role, &exchange.Assistant.Content, &exchange.Assistant.InputMode, &exchange.Assistant.ResponseMode, &exchange.Assistant.CreatedAt,
	)
	if err != nil {
		return StoredExchange{}, err
	}
	title := boundedTitle(userText)
	if _, err = tx.Exec(ctx, `
		UPDATE assistant_sessions
		SET title = CASE WHEN title = '' THEN $3 ELSE title END,
		    updated_at = NOW(), last_message_at = NOW()
		WHERE id = $1 AND student_id = $2
	`, sessionID, studentID, title); err != nil {
		return StoredExchange{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return StoredExchange{}, err
	}
	return exchange, nil
}

func boundedTitle(text string) string {
	value := strings.Join(strings.Fields(strings.TrimSpace(text)), " ")
	runes := []rune(value)
	if len(runes) > 80 {
		return string(runes[:80]) + "…"
	}
	return value
}
