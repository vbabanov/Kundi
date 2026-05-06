package diary_ingest

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type MergeStatsV2 struct {
	MergedLessons    int
	MergedResults    int
	MergedAggregates int
	MergedAttendance int
	InsertedEvidence int
}

func (r *PostgresRepository) CreateBatchV2(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundleV2, checksum string) (uuid.UUID, bool, error) {
	payload, _ := json.Marshal(bundle)
	var batchID uuid.UUID
	provider := strings.ToLower(strings.TrimSpace(bundle.Identity.Provider))
	if provider == "" {
		provider = strings.ToLower(strings.TrimSpace(bundle.Source))
	}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO ingest_batches (student_id, provider, idempotency_key, bundle_checksum, bundle_version, status, request_payload, ingested_at)
		VALUES ($1, $2, $3, $4, 2, 'accepted', $5, NOW())
		ON CONFLICT (student_id, idempotency_key) DO NOTHING
		RETURNING id
	`, studentID, provider, bundle.IdempotencyKey, checksum, payload).Scan(&batchID)
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

func (r *PostgresRepository) MergeBundleV2(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundleV2) (MergeStatsV2, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return MergeStatsV2{}, err
	}
	defer tx.Rollback(ctx)

	stats := MergeStatsV2{}

	if err := upsertProviderIdentitySnapshotV2(ctx, tx, studentID, bundle.Identity); err != nil {
		return MergeStatsV2{}, err
	}
	if err := upsertLocalAppProfileV2(ctx, tx, studentID, bundle.LocalAppProfile); err != nil {
		return MergeStatsV2{}, err
	}

	lessonIDsByRef := make(map[string]uuid.UUID, len(bundle.Lessons)*2)
	for _, lesson := range bundle.Lessons {
		lessonID, err := upsertLessonV2(ctx, tx, studentID, bundle.Identity.Provider, lesson)
		if err != nil {
			return MergeStatsV2{}, err
		}
		stats.MergedLessons++
		lessonIDsByRef[lesson.SourceLessonKey] = lessonID
		if lesson.ProviderLessonID != "" {
			lessonIDsByRef[lesson.ProviderLessonID] = lessonID
		}

		if err := upsertLessonTopic(ctx, tx, lessonID, lesson.Theme); err != nil {
			return MergeStatsV2{}, err
		}
		if err := upsertHomework(ctx, tx, studentID, lessonID, HomeworkPayload{
			SourceHomeworkKey: "",
			Description:       lesson.HomeworkText,
			RequiresPhoto:     lesson.RequiresPhoto,
		}); err != nil {
			return MergeStatsV2{}, err
		}
	}

	resultEvidenceByRef := indexEvidenceByResultRef(bundle.Evidence)
	aggregateEvidenceByRef := indexEvidenceByAggregateRef(bundle.Evidence)

	for _, incoming := range bundle.Results {
		lessonID := uuid.Nil
		if incoming.LessonRefKey != "" {
			if value, ok := lessonIDsByRef[incoming.LessonRefKey]; ok {
				lessonID = value
			}
		}

		resID, existed, changed, err := upsertAcademicResultV2(ctx, tx, studentID, bundle.Identity, lessonID, incoming, resultEvidenceByRef[incoming.SourceResultKey])
		if err != nil {
			return MergeStatsV2{}, err
		}
		if existed || !existed {
			stats.MergedResults++
		}

		ev, hasEvidence := resultEvidenceByRef[incoming.SourceResultKey]
		if !hasEvidence {
			ev = buildSyntheticResultEvidence(bundle.Identity.Provider, bundle.Identity.ProviderPersonID, incoming)
		}
		if changed || existed {
			inserted, err := insertResultEvidenceV2(ctx, tx, studentID, bundle.Identity.Provider, resID, uuid.Nil, ev)
			if err != nil {
				return MergeStatsV2{}, err
			}
			if inserted {
				stats.InsertedEvidence++
			}
		}
	}

	for _, incoming := range bundle.Aggregates {
		aggID, existed, changed, err := upsertAcademicAggregateV2(ctx, tx, studentID, bundle.Identity, incoming, aggregateEvidenceByRef[incoming.SourceAggregateKey])
		if err != nil {
			return MergeStatsV2{}, err
		}
		if existed || !existed {
			stats.MergedAggregates++
		}
		ev, hasEvidence := aggregateEvidenceByRef[incoming.SourceAggregateKey]
		if !hasEvidence {
			ev = buildSyntheticAggregateEvidence(bundle.Identity.Provider, bundle.Identity.ProviderPersonID, incoming)
		}
		if changed || existed {
			inserted, err := insertResultEvidenceV2(ctx, tx, studentID, bundle.Identity.Provider, uuid.Nil, aggID, ev)
			if err != nil {
				return MergeStatsV2{}, err
			}
			if inserted {
				stats.InsertedEvidence++
			}
		}
	}

	for _, incoming := range bundle.Attendance {
		lessonID := uuid.Nil
		if incoming.ProviderLessonRef != "" {
			if value, ok := lessonIDsByRef[incoming.ProviderLessonRef]; ok {
				lessonID = value
			}
		}
		if err := upsertAttendanceV2(ctx, tx, studentID, bundle.Identity.Provider, lessonID, incoming); err != nil {
			return MergeStatsV2{}, err
		}
		stats.MergedAttendance++
	}

	if err := tx.Commit(ctx); err != nil {
		return MergeStatsV2{}, err
	}
	return stats, nil
}

func upsertProviderIdentitySnapshotV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, identity CanonicalProviderIdentityV2) error {
	provider := strings.ToLower(strings.TrimSpace(identity.Provider))
	_, err := tx.Exec(ctx, `
		INSERT INTO provider_identity_snapshots (
			student_id, provider, provider_account_ref, provider_person_id, provider_school_id, provider_group_id,
			school_name, class_label, class_teacher_full_name, student_full_name, captured_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), NOW())
		ON CONFLICT (student_id, provider)
		DO UPDATE SET
			provider_account_ref = COALESCE(NULLIF(EXCLUDED.provider_account_ref, ''), provider_identity_snapshots.provider_account_ref),
			provider_person_id = COALESCE(NULLIF(EXCLUDED.provider_person_id, ''), provider_identity_snapshots.provider_person_id),
			provider_school_id = COALESCE(NULLIF(EXCLUDED.provider_school_id, ''), provider_identity_snapshots.provider_school_id),
			provider_group_id = COALESCE(NULLIF(EXCLUDED.provider_group_id, ''), provider_identity_snapshots.provider_group_id),
			school_name = COALESCE(NULLIF(EXCLUDED.school_name, ''), provider_identity_snapshots.school_name),
			class_label = COALESCE(NULLIF(EXCLUDED.class_label, ''), provider_identity_snapshots.class_label),
			class_teacher_full_name = COALESCE(NULLIF(EXCLUDED.class_teacher_full_name, ''), provider_identity_snapshots.class_teacher_full_name),
			student_full_name = COALESCE(NULLIF(EXCLUDED.student_full_name, ''), provider_identity_snapshots.student_full_name),
			captured_at = NOW(),
			updated_at = NOW()
	`, studentID, provider, identity.ProviderAccountRef, identity.ProviderPersonID, identity.ProviderSchoolID, identity.ProviderGroupID, identity.SchoolName, identity.ClassLabel, identity.ClassTeacherFullName, identity.StudentFullName)
	return err
}

func upsertLocalAppProfileV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, local *CanonicalLocalAppProfileV2) error {
	if local == nil {
		return nil
	}
	var shift any = nil
	if local.Shift != nil {
		shift = *local.Shift
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO student_app_profiles(student_id, shift, parent_phone_1, parent_phone_2, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (student_id)
		DO UPDATE SET
			shift = COALESCE(EXCLUDED.shift, student_app_profiles.shift),
			parent_phone_1 = COALESCE(NULLIF(EXCLUDED.parent_phone_1, ''), student_app_profiles.parent_phone_1),
			parent_phone_2 = COALESCE(NULLIF(EXCLUDED.parent_phone_2, ''), student_app_profiles.parent_phone_2),
			updated_at = NOW()
	`, studentID, shift, strings.TrimSpace(local.ParentPhone1), strings.TrimSpace(local.ParentPhone2))
	return err
}

