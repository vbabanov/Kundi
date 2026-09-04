package assistant

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	MaxContextTopics       = 6
	MaxContextHomeworks    = 5
	MaxContextWeakTopics   = 3
	MaxContextRecentGrades = 12
	MaxContextRunes        = 4_000
)

type ContextHomework struct {
	Subject     string
	Description string
	DueAt       *time.Time
}

type AcademicContext struct {
	Locale             string
	GradeLevel         int
	ClassLabel         string
	RecentTopics       []string
	WeakTopics         []string
	RecentResults      []string
	UnfinishedHomework []ContextHomework
	PositiveTrend      string
}

type AcademicContextProvider interface {
	Build(ctx context.Context, studentID uuid.UUID) (AcademicContext, error)
}

type EmptyAcademicContextProvider struct{}

func (EmptyAcademicContextProvider) Build(context.Context, uuid.UUID) (AcademicContext, error) {
	return AcademicContext{}, nil
}

type PostgresAcademicContextProvider struct{ pool *pgxpool.Pool }

func NewPostgresAcademicContextProvider(pool *pgxpool.Pool) *PostgresAcademicContextProvider {
	return &PostgresAcademicContextProvider{pool: pool}
}

func (p *PostgresAcademicContextProvider) Build(ctx context.Context, studentID uuid.UUID) (AcademicContext, error) {
	var result AcademicContext
	if err := p.pool.QueryRow(ctx, `
		SELECT locale, grade_level, class_label FROM student_profiles WHERE student_id = $1
	`, studentID).Scan(&result.Locale, &result.GradeLevel, &result.ClassLabel); err != nil {
		return AcademicContext{}, err
	}

	topicRows, err := p.pool.Query(ctx, `
		SELECT trim(lt.title)
		FROM lessons l JOIN lesson_topics lt ON lt.lesson_id = l.id
		WHERE l.student_id = $1 AND trim(lt.title) <> ''
		GROUP BY trim(lt.title)
		ORDER BY MAX(l.lesson_date) DESC LIMIT $2
	`, studentID, MaxContextTopics)
	if err != nil {
		return AcademicContext{}, err
	}
	for topicRows.Next() {
		var topic string
		if err := topicRows.Scan(&topic); err != nil {
			topicRows.Close()
			return AcademicContext{}, err
		}
		result.RecentTopics = append(result.RecentTopics, topic)
	}
	if err := topicRows.Err(); err != nil {
		topicRows.Close()
		return AcademicContext{}, err
	}
	topicRows.Close()

	homeworkRows, err := p.pool.Query(ctx, `
		SELECT l.subject_name, h.description, h.due_at
		FROM homeworks h
		JOIN lessons l ON l.id = h.lesson_id
		LEFT JOIN homework_completions hc ON hc.homework_id = h.id AND hc.student_id = h.student_id
		WHERE h.student_id = $1
		  AND COALESCE(hc.status, 'pending') NOT IN ('completed', 'submitted', 'reviewed')
		  AND trim(h.description) <> ''
		ORDER BY h.due_at ASC NULLS LAST, h.updated_at DESC LIMIT $2
	`, studentID, MaxContextHomeworks)
	if err != nil {
		return AcademicContext{}, err
	}
	for homeworkRows.Next() {
		var item ContextHomework
		if err := homeworkRows.Scan(&item.Subject, &item.Description, &item.DueAt); err != nil {
			homeworkRows.Close()
			return AcademicContext{}, err
		}
		result.UnfinishedHomework = append(result.UnfinishedHomework, item)
	}
	if err := homeworkRows.Err(); err != nil {
		homeworkRows.Close()
		return AcademicContext{}, err
	}
	homeworkRows.Close()

	gradeRows, err := p.pool.Query(ctx, `
		SELECT subject_name, value_text, resolved_mood
		FROM academic_results
		WHERE student_id = $1
		ORDER BY recorded_on DESC, updated_at DESC LIMIT $2
	`, studentID, MaxContextRecentGrades)
	if err != nil {
		return AcademicContext{}, err
	}
	moodsBySubject := make(map[string][]string)
	subjectOrder := make([]string, 0)
	for gradeRows.Next() {
		var subject, value, mood string
		if err := gradeRows.Scan(&subject, &value, &mood); err != nil {
			gradeRows.Close()
			return AcademicContext{}, err
		}
		result.RecentResults = append(result.RecentResults, fmt.Sprintf("%s: %s", strings.TrimSpace(subject), strings.TrimSpace(value)))
		if _, seen := moodsBySubject[subject]; !seen {
			subjectOrder = append(subjectOrder, subject)
		}
		moodsBySubject[subject] = append(moodsBySubject[subject], normalizeMood(mood))
	}
	if err := gradeRows.Err(); err != nil {
		gradeRows.Close()
		return AcademicContext{}, err
	}
	gradeRows.Close()

	weakRows, err := p.pool.Query(ctx, `
		SELECT trim(lt.title), COUNT(*)
		FROM academic_results ar
		JOIN lesson_topics lt ON lt.lesson_id = ar.lesson_id
		WHERE ar.student_id = $1
		  AND (lower(ar.resolved_mood) LIKE '%negative%' OR lower(ar.resolved_mood) LIKE '%bad%' OR lower(ar.resolved_mood) LIKE '%poor%')
		  AND trim(lt.title) <> ''
		GROUP BY trim(lt.title) HAVING COUNT(*) >= 2
		ORDER BY COUNT(*) DESC, trim(lt.title) LIMIT $2
	`, studentID, MaxContextWeakTopics)
	if err != nil {
		return AcademicContext{}, err
	}
	for weakRows.Next() {
		var topic string
		var count int
		if err := weakRows.Scan(&topic, &count); err != nil {
			weakRows.Close()
			return AcademicContext{}, err
		}
		result.WeakTopics = append(result.WeakTopics, topic)
	}
	if err := weakRows.Err(); err != nil {
		weakRows.Close()
		return AcademicContext{}, err
	}
	weakRows.Close()
	for _, subject := range subjectOrder {
		moods := moodsBySubject[subject]
		if hasPositiveTrend(moods) {
			result.PositiveTrend = strings.TrimSpace(subject)
			break
		}
	}
	return result, nil
}

