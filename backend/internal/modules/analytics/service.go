package analytics

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool}
}

func (s *Service) RecomputeDailyStats(ctx context.Context, studentID uuid.UUID, statsDate time.Time) error {
	date := statsDate.UTC().Format("2006-01-02")

	var lessonsTotal int
	var homeworkTotal int
	var homeworkCompleted int
	var absencesTotal int
	var avgGrade *float64
	err := s.pool.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*)
			 FROM lessons l
			 WHERE l.student_id = $1 AND l.lesson_date = $2::date),
			(SELECT COUNT(*)
			 FROM homeworks h
			 JOIN lessons l ON l.id = h.lesson_id
			 WHERE h.student_id = $1 AND l.lesson_date = $2::date),
			(SELECT COUNT(*)
			 FROM homework_completions hc
			 JOIN homeworks h ON h.id = hc.homework_id
			 JOIN lessons l ON l.id = h.lesson_id
			 WHERE hc.student_id = $1
			   AND l.lesson_date = $2::date
			   AND hc.status IN ('completed', 'submitted', 'reviewed')),
			(SELECT COUNT(*)
			 FROM attendance_events a
			 WHERE a.student_id = $1
			   AND a.event_date = $2::date
			   AND a.attendance_code = 'absent'),
			(SELECT AVG(g.grade_numeric)::float8
			 FROM grades g
			 JOIN lessons l ON l.id = g.lesson_id
			 WHERE g.student_id = $1
			   AND l.lesson_date = $2::date
			   AND g.grade_numeric IS NOT NULL)
	`, studentID, date).Scan(
		&lessonsTotal,
		&homeworkTotal,
		&homeworkCompleted,
		&absencesTotal,
		&avgGrade,
	)
	if err != nil {
		return fmt.Errorf("load daily stat aggregates: %w", err)
	}

	riskScore := computeRiskScore(homeworkTotal, homeworkCompleted, absencesTotal)
	_, err = s.pool.Exec(ctx, `
		INSERT INTO daily_stats (
			student_id,
			stats_date,
			lessons_total,
			homework_total,
			homework_completed,
			absences_total,
			avg_grade,
			risk_score,
			computed_at
		)
		VALUES ($1, $2::date, $3, $4, $5, $6, $7, $8, NOW())
		ON CONFLICT (student_id, stats_date)
		DO UPDATE SET
			lessons_total = EXCLUDED.lessons_total,
			homework_total = EXCLUDED.homework_total,
			homework_completed = EXCLUDED.homework_completed,
			absences_total = EXCLUDED.absences_total,
			avg_grade = EXCLUDED.avg_grade,
			risk_score = EXCLUDED.risk_score,
			computed_at = NOW()
	`, studentID, date, lessonsTotal, homeworkTotal, homeworkCompleted, absencesTotal, avgGrade, riskScore)
	if err != nil {
		return fmt.Errorf("upsert daily stats: %w", err)
	}
	return nil
}

func (s *Service) RecomputeWeeklyStats(ctx context.Context, studentID uuid.UUID, weekStart, weekEnd time.Time) error {
	startDate := weekStart.UTC().Format("2006-01-02")
	endDate := weekEnd.UTC().Format("2006-01-02")

	var lessonsTotal int
	var homeworkTotal int
	var homeworkCompleted int
	var absencesTotal int
	var avgGrade *float64
	err := s.pool.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*)
			 FROM lessons l
			 WHERE l.student_id = $1 AND l.lesson_date BETWEEN $2::date AND $3::date),
			(SELECT COUNT(*)
			 FROM homeworks h
			 JOIN lessons l ON l.id = h.lesson_id
			 WHERE h.student_id = $1 AND l.lesson_date BETWEEN $2::date AND $3::date),
			(SELECT COUNT(*)
			 FROM homework_completions hc
			 JOIN homeworks h ON h.id = hc.homework_id
			 JOIN lessons l ON l.id = h.lesson_id
			 WHERE hc.student_id = $1
			   AND l.lesson_date BETWEEN $2::date AND $3::date
			   AND hc.status IN ('completed', 'submitted', 'reviewed')),
			(SELECT COUNT(*)
			 FROM attendance_events a
			 WHERE a.student_id = $1
			   AND a.event_date BETWEEN $2::date AND $3::date
			   AND a.attendance_code = 'absent'),
			(SELECT AVG(g.grade_numeric)::float8
			 FROM grades g
			 JOIN lessons l ON l.id = g.lesson_id
			 WHERE g.student_id = $1
			   AND l.lesson_date BETWEEN $2::date AND $3::date
			   AND g.grade_numeric IS NOT NULL)
	`, studentID, startDate, endDate).Scan(
		&lessonsTotal,
		&homeworkTotal,
		&homeworkCompleted,
		&absencesTotal,
		&avgGrade,
	)
	if err != nil {
		return fmt.Errorf("load weekly stat aggregates: %w", err)
	}

	riskScore := computeRiskScore(homeworkTotal, homeworkCompleted, absencesTotal)
	_, err = s.pool.Exec(ctx, `
		INSERT INTO weekly_stats (
			student_id,
			week_start,
			week_end,
			lessons_total,
			homework_total,
			homework_completed,
			absences_total,
			avg_grade,
			risk_score,
			computed_at
		)
		VALUES ($1, $2::date, $3::date, $4, $5, $6, $7, $8, $9, NOW())
		ON CONFLICT (student_id, week_start, week_end)
		DO UPDATE SET
			lessons_total = EXCLUDED.lessons_total,
			homework_total = EXCLUDED.homework_total,
			homework_completed = EXCLUDED.homework_completed,
			absences_total = EXCLUDED.absences_total,
			avg_grade = EXCLUDED.avg_grade,
			risk_score = EXCLUDED.risk_score,
			computed_at = NOW()
	`, studentID, startDate, endDate, lessonsTotal, homeworkTotal, homeworkCompleted, absencesTotal, avgGrade, riskScore)
	if err != nil {
		return fmt.Errorf("upsert weekly stats: %w", err)
	}
	return nil
}