func upsertLessonV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, provider string, lesson CanonicalLessonV2) (uuid.UUID, error) {
	var lessonID uuid.UUID
	err := tx.QueryRow(ctx, `
		INSERT INTO lessons (
			student_id, provider, source_lesson_key, provider_lesson_id, provider_subject_id,
			lesson_date, lesson_number, subject_name, lesson_place, start_time, end_time, source_updated_at, updated_at
		)
		VALUES (
			$1, $2, $3, NULLIF($4, ''), $5,
			$6::date, $7, $8, $9, NULLIF($10, '')::time, NULLIF($11, '')::time, NOW(), NOW()
		)
		ON CONFLICT (student_id, source_lesson_key)
		DO UPDATE SET
			provider = EXCLUDED.provider,
			provider_lesson_id = COALESCE(NULLIF(EXCLUDED.provider_lesson_id, ''), lessons.provider_lesson_id),
			provider_subject_id = COALESCE(NULLIF(EXCLUDED.provider_subject_id, ''), lessons.provider_subject_id),
			lesson_date = EXCLUDED.lesson_date,
			lesson_number = EXCLUDED.lesson_number,
			subject_name = EXCLUDED.subject_name,
			lesson_place = EXCLUDED.lesson_place,
			start_time = EXCLUDED.start_time,
			end_time = EXCLUDED.end_time,
			source_updated_at = NOW(),
			updated_at = NOW()
		RETURNING id
	`, studentID, provider, lesson.SourceLessonKey, lesson.ProviderLessonID, lesson.ProviderSubjectID, lesson.Date, lesson.LessonNumber, lesson.SubjectName, lesson.LessonPlace, lesson.StartTime, lesson.EndTime).Scan(&lessonID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("upsert lesson v2 failed: %w", err)
	}
	return lessonID, nil
}

