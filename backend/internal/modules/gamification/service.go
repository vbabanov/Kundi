package gamification

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	activeDayXP         = 5
	gradeFiveXP         = 10
	learningQuestionXP  = 2
	attemptCheckXP      = 3
	achievementUnlockXP = 25
	maxLearningXPPerDay = 20
	maxAttemptXPPerDay  = 15
	DefaultTimezone     = "Asia/Almaty"
)

var ErrUnknownAchievement = errors.New("unknown achievement")

type Clock interface{ Now() time.Time }
type systemClock struct{}

func (systemClock) Now() time.Time { return time.Now() }

type Service struct {
	pool     *pgxpool.Pool
	location *time.Location
	clock    Clock
}

type Profile struct {
	CatalogVersion       int           `json:"catalog_version"`
	Points               int           `json:"points"`
	Level                int           `json:"level"`
	LevelFloorPoints     int           `json:"level_floor_points"`
	NextLevelPoints      int           `json:"next_level_points"`
	CurrentStreak        int           `json:"current_streak"`
	LongestStreak        int           `json:"longest_streak"`
	LastActiveDate       string        `json:"last_active_date,omitempty"`
	AchievementsUnlocked int           `json:"achievements_unlocked"`
	AchievementsTotal    int           `json:"achievements_total"`
	Achievements         []Achievement `json:"achievements"`
	PendingUnlocks       []Achievement `json:"pending_unlocks"`
}

type Achievement struct {
	Code          string        `json:"code"`
	Category      string        `json:"category"`
	CategoryTitle LocalizedText `json:"category_title"`
	Title         LocalizedText `json:"title"`
	Description   LocalizedText `json:"description"`
	Current       int           `json:"current"`
	Target        int           `json:"target"`
	Unlocked      bool          `json:"unlocked"`
	UnlockedAt    string        `json:"unlocked_at,omitempty"`
	Seen          bool          `json:"seen"`
}

type metricValues struct {
	ActiveDays, CurrentStreak, LongestStreak, GradeFives, LearningQuestions, AttemptChecks int
	LastActiveDate                                                                         *time.Time
	ActivityDays                                                                           []activityDay
}

type activityDay struct {
	Date      time.Time
	FirstSeen time.Time
}

type unlockState struct {
	At   time.Time
	Seen bool
}

func NewService(pool *pgxpool.Pool, timezone string) (*Service, error) {
	return NewServiceWithClock(pool, timezone, systemClock{})
}

func NewServiceWithClock(pool *pgxpool.Pool, timezone string, clock Clock) (*Service, error) {
	if pool == nil {
		return nil, errors.New("gamification pool is required")
	}
	zone := strings.TrimSpace(timezone)
	if zone == "" {
		zone = DefaultTimezone
	}
	location, err := time.LoadLocation(zone)
	if err != nil {
		return nil, fmt.Errorf("load gamification timezone: %w", err)
	}
	if clock == nil {
		clock = systemClock{}
	}
	return &Service{pool: pool, location: location, clock: clock}, nil
}

func (s *Service) GetProfile(ctx context.Context, studentID uuid.UUID) (Profile, error) {
	return s.reconcile(ctx, studentID, false)
}

func (s *Service) RecordActivity(ctx context.Context, studentID uuid.UUID) (Profile, error) {
	return s.reconcile(ctx, studentID, true)
}

func (s *Service) Acknowledge(ctx context.Context, studentID uuid.UUID, codes []string) error {
	if studentID == uuid.Nil {
		return errors.New("student id is required")
	}
	if len(codes) == 0 {
		return nil
	}
	known := make(map[string]struct{}, len(catalog))
	for _, definition := range catalog {
		known[definition.Code] = struct{}{}
	}
	dedup := make([]string, 0, len(codes))
	seen := make(map[string]struct{}, len(codes))
	for _, raw := range codes {
		code := strings.TrimSpace(raw)
		if _, ok := known[code]; !ok {
			return fmt.Errorf("%w: %q", ErrUnknownAchievement, code)
		}
		if _, ok := seen[code]; ok {
			continue
		}
		seen[code] = struct{}{}
		dedup = append(dedup, code)
	}
	_, err := s.pool.Exec(ctx, `
		UPDATE gamification_achievement_unlocks
		SET seen_at = COALESCE(seen_at, $3)
		WHERE student_id = $1 AND achievement_code = ANY($2::text[])
	`, studentID, dedup, s.clock.Now().UTC())
	return err
}

