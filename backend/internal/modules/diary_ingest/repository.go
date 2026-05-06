package diary_ingest

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrIdempotencyConflict = errors.New("idempotency key already exists with different payload")

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

func (r *PostgresRepository) CreateBatch(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundle, checksum string) (uuid.UUID, bool, error) {
	payload, _ := json.Marshal(bundle)
	var batchID uuid.UUID
	err := r.pool.QueryRow(ctx, `
		INSERT INTO ingest_batches (student_id, idempotency_key, bundle_checksum, bundle_version, status, request_payload, ingested_at)
		VALUES ($1, $2, $3, 1, 'accepted', $4, NOW())
		ON CONFLICT (student_id, idempotency_key) DO NOTHING
		RETURNING id
	`, studentID, bundle.IdempotencyKey, checksum, payload).Scan(&batchID)
	if err == pgx.ErrNoRows {
		var existingChecksum string
		err = r.pool.QueryRow(ctx, `
			SELECT id, bundle_checksum
			FROM ingest_batches
			WHERE student_id = $1 AND idempotency_key = $2
		`, studentID, bundle.IdempotencyKey).Scan(&batchID, &existingChecksum)
		if err != nil {
			return uuid.Nil, false, err
		}
		if existingChecksum != checksum {
			return batchID, false, ErrIdempotencyConflict
		}
		return batchID, false, nil
	}
	if err != nil {
		return uuid.Nil, false, err
	}
	return batchID, true, nil
}

func (r *PostgresRepository) MergeBundle(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundle) (int, int, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return 0, 0, err
	}
	defer tx.Rollback(ctx)

	if err := upsertProfile(ctx, tx, studentID, bundle.Profile); err != nil {
		return 0, 0, err
	}
	if err := upsertSourceIDs(ctx, tx, studentID, bundle.Source, bundle.SourceIDs); err != nil {
		return 0, 0, err
	}

	mergedLessons := 0
	mergedGrades := 0
	for _, lesson := range bundle.Lessons {
		lessonID, err := upsertLesson(ctx, tx, studentID, lesson)
		if err != nil {
			return 0, 0, err
		}
		mergedLessons++
		if err := upsertLessonTopic(ctx, tx, lessonID, lesson.TopicTitle); err != nil {
			return 0, 0, err
		}
		if err := upsertHomework(ctx, tx, studentID, lessonID, lesson.Homework); err != nil {
			return 0, 0, err
		}
		count, err := replaceGrades(ctx, tx, studentID, lessonID, lesson.Grades)
		if err != nil {
			return 0, 0, err
		}
		mergedGrades += count
	}

	for _, event := range bundle.Attendance {
		if err := upsertAttendance(ctx, tx, studentID, event); err != nil {
			return 0, 0, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, 0, err
	}
	return mergedLessons, mergedGrades, nil
}

func (r *PostgresRepository) MarkMerged(ctx context.Context, batchID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `UPDATE ingest_batches SET status = 'merged' WHERE id = $1`, batchID)
	return err
}

func upsertProfile(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, profile CanonicalProfile) error {
	_, err := tx.Exec(ctx, `
		UPDATE student_profiles
		SET first_name = COALESCE(NULLIF($1, ''), first_name),
			last_name = COALESCE(NULLIF($2, ''), last_name),
			grade_level = CASE WHEN $3 BETWEEN 1 AND 12 THEN $3 ELSE grade_level END,
			class_label = COALESCE(NULLIF($4, ''), class_label),
			updated_at = NOW()
		WHERE student_id = $5
	`, profile.FirstName, profile.LastName, profile.GradeLevel, profile.ClassLabel, studentID)
	return err
}