func (c AcademicContext) Render() string {
	parts := []string{fmt.Sprintf("Class: %d %s", c.GradeLevel, strings.TrimSpace(c.ClassLabel))}
	if len(c.RecentTopics) > 0 {
		parts = append(parts, "Recent lesson topics: "+strings.Join(c.RecentTopics, "; "))
	}
	if len(c.WeakTopics) > 0 {
		parts = append(parts, "Repeated weak areas (not inferred from a single grade): "+strings.Join(c.WeakTopics, "; "))
	}
	if len(c.RecentResults) > 0 {
		parts = append(parts, "Recent results: "+strings.Join(c.RecentResults, "; "))
	}
	if len(c.UnfinishedHomework) > 0 {
		items := make([]string, 0, len(c.UnfinishedHomework))
		for _, item := range c.UnfinishedHomework {
			items = append(items, strings.TrimSpace(item.Subject)+": "+strings.TrimSpace(item.Description))
		}
		parts = append(parts, "Unfinished homework: "+strings.Join(items, "; "))
	}
	if c.PositiveTrend != "" {
		parts = append(parts, "Positive trend: "+c.PositiveTrend)
	}
	return boundContext(strings.Join(parts, "\n"), MaxContextRunes)
}

func (c AcademicContext) MatchesActiveHomework(question string) bool {
	questionTokens := meaningfulTokens(question)
	for _, homework := range c.UnfinishedHomework {
		candidate := strings.ToLower(homework.Subject + " " + homework.Description)
		matches := 0
		for _, token := range questionTokens {
			if strings.Contains(candidate, token) {
				matches++
			}
		}
		if matches >= 2 || (matches == 1 && len(questionTokens) <= 3) {
			return true
		}
	}
	return false
}

func (c AcademicContext) Suggestions() []string {
	out := make([]string, 0, 3)
	for _, topic := range c.WeakTopics {
		out = append(out, "Разобраться с темой: "+topic)
		if len(out) == 3 {
			return out
		}
	}
	for _, topic := range c.RecentTopics {
		out = append(out, "Повторить: "+topic)
		if len(out) == 3 {
			return out
		}
	}
	if len(out) == 0 {
		return []string{"Объясни тему", "Помоги сделать первый шаг", "Проверь мой ответ"}
	}
	return out
}

func normalizeMood(value string) string {
	v := strings.ToLower(strings.TrimSpace(value))
	if strings.Contains(v, "positive") || strings.Contains(v, "good") || strings.Contains(v, "excellent") || strings.Contains(v, "полож") {
		return "positive"
	}
	if strings.Contains(v, "negative") || strings.Contains(v, "bad") || strings.Contains(v, "poor") || strings.Contains(v, "отриц") {
		return "negative"
	}
	return ""
}

func hasPositiveTrend(moods []string) bool {
	if len(moods) < 3 || moods[0] != "positive" || moods[1] != "positive" {
		return false
	}
	for _, mood := range moods[2:] {
		if mood != "positive" {
			return true
		}
	}
	return false
}

func meaningfulTokens(value string) []string {
	fields := strings.Fields(strings.ToLower(value))
	out := make([]string, 0, len(fields))
	for _, field := range fields {
		field = strings.Trim(field, ".,!?;:()[]{}\"'")
		if len([]rune(field)) >= 4 {
			out = append(out, field)
		}
	}
	return out
}

func boundContext(value string, max int) string {
	runes := []rune(strings.TrimSpace(value))
	if len(runes) <= max {
		return string(runes)
	}
	return string(runes[:max])
}