func (s *Service) reconcile(ctx context.Context, studentID uuid.UUID, recordActivity bool) (Profile, error) {
	if studentID == uuid.Nil {
		return Profile{}, errors.New("student id is required")
	}
	now := s.clock.Now().UTC()
	localDate := dateOnly(now.In(s.location))
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Profile{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err = tx.Exec(ctx, `
		INSERT INTO gamification_profiles(student_id, catalog_version)
		VALUES ($1, $2) ON CONFLICT (student_id) DO NOTHING
	`, studentID, CatalogVersion); err != nil {
		return Profile{}, err
	}
	if _, err = tx.Exec(ctx, `SELECT 1 FROM gamification_profiles WHERE student_id = $1 FOR UPDATE`, studentID); err != nil {
		return Profile{}, err
	}
	if recordActivity {
		if _, err = tx.Exec(ctx, `
			INSERT INTO gamification_activity_days(student_id, activity_date, timezone, first_seen_at, last_seen_at)
			VALUES ($1, $2, $3, $4, $4)
			ON CONFLICT (student_id, activity_date) DO UPDATE SET last_seen_at = GREATEST(gamification_activity_days.last_seen_at, EXCLUDED.last_seen_at)
		`, studentID, localDate, s.location.String(), now); err != nil {
			return Profile{}, err
		}
	}
	if err = s.reconcileSourceFacts(ctx, tx, studentID); err != nil {
		return Profile{}, err
	}
	metrics, err := loadMetrics(ctx, tx, studentID, localDate)
	if err != nil {
		return Profile{}, err
	}
	unlocks, err := loadUnlocks(ctx, tx, studentID)
	if err != nil {
		return Profile{}, err
	}
	for _, definition := range catalog {
		if progressFor(definition.Metric, metrics) < definition.Target {
			continue
		}
		if _, exists := unlocks[definition.Code]; exists {
			continue
		}
		unlockedAt, err := unlockTime(ctx, tx, studentID, definition, metrics)
		if err != nil {
			return Profile{}, err
		}
		if _, err = tx.Exec(ctx, `
			INSERT INTO gamification_achievement_unlocks(student_id, achievement_code, catalog_version, unlocked_at)
			VALUES ($1, $2, $3, $4) ON CONFLICT (student_id, achievement_code) DO NOTHING
		`, studentID, definition.Code, CatalogVersion, unlockedAt); err != nil {
			return Profile{}, err
		}
		unlocks[definition.Code] = unlockState{At: unlockedAt}
	}
	points, err := calculatePoints(ctx, tx, studentID)
	if err != nil {
		return Profile{}, err
	}
	level, floor, next := LevelForPoints(points)
	if _, err = tx.Exec(ctx, `
		UPDATE gamification_profiles SET catalog_version=$2, points=$3, level=$4,
			current_streak=$5, longest_streak=$6, last_active_date=$7,
			reconciled_at=$8, updated_at=$8 WHERE student_id=$1
	`, studentID, CatalogVersion, points, level, metrics.CurrentStreak, metrics.LongestStreak, metrics.LastActiveDate, now); err != nil {
		return Profile{}, err
	}
	profile := buildProfile(metrics, unlocks, points, level, floor, next)
	if err = tx.Commit(ctx); err != nil {
		return Profile{}, err
	}
	return profile, nil
}

func (s *Service) reconcileSourceFacts(ctx context.Context, tx pgx.Tx, studentID uuid.UUID) error {
	zone := s.location.String()
	if _, err := tx.Exec(ctx, `
		INSERT INTO gamification_facts(student_id, fact_type, source_key, occurred_at, local_date)
		SELECT student_id, 'grade_five', id::text, recorded_on::timestamp AT TIME ZONE $2, recorded_on
		FROM academic_results
		WHERE student_id=$1 AND result_kind='regular' AND value_numeric=5
		ON CONFLICT (student_id, fact_type, source_key) DO NOTHING
	`, studentID, zone); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO gamification_facts(student_id, fact_type, source_key, occurred_at, local_date)
		SELECT a.student_id,
		       CASE WHEN a.response_mode='attempt_check' THEN 'attempt_check' ELSE 'learning_question' END,
		       a.id::text, a.created_at, (a.created_at AT TIME ZONE $2)::date
		FROM assistant_messages a
		WHERE a.student_id=$1 AND a.role='assistant' AND a.provider<>''
		  AND COALESCE(a.safety_category, '')=''
		  AND a.tutoring_policy_result @> '{"schema_version":1,"ready_answer_risk":false}'::jsonb
		  AND a.response_mode IN ('answer','explanation','hint','learning_plan','attempt_check')
		ON CONFLICT (student_id, fact_type, source_key) DO NOTHING
	`, studentID, zone)
	return err
}

func loadMetrics(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, today time.Time) (metricValues, error) {
	var metrics metricValues
	rows, err := tx.Query(ctx, `SELECT activity_date, first_seen_at FROM gamification_activity_days WHERE student_id=$1 ORDER BY activity_date`, studentID)
	if err != nil {
		return metrics, err
	}
	var days []time.Time
	for rows.Next() {
		var record activityDay
		if err := rows.Scan(&record.Date, &record.FirstSeen); err != nil {
			rows.Close()
			return metrics, err
		}
		record.Date = dateOnly(record.Date)
		days = append(days, record.Date)
		metrics.ActivityDays = append(metrics.ActivityDays, record)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return metrics, err
	}
	rows.Close()
	metrics.ActiveDays = len(days)
	metrics.CurrentStreak, metrics.LongestStreak, metrics.LastActiveDate = streaks(days, today)
	if err := tx.QueryRow(ctx, `
		SELECT count(*) FILTER (WHERE fact_type='grade_five'),
		       count(*) FILTER (WHERE fact_type='learning_question'),
		       count(*) FILTER (WHERE fact_type='attempt_check')
		FROM gamification_facts WHERE student_id=$1
	`, studentID).Scan(&metrics.GradeFives, &metrics.LearningQuestions, &metrics.AttemptChecks); err != nil {
		return metrics, err
	}
	return metrics, nil
}

func unlockTime(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, definition Definition, metrics metricValues) (time.Time, error) {
	switch definition.Metric {
	case MetricActiveDays:
		return metrics.ActivityDays[definition.Target-1].FirstSeen.UTC(), nil
	case MetricLongestStreak:
		run := 0
		var previous time.Time
		for _, record := range metrics.ActivityDays {
			if run == 0 || record.Date.Sub(previous) != 24*time.Hour {
				run = 1
			} else {
				run++
			}
			if run == definition.Target {
				return record.FirstSeen.UTC(), nil
			}
			previous = record.Date
		}
	case MetricGradeFives, MetricLearningQuestions, MetricAttemptChecks:
		factType := map[Metric]string{
			MetricGradeFives:        "grade_five",
			MetricLearningQuestions: "learning_question",
			MetricAttemptChecks:     "attempt_check",
		}[definition.Metric]
		var occurredAt time.Time
		err := tx.QueryRow(ctx, `
			SELECT occurred_at FROM gamification_facts
			WHERE student_id=$1 AND fact_type=$2
			ORDER BY occurred_at, source_key
			OFFSET $3 LIMIT 1
		`, studentID, factType, definition.Target-1).Scan(&occurredAt)
		if err != nil {
			return time.Time{}, err
		}
		return occurredAt.UTC(), nil
	}
	return time.Time{}, fmt.Errorf("cannot determine unlock time for %s", definition.Code)
}

func streaks(days []time.Time, today time.Time) (current, longest int, last *time.Time) {
	if len(days) == 0 {
		return 0, 0, nil
	}
	run := 0
	var previous time.Time
	for _, day := range days {
		if run == 0 || day.Sub(previous) != 24*time.Hour {
			run = 1
		} else {
			run++
		}
		if run > longest {
			longest = run
		}
		previous = day
	}
	lastValue := days[len(days)-1]
	last = &lastValue
	if delta := int(today.Sub(lastValue).Hours() / 24); delta == 0 || delta == 1 {
		current = 1
		for index := len(days) - 1; index > 0 && days[index].Sub(days[index-1]) == 24*time.Hour; index-- {
			current++
		}
	}
	return current, longest, last
}

func calculatePoints(ctx context.Context, tx pgx.Tx, studentID uuid.UUID) (int, error) {
	var activeDays, grades, unlocks int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM gamification_activity_days WHERE student_id=$1`, studentID).Scan(&activeDays); err != nil {
		return 0, err
	}
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM gamification_facts WHERE student_id=$1 AND fact_type='grade_five'`, studentID).Scan(&grades); err != nil {
		return 0, err
	}
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM gamification_achievement_unlocks WHERE student_id=$1`, studentID).Scan(&unlocks); err != nil {
		return 0, err
	}
	var learningXP, attemptXP int
	if err := tx.QueryRow(ctx, `SELECT COALESCE(sum(LEAST(day_count*$2, $3)),0)::int FROM (SELECT count(*) day_count FROM gamification_facts WHERE student_id=$1 AND fact_type='learning_question' GROUP BY local_date) d`, studentID, learningQuestionXP, maxLearningXPPerDay).Scan(&learningXP); err != nil {
		return 0, err
	}
	if err := tx.QueryRow(ctx, `SELECT COALESCE(sum(LEAST(day_count*$2, $3)),0)::int FROM (SELECT count(*) day_count FROM gamification_facts WHERE student_id=$1 AND fact_type='attempt_check' GROUP BY local_date) d`, studentID, attemptCheckXP, maxAttemptXPPerDay).Scan(&attemptXP); err != nil {
		return 0, err
	}
	return activeDays*activeDayXP + grades*gradeFiveXP + learningXP + attemptXP + unlocks*achievementUnlockXP, nil
}