func upsertAcademicResultV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, identity CanonicalProviderIdentityV2, lessonID uuid.UUID, incoming CanonicalAcademicResultV2, evidence CanonicalResultEvidenceV2) (uuid.UUID, bool, bool, error) {
	existingID, _, err := findExistingAcademicResultV2(ctx, tx, studentID, identity, lessonID, incoming)
	if err != nil {
		return uuid.Nil, false, false, err
	}
	incomingPrecedence := sourceEndpointPrecedence(evidence.SourceEndpoint)
	if existingID == uuid.Nil {
		var insertedID uuid.UUID
		err := tx.QueryRow(ctx, `
			INSERT INTO academic_results (
				student_id, provider, lesson_id, result_kind, provider_subject_id, subject_name,
				provider_work_id, provider_mark_id, source_result_key, value_text, value_numeric,
				resolved_mood, period_id, term_no, recorded_on, created_at, updated_at
			)
			VALUES (
				$1, $2, NULLIF($3::text, '')::uuid, $4, $5, $6,
				$7, $8, $9, $10, $11,
				$12, $13, $14, $15::date, NOW(), NOW()
			)
			RETURNING id
		`, studentID, identity.Provider, uuidOrEmpty(lessonID), incoming.ResultKind, incoming.ProviderSubjectID, incoming.SubjectName, incoming.ProviderWorkID, incoming.ProviderMarkID, incoming.SourceResultKey, incoming.ValueText, incoming.ValueNumeric, incoming.ResolvedMood, incoming.PeriodID, incoming.TermNo, incoming.RecordedOn).Scan(&insertedID)
		if err != nil {
			return uuid.Nil, false, false, err
		}
		return insertedID, false, true, nil
	}

	var currentSubjectID, currentSubjectName, currentMood string
	var currentLessonID *uuid.UUID
	if err := tx.QueryRow(ctx, `
		SELECT provider_subject_id, subject_name, resolved_mood, lesson_id
		FROM academic_results
		WHERE id = $1
	`, existingID).Scan(&currentSubjectID, &currentSubjectName, &currentMood, &currentLessonID); err != nil {
		return uuid.Nil, false, false, err
	}
	existingEndpoint := ""
	_ = tx.QueryRow(ctx, `
		SELECT source_endpoint
		FROM academic_result_evidence
		WHERE result_id = $1
		ORDER BY captured_at DESC
		LIMIT 1
	`, existingID).Scan(&existingEndpoint)
	existingPrecedence := sourceEndpointPrecedence(existingEndpoint)

	changed := false
	nextMood := currentMood
	if strings.TrimSpace(incoming.ResolvedMood) != "" && incomingPrecedence > existingPrecedence && incoming.ResolvedMood != currentMood {
		nextMood = incoming.ResolvedMood
		changed = true
	}

	nextLessonID := currentLessonID
	if lessonID != uuid.Nil && incomingPrecedence > existingPrecedence {
		lessonCopy := lessonID
		if currentLessonID == nil || *currentLessonID != lessonCopy {
			nextLessonID = &lessonCopy
			changed = true
		}
	}

	nextSubjectID := currentSubjectID
	if strings.TrimSpace(currentSubjectID) == "" && strings.TrimSpace(incoming.ProviderSubjectID) != "" {
		nextSubjectID = incoming.ProviderSubjectID
		changed = true
	}
	nextSubjectName := currentSubjectName
	if strings.TrimSpace(currentSubjectName) == "" && strings.TrimSpace(incoming.SubjectName) != "" {
		nextSubjectName = incoming.SubjectName
		changed = true
	}

	if changed {
		_, err := tx.Exec(ctx, `
			UPDATE academic_results
			SET lesson_id = NULLIF($2::text, '')::uuid,
				provider_subject_id = $3,
				subject_name = $4,
				resolved_mood = $5,
				updated_at = NOW()
			WHERE id = $1
		`, existingID, uuidPtrOrEmpty(nextLessonID), nextSubjectID, nextSubjectName, nextMood)
		if err != nil {
			return uuid.Nil, false, false, err
		}
	}
	return existingID, true, changed, nil
}