func upsertSourceIDs(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, source string, sourceIDs map[string]string) error {
	if len(sourceIDs) == 0 {
		return nil
	}
	var diaryAccountID uuid.UUID
	if err := tx.QueryRow(ctx, `SELECT id FROM diary_accounts WHERE student_id = $1 AND source = $2`, studentID, strings.ToLower(strings.TrimSpace(source))).Scan(&diaryAccountID); err != nil {
		return err
	}
	for key, value := range sourceIDs {
		if strings.TrimSpace(key) == "" || strings.TrimSpace(value) == "" {
			continue
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO diary_source_ids (diary_account_id, id_key, id_value, discovered_at)
			VALUES ($1, $2, $3, NOW())
			ON CONFLICT (diary_account_id, id_key, id_value) DO NOTHING
		`, diaryAccountID, key, value); err != nil {
			return err
		}
	}
	return nil
}

func upsertLesson(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, lesson CanonicalLesson) (uuid.UUID, error) {
	var lessonID uuid.UUID
	err := tx.QueryRow(ctx, `
		INSERT INTO lessons (student_id, source_lesson_key, lesson_date, lesson_number, subject_name, lesson_place, start_time, end_time, source_updated_at, updated_at)
		VALUES ($1, $2, $3::date, $4, $5, $6, NULLIF($7, '')::time, NULLIF($8, '')::time, NOW(), NOW())
		ON CONFLICT (student_id, source_lesson_key)
		DO UPDATE SET lesson_date = EXCLUDED.lesson_date,
			lesson_number = EXCLUDED.lesson_number,
			subject_name = EXCLUDED.subject_name,
			lesson_place = EXCLUDED.lesson_place,
			start_time = EXCLUDED.start_time,
			end_time = EXCLUDED.end_time,
			source_updated_at = NOW(),
			updated_at = NOW()
		RETURNING id
	`, studentID, lesson.SourceLessonKey, lesson.Date, lesson.LessonNumber, lesson.SubjectName, lesson.LessonPlace, lesson.StartTime, lesson.EndTime).Scan(&lessonID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("upsert lesson failed: %w", err)
	}
	return lessonID, nil
}

func upsertLessonTopic(ctx context.Context, tx pgx.Tx, lessonID uuid.UUID, title string) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO lesson_topics (lesson_id, topic_index, title, description)
		VALUES ($1, 1, COALESCE(NULLIF($2, ''), 'N/A'), '')
		ON CONFLICT (lesson_id, topic_index)
		DO UPDATE SET title = EXCLUDED.title
	`, lessonID, title)
	return err
}

func upsertHomework(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, lessonID uuid.UUID, hw HomeworkPayload) error {
	if strings.TrimSpace(hw.SourceHomeworkKey) == "" && strings.TrimSpace(hw.Description) == "" && !hw.RequiresPhoto {
		return nil
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO homeworks (student_id, lesson_id, source_homework_key, description, requires_photo, updated_at)
		VALUES ($1, $2, NULLIF($3, ''), COALESCE($4, ''), $5, NOW())
		ON CONFLICT (lesson_id)
		DO UPDATE SET source_homework_key = EXCLUDED.source_homework_key,
			description = EXCLUDED.description,
			requires_photo = EXCLUDED.requires_photo,
			updated_at = NOW()
	`, studentID, lessonID, hw.SourceHomeworkKey, hw.Description, hw.RequiresPhoto)
	return err
}

func replaceGrades(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, lessonID uuid.UUID, grades []GradePayload) (int, error) {
	if len(grades) == 0 {
		return 0, nil
	}

	keyed, keys, unkeyed := splitGradesForReconcile(grades)

	if len(keyed) > 0 {
		if _, err := tx.Exec(ctx, `
			DELETE FROM grades
			WHERE student_id = $1
			  AND lesson_id = $2
			  AND source_grade_key IS NOT NULL
			  AND NOT (source_grade_key = ANY($3::text[]))
		`, studentID, lessonID, keys); err != nil {
			return 0, err
		}
	}
	if len(unkeyed) > 0 {
		if _, err := tx.Exec(ctx, `
			DELETE FROM grades
			WHERE student_id = $1
			  AND lesson_id = $2
			  AND source_grade_key IS NULL
		`, studentID, lessonID); err != nil {
			return 0, err
		}
	}

	count := 0
	for _, grade := range keyed {
		_, err := tx.Exec(ctx, `
			INSERT INTO grades (student_id, lesson_id, source_grade_key, grade_type, grade_value, grade_mood, is_absent, created_at, updated_at)
			VALUES ($1, $2, NULLIF($3, ''), COALESCE(NULLIF($4, ''), 'regular'), $5, NULLIF($6, ''), $7, NOW(), NOW())
			ON CONFLICT (student_id, source_grade_key)
			DO UPDATE SET lesson_id = EXCLUDED.lesson_id,
				grade_type = EXCLUDED.grade_type,
				grade_value = EXCLUDED.grade_value,
				grade_mood = EXCLUDED.grade_mood,
				is_absent = EXCLUDED.is_absent,
				updated_at = NOW()
		`, studentID, lessonID, grade.SourceGradeKey, grade.Type, grade.Value, grade.Mood, grade.IsAbsent)
		if err != nil {
			return 0, err
		}
		count++
	}
	for _, grade := range unkeyed {
		_, err := tx.Exec(ctx, `
			INSERT INTO grades (student_id, lesson_id, source_grade_key, grade_type, grade_value, grade_mood, is_absent, created_at, updated_at)
			VALUES ($1, $2, NULL, COALESCE(NULLIF($3, ''), 'regular'), $4, NULLIF($5, ''), $6, NOW(), NOW())
		`, studentID, lessonID, grade.Type, grade.Value, grade.Mood, grade.IsAbsent)
		if err != nil {
			return 0, err
		}
		count++
	}
	return count, nil
}

func splitGradesForReconcile(grades []GradePayload) (keyed []GradePayload, keys []string, unkeyed []GradePayload) {
	keyed = make([]GradePayload, 0, len(grades))
	unkeyed = make([]GradePayload, 0, len(grades))
	keys = make([]string, 0, len(grades))
	for _, grade := range grades {
		if strings.TrimSpace(grade.Value) == "" {
			continue
		}
		grade.SourceGradeKey = strings.TrimSpace(grade.SourceGradeKey)
		if grade.SourceGradeKey == "" {
			unkeyed = append(unkeyed, grade)
			continue
		}
		keyed = append(keyed, grade)
		keys = append(keys, grade.SourceGradeKey)
	}
	return keyed, keys, unkeyed
}

func upsertAttendance(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, event AttendanceEvent) error {
	if strings.TrimSpace(event.SourceEventKey) != "" {
		_, err := tx.Exec(ctx, `
			INSERT INTO attendance_events (student_id, source_event_key, event_date, attendance_code, reason, created_at)
			VALUES ($1, $2, $3::date, $4, COALESCE($5, ''), NOW())
			ON CONFLICT (student_id, source_event_key)
			DO UPDATE SET attendance_code = EXCLUDED.attendance_code, reason = EXCLUDED.reason
		`, studentID, event.SourceEventKey, event.Date, event.Code, event.Reason)
		return err
	}
	if _, err := tx.Exec(ctx, `
		DELETE FROM attendance_events
		WHERE student_id = $1
		  AND source_event_key IS NULL
		  AND event_date = $2::date
		  AND attendance_code = $3
	`, studentID, event.Date, event.Code); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO attendance_events (student_id, event_date, attendance_code, reason, created_at)
		VALUES ($1, $2::date, $3, COALESCE($4, ''), NOW())
	`, studentID, event.Date, event.Code, event.Reason)
	return err
}