func loadUnlocks(ctx context.Context, tx pgx.Tx, studentID uuid.UUID) (map[string]unlockState, error) {
	rows, err := tx.Query(ctx, `SELECT achievement_code, unlocked_at, seen_at IS NOT NULL FROM gamification_achievement_unlocks WHERE student_id=$1`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[string]unlockState)
	for rows.Next() {
		var code string
		var state unlockState
		if err := rows.Scan(&code, &state.At, &state.Seen); err != nil {
			return nil, err
		}
		result[code] = state
	}
	return result, rows.Err()
}

func buildProfile(metrics metricValues, unlocks map[string]unlockState, points, level, floor, next int) Profile {
	profile := Profile{CatalogVersion: CatalogVersion, Points: points, Level: level, LevelFloorPoints: floor, NextLevelPoints: next, CurrentStreak: metrics.CurrentStreak, LongestStreak: metrics.LongestStreak, AchievementsTotal: len(catalog), Achievements: make([]Achievement, 0, len(catalog)), PendingUnlocks: []Achievement{}}
	if metrics.LastActiveDate != nil {
		profile.LastActiveDate = metrics.LastActiveDate.Format("2006-01-02")
	}
	for _, definition := range catalog {
		state, unlocked := unlocks[definition.Code]
		item := Achievement{Code: definition.Code, Category: definition.Category, CategoryTitle: CategoryTitle(definition.Category), Title: definition.Title, Description: definition.Description, Current: progressFor(definition.Metric, metrics), Target: definition.Target, Unlocked: unlocked, Seen: state.Seen}
		if unlocked {
			item.UnlockedAt = state.At.UTC().Format(time.RFC3339)
			profile.AchievementsUnlocked++
		}
		profile.Achievements = append(profile.Achievements, item)
		if unlocked && !state.Seen {
			profile.PendingUnlocks = append(profile.PendingUnlocks, item)
		}
	}
	return profile
}

func progressFor(metric Metric, values metricValues) int {
	switch metric {
	case MetricActiveDays:
		return values.ActiveDays
	case MetricLongestStreak:
		return values.LongestStreak
	case MetricGradeFives:
		return values.GradeFives
	case MetricLearningQuestions:
		return values.LearningQuestions
	case MetricAttemptChecks:
		return values.AttemptChecks
	default:
		return 0
	}
}

func dateOnly(value time.Time) time.Time {
	return time.Date(value.Year(), value.Month(), value.Day(), 0, 0, 0, 0, time.UTC)
}
