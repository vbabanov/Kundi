package academic

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kundi/kundi/backend/internal/platform/observability"
)

type queryer interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type Service struct {
	pool    queryer
	metrics observability.Metrics
	tracer  observability.Tracer
}

func NewService(pool *pgxpool.Pool, hooks ...observability.Hooks) *Service {
	observe := observability.Ensure(observability.Hooks{})
	if len(hooks) > 0 {
		observe = observability.Ensure(hooks[0])
	}
	return &Service{
		pool:    pool,
		metrics: observe.Metrics,
		tracer:  observe.Tracer,
	}
}

func (s *Service) Lessons(ctx context.Context, studentID uuid.UUID) ([]map[string]any, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT l.id::text,
		       TO_CHAR(l.lesson_date, 'YYYY-MM-DD'),
		       l.lesson_number,
		       l.subject_name,
		       COALESCE(lt.title, ''),
		       COALESCE(h.description, ''),
		       COALESCE(h.requires_photo, FALSE),
		       COALESCE(g.grade_value, ''),
		       COALESCE(g.grade_mood, ''),
		       COALESCE(a.attendance_code, '')
		FROM lessons l
		LEFT JOIN lesson_topics lt ON lt.lesson_id = l.id AND lt.topic_index = 1
		LEFT JOIN homeworks h ON h.lesson_id = l.id
		LEFT JOIN LATERAL (
			SELECT grade_value, grade_mood
			FROM grades
			WHERE lesson_id = l.id
			ORDER BY updated_at DESC
			LIMIT 1
		) g ON TRUE
		LEFT JOIN attendance_events a ON a.lesson_id = l.id
		WHERE l.student_id = $1
		ORDER BY l.lesson_date ASC, l.lesson_number ASC
	`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var lessonID, date, subject, topic, homework, gradeValue, gradeMood, attendance string
		var lessonNumber int
		var requiresPhoto bool
		if err := rows.Scan(&lessonID, &date, &lessonNumber, &subject, &topic, &homework, &requiresPhoto, &gradeValue, &gradeMood, &attendance); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{
			"lesson_id":       lessonID,
			"date":            date,
			"lesson_number":   lessonNumber,
			"subject_name":    subject,
			"topic":           topic,
			"homework_text":   homework,
			"requires_photo":  requiresPhoto,
			"grade_value":     gradeValue,
			"grade_mood":      gradeMood,
			"attendance_code": attendance,
		})
	}
	return out, rows.Err()
}

func (s *Service) Homework(ctx context.Context, studentID uuid.UUID) ([]map[string]any, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT h.id::text,
		       h.description,
		       COALESCE(h.requires_photo, FALSE),
		       TO_CHAR(l.lesson_date, 'YYYY-MM-DD'),
		       l.subject_name
		FROM homeworks h
		JOIN lessons l ON l.id = h.lesson_id
		WHERE h.student_id = $1
		ORDER BY l.lesson_date DESC
	`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var id, description, lessonDate, subject string
		var requiresPhoto bool
		if err := rows.Scan(&id, &description, &requiresPhoto, &lessonDate, &subject); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{
			"homework_id":    id,
			"description":    description,
			"requires_photo": requiresPhoto,
			"lesson_date":    lessonDate,
			"subject_name":   subject,
		})
	}
	return out, rows.Err()
}

func (s *Service) Grades(ctx context.Context, studentID uuid.UUID) ([]map[string]any, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT grade_value, COALESCE(grade_mood, ''), COALESCE(grade_type, 'regular'), created_at
		FROM grades
		WHERE student_id = $1
		ORDER BY created_at DESC
	`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var value, mood, gradeType string
		var createdAt string
		if err := rows.Scan(&value, &mood, &gradeType, &createdAt); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{
			"value":      value,
			"mood":       mood,
			"grade_type": gradeType,
			"created_at": createdAt,
		})
	}
	return out, rows.Err()
}

func (s *Service) Attendance(ctx context.Context, studentID uuid.UUID) ([]map[string]any, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT TO_CHAR(event_date, 'YYYY-MM-DD'), attendance_code, reason
		FROM attendance_events
		WHERE student_id = $1
		ORDER BY event_date DESC
	`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		var date, code, reason string
		if err := rows.Scan(&date, &code, &reason); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{"date": date, "code": code, "reason": reason})
	}
	return out, rows.Err()
}