func findExistingAcademicResultV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, identity CanonicalProviderIdentityV2, lessonID uuid.UUID, incoming CanonicalAcademicResultV2) (uuid.UUID, bool, error) {
	if incoming.ProviderMarkID != "" {
		var id uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id
			FROM academic_results
			WHERE student_id = $1 AND provider = $2 AND provider_mark_id = $3
			LIMIT 1
		`, studentID, identity.Provider, incoming.ProviderMarkID).Scan(&id)
		if err == nil {
			return id, true, nil
		}
		if err != pgx.ErrNoRows {
			return uuid.Nil, false, err
		}
	}
	if incoming.SourceResultKey != "" {
		var id uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id
			FROM academic_results
			WHERE student_id = $1 AND provider = $2 AND source_result_key = $3
			LIMIT 1
		`, studentID, identity.Provider, incoming.SourceResultKey).Scan(&id)
		if err == nil {
			return id, true, nil
		}
		if err != pgx.ErrNoRows {
			return uuid.Nil, false, err
		}
	}
	if incoming.ResultKind == string(EventResultKindRegular) {
		var id uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id
			FROM academic_results
			WHERE student_id = $1
			  AND provider = $2
			  AND result_kind = 'regular'
			  AND provider_subject_id = $3
			  AND provider_work_id = $4
			  AND value_text = $5
			  AND recorded_on = $6::date
			  AND COALESCE(lesson_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(NULLIF($7::text, '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
			LIMIT 1
		`, studentID, identity.Provider, incoming.ProviderSubjectID, incoming.ProviderWorkID, incoming.ValueText, incoming.RecordedOn, uuidOrEmpty(lessonID)).Scan(&id)
		if err == nil {
			return id, true, nil
		}
		if err != pgx.ErrNoRows {
			return uuid.Nil, false, err
		}
	} else {
		var id uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id
			FROM academic_results
			WHERE student_id = $1
			  AND provider = $2
			  AND result_kind = $3
			  AND provider_subject_id = $4
			  AND provider_work_id = $5
			  AND COALESCE(term_no, -1) = COALESCE($6, -1)
			  AND value_text = $7
			  AND recorded_on = $8::date
			LIMIT 1
		`, studentID, identity.Provider, incoming.ResultKind, incoming.ProviderSubjectID, incoming.ProviderWorkID, incoming.TermNo, incoming.ValueText, incoming.RecordedOn).Scan(&id)
		if err == nil {
			return id, true, nil
		}
		if err != pgx.ErrNoRows {
			return uuid.Nil, false, err
		}
	}
	return uuid.Nil, false, nil
}

func upsertAcademicAggregateV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, identity CanonicalProviderIdentityV2, incoming CanonicalAcademicAggregate, evidence CanonicalResultEvidenceV2) (uuid.UUID, bool, bool, error) {
	existingID, _, err := findExistingAcademicAggregateV2(ctx, tx, studentID, identity, incoming)
	if err != nil {
		return uuid.Nil, false, false, err
	}
	incomingPrecedence := sourceEndpointPrecedence(evidence.SourceEndpoint)
	if existingID == uuid.Nil {
		var insertedID uuid.UUID
		err := tx.QueryRow(ctx, `
			INSERT INTO academic_aggregates (
				student_id, provider, result_kind, provider_subject_id, subject_name, period_id, term_no, year_label,
				value_text, value_numeric, resolved_mood, recorded_on, source_aggregate_key, created_at, updated_at
			)
			VALUES (
				$1, $2, $3, $4, $5, $6, $7, $8,
				$9, $10, $11, $12::date, $13, NOW(), NOW()
			)
			RETURNING id
		`, studentID, identity.Provider, incoming.ResultKind, incoming.ProviderSubjectID, incoming.SubjectName, incoming.PeriodID, incoming.TermNo, incoming.YearLabel, incoming.ValueText, incoming.ValueNumeric, incoming.ResolvedMood, incoming.RecordedOn, incoming.SourceAggregateKey).Scan(&insertedID)
		if err != nil {
			return uuid.Nil, false, false, err
		}
		return insertedID, false, true, nil
	}

	var currentSubjectID, currentSubjectName, currentMood string
	if err := tx.QueryRow(ctx, `
		SELECT provider_subject_id, subject_name, resolved_mood
		FROM academic_aggregates
		WHERE id = $1
	`, existingID).Scan(&currentSubjectID, &currentSubjectName, &currentMood); err != nil {
		return uuid.Nil, false, false, err
	}

	existingEndpoint := ""
	_ = tx.QueryRow(ctx, `
		SELECT source_endpoint
		FROM academic_result_evidence
		WHERE aggregate_id = $1
		ORDER BY captured_at DESC
		LIMIT 1
	`, existingID).Scan(&existingEndpoint)
	existingPrecedence := sourceEndpointPrecedence(existingEndpoint)

	changed := false
	nextMood := currentMood
	if strings.TrimSpace(incoming.ResolvedMood) != "" && incomingPrecedence > existingPrecedence && incoming.ResolvedMood != currentMood {
		nextMood = incoming.ResolvedMood
		changed = true
	}
	nextSubjectID := currentSubjectID
	if strings.TrimSpace(currentSubjectID) == "" && strings.TrimSpace(incoming.ProviderSubjectID) != "" {
		nextSubjectID = incoming.ProviderSubjectID
		changed = true
	}
	nextSubjectName := currentSubjectName
	if strings.TrimSpace(currentSubjectName) == "" && strings.TrimSpace(incoming.SubjectName) != "" {
		nextSubjectName = incoming.SubjectName
		changed = true
	}

	if changed {
		_, err := tx.Exec(ctx, `
			UPDATE academic_aggregates
			SET provider_subject_id = $2,
				subject_name = $3,
				resolved_mood = $4,
				updated_at = NOW()
			WHERE id = $1
		`, existingID, nextSubjectID, nextSubjectName, nextMood)
		if err != nil {
			return uuid.Nil, false, false, err
		}
	}
	return existingID, true, changed, nil
}