func (s *Service) DetectStaleData(ctx context.Context, studentID uuid.UUID, now time.Time, maxAge time.Duration) error {
	if maxAge <= 0 {
		maxAge = 72 * time.Hour
	}

	var lastIngest sql.NullTime
	if err := s.pool.QueryRow(ctx, `
		SELECT MAX(ingested_at)
		FROM ingest_batches
		WHERE student_id = $1
		  AND status = 'merged'
	`, studentID).Scan(&lastIngest); err != nil {
		return fmt.Errorf("load last ingest timestamp: %w", err)
	}

	stale := !lastIngest.Valid || now.UTC().Sub(lastIngest.Time.UTC()) > maxAge
	if stale {
		return s.openOrRefreshStaleFlag(ctx, studentID, lastIngest, maxAge)
	}
	_, err := s.pool.Exec(ctx, `
		UPDATE risk_flags
		SET status = 'resolved',
			resolved_at = NOW()
		WHERE student_id = $1
		  AND flag_type = 'stale_data'
		  AND status = 'open'
	`, studentID)
	if err != nil {
		return fmt.Errorf("resolve stale_data risk flag: %w", err)
	}
	return nil
}

func (s *Service) openOrRefreshStaleFlag(ctx context.Context, studentID uuid.UUID, lastIngest sql.NullTime, maxAge time.Duration) error {
	details := map[string]any{
		"max_age_hours": maxAge.Hours(),
	}
	if lastIngest.Valid {
		details["last_ingested_at"] = lastIngest.Time.UTC().Format(time.RFC3339)
	} else {
		details["last_ingested_at"] = ""
	}
	rawDetails, _ := json.Marshal(details)

	var existingID uuid.UUID
	err := s.pool.QueryRow(ctx, `
		SELECT id
		FROM risk_flags
		WHERE student_id = $1
		  AND flag_type = 'stale_data'
		  AND status = 'open'
		ORDER BY detected_at DESC
		LIMIT 1
	`, studentID).Scan(&existingID)
	if err == nil {
		_, err = s.pool.Exec(ctx, `
			UPDATE risk_flags
			SET severity = 3,
				details = $2,
				detected_at = NOW()
			WHERE id = $1
		`, existingID, rawDetails)
		if err != nil {
			return fmt.Errorf("refresh stale_data risk flag: %w", err)
		}
		return nil
	}

	_, err = s.pool.Exec(ctx, `
		INSERT INTO risk_flags (student_id, flag_type, severity, status, details, detected_at)
		VALUES ($1, 'stale_data', 3, 'open', $2, NOW())
	`, studentID, rawDetails)
	if err != nil {
		return fmt.Errorf("insert stale_data risk flag: %w", err)
	}
	return nil
}

func computeRiskScore(homeworkTotal, homeworkCompleted, absencesTotal int) float64 {
	missedHomework := homeworkTotal - homeworkCompleted
	if missedHomework < 0 {
		missedHomework = 0
	}
	score := float64(absencesTotal*12 + missedHomework*5)
	if score > 100 {
		return 100
	}
	return score
}