func (s *Service) BuildHomeworkDigest(
	ctx context.Context,
	studentID uuid.UUID,
	forDate time.Time,
	mode string,
) (string, error) {
	date := forDate.UTC().Format("2006-01-02")
	mode = strings.ToLower(strings.TrimSpace(mode))
	if mode != "topic" {
		mode = "homework"
	}
	studentName := ""
	_ = s.pool.QueryRow(
		ctx,
		`SELECT COALESCE(full_name, '') FROM profiles WHERE student_id = $1`,
		studentID,
	).Scan(&studentName)
	studentName = strings.TrimSpace(studentName)

	rows, err := s.pool.Query(ctx, `
		SELECT COALESCE(l.subject_name, ''),
		       COALESCE(TO_CHAR(l.start_time, 'HH24:MI'), ''),
		       COALESCE(TO_CHAR(l.end_time, 'HH24:MI'), ''),
		       l.lesson_number,
		       COALESCE(h.description, ''),
		       COALESCE(lt.title, '')
		FROM lessons l
		LEFT JOIN homeworks h ON h.lesson_id = l.id
		LEFT JOIN lesson_topics lt ON lt.lesson_id = l.id AND lt.topic_index = 1
		WHERE l.student_id = $1
		  AND l.lesson_date = $2::date
		ORDER BY l.lesson_number ASC, l.start_time ASC NULLS LAST
	`, studentID, date)
	if err != nil {
		return "", err
	}
	defer rows.Close()

	items := make([]string, 0, 8)
	index := 1
	for rows.Next() {
		var subjectName, startTime, endTime, homeworkText, topicTitle string
		var lessonNumber int
		if err := rows.Scan(
			&subjectName,
			&startTime,
			&endTime,
			&lessonNumber,
			&homeworkText,
			&topicTitle,
		); err != nil {
			return "", err
		}

		subject := strings.TrimSpace(subjectName)
		if subject == "" {
			subject = "Предмет"
		}
		content := strings.TrimSpace(homeworkText)
		if mode == "topic" {
			content = strings.TrimSpace(topicTitle)
		}
		if content == "" {
			content = "не задано"
		}

		title := fmt.Sprintf("%d. %s", index, subject)
		if startTime != "" && endTime != "" {
			title = fmt.Sprintf("%s (%s - %s)", title, startTime, endTime)
		}
		title = "*" + title + "*"

		itemLines := []string{title, "_" + content + "_"}
		if mode == "homework" {
			topic := strings.TrimSpace(topicTitle)
			if topic != "" {
				lowered := strings.ToLower(topic + " " + content)
				if strings.Contains(lowered, "контрольн") ||
					strings.Contains(lowered, "сор") ||
					strings.Contains(lowered, "соч") ||
					strings.Contains(lowered, " sor") ||
					strings.Contains(lowered, " soch") {
					itemLines = append(itemLines, "⚠️ Важно: "+topic)
				}
			}
		}

		if lessonNumber < 0 {
			lessonNumber = 0
		}
		items = append(items, strings.Join(itemLines, "\n"))
		index++
	}
	if err := rows.Err(); err != nil {
		return "", err
	}

	headerDate := forDate.UTC().Format("02.01.2006")
	header := fmt.Sprintf("📚 ДЗ на %s:", headerDate)
	if mode == "topic" {
		header = fmt.Sprintf("📚 Темы на %s:", headerDate)
	}

	parts := []string{header}
	if studentName != "" {
		parts = append(parts, studentName)
	}
	if len(items) == 0 {
		parts = append(parts, "На эту дату уроков не найдено.")
		return strings.Join(parts, "\n\n"), nil
	}
	parts = append(parts, strings.Join(items, "\n\n"))
	return strings.Join(parts, "\n\n"), nil
}