func findExistingAcademicAggregateV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, identity CanonicalProviderIdentityV2, incoming CanonicalAcademicAggregate) (uuid.UUID, bool, error) {
	if incoming.SourceAggregateKey != "" {
		var id uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id
			FROM academic_aggregates
			WHERE student_id = $1 AND provider = $2 AND source_aggregate_key = $3
			LIMIT 1
		`, studentID, identity.Provider, incoming.SourceAggregateKey).Scan(&id)
		if err == nil {
			return id, true, nil
		}
		if err != pgx.ErrNoRows {
			return uuid.Nil, false, err
		}
	}
	if incoming.ResultKind == string(AggregateResultKindTerm) {
		var id uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id
			FROM academic_aggregates
			WHERE student_id = $1
			  AND provider = $2
			  AND result_kind = 'term'
			  AND provider_subject_id = $3
			  AND COALESCE(term_no, -1) = COALESCE($4, -1)
			  AND period_id = $5
			LIMIT 1
		`, studentID, identity.Provider, incoming.ProviderSubjectID, incoming.TermNo, incoming.PeriodID).Scan(&id)
		if err == nil {
			return id, true, nil
		}
		if err != pgx.ErrNoRows {
			return uuid.Nil, false, err
		}
	} else if incoming.ResultKind == string(AggregateResultKindYear) {
		var id uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id
			FROM academic_aggregates
			WHERE student_id = $1
			  AND provider = $2
			  AND result_kind = 'year'
			  AND provider_subject_id = $3
			  AND year_label = $4
			LIMIT 1
		`, studentID, identity.Provider, incoming.ProviderSubjectID, incoming.YearLabel).Scan(&id)
		if err == nil {
			return id, true, nil
		}
		if err != pgx.ErrNoRows {
			return uuid.Nil, false, err
		}
	}
	return uuid.Nil, false, nil
}

func upsertAttendanceV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, provider string, lessonID uuid.UUID, incoming CanonicalAttendanceEventV2) error {
	normalized := normalizeAttendanceStatus(incoming.RawCode, incoming.NormalizedStatus)
	sourceEventKey := strings.TrimSpace(incoming.SourceEventKey)
	providerEventKey := strings.TrimSpace(incoming.ProviderEventKey)
	if providerEventKey == "" {
		providerEventKey = sourceEventKey
	}

	if providerEventKey != "" {
		var existingID uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT id
			FROM attendance_events
			WHERE student_id = $1 AND provider = $2 AND provider_event_key = $3
			LIMIT 1
		`, studentID, provider, providerEventKey).Scan(&existingID)
		if err == nil {
			_, err = tx.Exec(ctx, `
				UPDATE attendance_events
				SET lesson_id = NULLIF($2::text, '')::uuid,
					source_event_key = COALESCE(NULLIF($3, ''), source_event_key),
					event_date = $4::date,
					recorded_on = $4::date,
					attendance_code = $5,
					raw_code = $6,
					normalized_status = $5,
					reason = $7,
					provider_subject_id = $8,
					subject_name = $9,
					lesson_number = $10
				WHERE id = $1
			`, existingID, uuidOrEmpty(lessonID), sourceEventKey, incoming.RecordedOn, normalized, incoming.RawCode, incoming.Reason, incoming.ProviderSubjectID, incoming.SubjectName, incoming.LessonNumber)
			return err
		}
		if err != pgx.ErrNoRows {
			return err
		}
	}

	_, err := tx.Exec(ctx, `
		INSERT INTO attendance_events (
			student_id, provider, lesson_id, source_event_key, provider_event_key,
			event_date, recorded_on, attendance_code, raw_code, normalized_status, reason, provider_subject_id, subject_name, lesson_number, created_at
		)
		VALUES (
			$1, $2, NULLIF($3::text, '')::uuid, NULLIF($4, ''), NULLIF($5, ''),
			$6::date, $6::date, $7, $8, $7, $9, $10, $11, $12, NOW()
		)
	`, studentID, provider, uuidOrEmpty(lessonID), sourceEventKey, providerEventKey, incoming.RecordedOn, normalized, incoming.RawCode, incoming.Reason, incoming.ProviderSubjectID, incoming.SubjectName, incoming.LessonNumber)
	return err
}

func indexEvidenceByResultRef(items []CanonicalResultEvidenceV2) map[string]CanonicalResultEvidenceV2 {
	out := make(map[string]CanonicalResultEvidenceV2, len(items))
	for _, item := range items {
		key := strings.TrimSpace(item.SourceResultRefKey)
		if key == "" {
			continue
		}
		out[key] = item
	}
	return out
}

func indexEvidenceByAggregateRef(items []CanonicalResultEvidenceV2) map[string]CanonicalResultEvidenceV2 {
	out := make(map[string]CanonicalResultEvidenceV2, len(items))
	for _, item := range items {
		key := strings.TrimSpace(item.SourceAggregateRefKey)
		if key == "" {
			continue
		}
		out[key] = item
	}
	return out
}

func insertResultEvidenceV2(ctx context.Context, tx pgx.Tx, studentID uuid.UUID, provider string, resultID uuid.UUID, aggregateID uuid.UUID, incoming CanonicalResultEvidenceV2) (bool, error) {
	fingerprint := strings.TrimSpace(incoming.FingerprintSHA256)
	if fingerprint == "" {
		return false, nil
	}
	resID := uuidOrEmpty(resultID)
	aggID := uuidOrEmpty(aggregateID)
	tag, err := tx.Exec(ctx, `
		INSERT INTO academic_result_evidence (
			student_id, provider, result_id, aggregate_id, source_endpoint, provider_work_id,
			provider_mark_id, provider_payload_path, source_mood_raw, fingerprint_sha256, captured_at
		)
		VALUES (
			$1, $2, NULLIF($3::text, '')::uuid, NULLIF($4::text, '')::uuid, $5, $6,
			$7, $8, $9, $10, NOW()
		)
		ON CONFLICT DO NOTHING
	`, studentID, provider, resID, aggID, incoming.SourceEndpoint, incoming.ProviderWorkID, incoming.ProviderMarkID, incoming.ProviderPayloadPath, incoming.SourceMoodRaw, fingerprint)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

func sourceEndpointPrecedence(endpoint string) int {
	switch strings.ToLower(strings.TrimSpace(endpoint)) {
	case "diary":
		return 30
	case "period":
		return 20
	case "final":
		return 10
	default:
		return 0
	}
}

func normalizeAttendanceStatus(rawCode string, normalized string) string {
	value := strings.ToLower(strings.TrimSpace(normalized))
	if value != "" {
		switch value {
		case "present", "absent", "late", "excused", "unknown":
			return value
		}
	}
	raw := strings.ToLower(strings.TrimSpace(rawCode))
	switch raw {
	case "н", "absent":
		return "absent"
	case "б", "бол", "sick", "ill", "excused":
		return "excused"
	case "о", "late":
		return "late"
	case "п", "+", "present":
		return "present"
	default:
		return "unknown"
	}
}

func buildSyntheticResultEvidence(provider string, providerPersonID string, res CanonicalAcademicResultV2) CanonicalResultEvidenceV2 {
	fingerprint := digest(
		"result",
		provider,
		providerPersonID,
		res.ResultKind,
		res.ProviderSubjectID,
		res.ProviderWorkID,
		res.ProviderMarkID,
		res.SourceResultKey,
		res.ValueText,
		res.RecordedOn,
		intPtrString(res.TermNo),
		res.LessonRefKey,
	)
	return CanonicalResultEvidenceV2{
		SourceResultRefKey: res.SourceResultKey,
		SourceEndpoint:     "unknown",
		ProviderWorkID:     res.ProviderWorkID,
		ProviderMarkID:     res.ProviderMarkID,
		SourceMoodRaw:      res.ResolvedMood,
		FingerprintSHA256:  fingerprint,
	}
}

func buildSyntheticAggregateEvidence(provider string, providerPersonID string, agg CanonicalAcademicAggregate) CanonicalResultEvidenceV2 {
	fingerprint := digest(
		"aggregate",
		provider,
		providerPersonID,
		agg.ResultKind,
		agg.ProviderSubjectID,
		agg.SourceAggregateKey,
		agg.PeriodID,
		agg.YearLabel,
		agg.ValueText,
		agg.RecordedOn,
		intPtrString(agg.TermNo),
	)
	return CanonicalResultEvidenceV2{
		SourceAggregateRefKey: agg.SourceAggregateKey,
		SourceEndpoint:        "unknown",
		SourceMoodRaw:         agg.ResolvedMood,
		FingerprintSHA256:     fingerprint,
	}
}

func digest(parts ...string) string {
	joined := strings.Join(parts, "|")
	sum := sha256.Sum256([]byte(joined))
	return hex.EncodeToString(sum[:])
}

func uuidOrEmpty(value uuid.UUID) string {
	if value == uuid.Nil {
		return ""
	}
	return value.String()
}

func uuidPtrOrEmpty(value *uuid.UUID) string {
	if value == nil || *value == uuid.Nil {
		return ""
	}
	return value.String()
}

func intPtrString(value *int) string {
	if value == nil {
		return ""
	}
	return fmt.Sprintf("%d", *value)
}
