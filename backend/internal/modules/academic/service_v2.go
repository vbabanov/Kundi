package academic

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/kundi/kundi/backend/internal/contracts"
)

const (
	defaultOverviewRecentResultsLimit = 5
	defaultOverviewUpcomingLessons    = 8
	defaultResultsLimit               = 300
)

type ReadWindowV2 struct {
	Provider   string
	WindowFrom time.Time
	WindowTo   time.Time
	SnapshotAt time.Time
}

func DefaultReadWindowV2(provider string, now time.Time) ReadWindowV2 {
	snapshot := now.UTC()
	return ReadWindowV2{
		Provider:   normalizeProvider(provider),
		WindowFrom: snapshot.AddDate(0, 0, -30).Truncate(24 * time.Hour),
		WindowTo:   snapshot.AddDate(0, 0, 14).Truncate(24 * time.Hour),
		SnapshotAt: snapshot,
	}
}

func (w ReadWindowV2) ToDTO() contracts.ReadWindowV2DTO {
	return contracts.ReadWindowV2DTO{
		Provider:   w.Provider,
		WindowFrom: w.WindowFrom.UTC().Format("2006-01-02"),
		WindowTo:   w.WindowTo.UTC().Format("2006-01-02"),
		SnapshotAt: w.SnapshotAt.UTC().Format(time.RFC3339),
		WindowKey: fmt.Sprintf(
			"%s:%s:%s",
			w.Provider,
			w.WindowFrom.UTC().Format("2006-01-02"),
			w.WindowTo.UTC().Format("2006-01-02"),
		),
	}
}

func normalizeProvider(provider string) string {
	switch strings.ToLower(strings.TrimSpace(provider)) {
	case "dnevnikru":
		return "dnevnikru"
	case "edupage":
		return "edupage"
	default:
		return "kundelik"
	}
}

func (s *Service) ProfileV2(ctx context.Context, studentID uuid.UUID, window ReadWindowV2) (contracts.ProfileV2DTO, error) {
	ctx, tags, startedAt, finish := s.observeRead(ctx, "profile", window.Provider)
	var observeErr error
	defer func() { finish(startedAt, tags, observeErr) }()

	identity, err := s.providerIdentity(ctx, studentID, window.Provider)
	if err != nil {
		observeErr = err
		return contracts.ProfileV2DTO{}, err
	}
	local, err := s.localAppProfile(ctx, studentID)
	if err != nil {
		observeErr = err
		return contracts.ProfileV2DTO{}, err
	}
	return contracts.ProfileV2DTO{
		Window:           window.ToDTO(),
		ProviderIdentity: identity,
		LocalAppProfile:  local,
	}, nil
}

func (s *Service) OverviewV2(ctx context.Context, studentID uuid.UUID, window ReadWindowV2) (contracts.AcademicOverviewV2DTO, error) {
	ctx, tags, startedAt, finish := s.observeRead(ctx, "overview", window.Provider)
	var observeErr error
	defer func() { finish(startedAt, tags, observeErr) }()

	identity, err := s.providerIdentity(ctx, studentID, window.Provider)
	if err != nil {
		observeErr = err
		return contracts.AcademicOverviewV2DTO{}, err
	}
	local, err := s.localAppProfile(ctx, studentID)
	if err != nil {
		observeErr = err
		return contracts.AcademicOverviewV2DTO{}, err
	}
	counts, err := s.overviewCounts(ctx, studentID, window)
	if err != nil {
		observeErr = err
		return contracts.AcademicOverviewV2DTO{}, err
	}
	highlights, err := s.overviewHighlights(ctx, studentID, window)
	if err != nil {
		observeErr = err
		return contracts.AcademicOverviewV2DTO{}, err
	}
	return contracts.AcademicOverviewV2DTO{
		Window:           window.ToDTO(),
		ProviderIdentity: identity,
		LocalAppProfile:  local,
		Counts:           counts,
		Highlights:       highlights,
	}, nil
}

func (s *Service) ResultsV2(ctx context.Context, studentID uuid.UUID, window ReadWindowV2, limit int) (contracts.AcademicResultsResponseV2DTO, error) {
	ctx, tags, startedAt, finish := s.observeRead(ctx, "results", window.Provider)
	var observeErr error
	defer func() { finish(startedAt, tags, observeErr) }()

	if limit <= 0 || limit > 1000 {
		limit = defaultResultsLimit
	}
	lessons, err := s.resultsLessons(ctx, studentID, window, limit)
	if err != nil {
		observeErr = err
		return contracts.AcademicResultsResponseV2DTO{}, err
	}
	results, err := s.eventResults(ctx, studentID, window, limit)
	if err != nil {
		observeErr = err
		return contracts.AcademicResultsResponseV2DTO{}, err
	}
	aggregates, err := s.aggregates(ctx, studentID, window, limit)
	if err != nil {
		observeErr = err
		return contracts.AcademicResultsResponseV2DTO{}, err
	}
	attendance, err := s.attendance(ctx, studentID, window, limit)
	if err != nil {
		observeErr = err
		return contracts.AcademicResultsResponseV2DTO{}, err
	}
	return contracts.AcademicResultsResponseV2DTO{
		Window:     window.ToDTO(),
		Lessons:    lessons,
		Results:    results,
		Aggregates: aggregates,
		Attendance: attendance,
	}, nil
}

func (s *Service) providerIdentity(ctx context.Context, studentID uuid.UUID, provider string) (out contracts.ProviderIdentityV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "provider_identity_snapshot", "profile_overview", provider)
	defer func() { finish(retErr) }()

	err := s.pool.QueryRow(ctx, `
		SELECT provider, provider_account_ref, provider_person_id, provider_school_id, provider_group_id,
		       student_full_name, school_name, class_label, class_teacher_full_name
		FROM provider_identity_snapshots
		WHERE student_id = $1 AND provider = $2
	`, studentID, provider).Scan(
		&out.Provider,
		&out.ProviderAccountRef,
		&out.ProviderPersonID,
		&out.ProviderSchoolID,
		&out.ProviderGroupID,
		&out.StudentFullName,
		&out.SchoolName,
		&out.ClassLabel,
		&out.ClassTeacherFullName,
	)
	if err == nil {
		return out, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		retErr = err
		return contracts.ProviderIdentityV2DTO{}, retErr
	}

	// Backward-compatible fallback for accounts that only ingested v1 bundle data.
	// We keep provider fields and source ids when available so v2 read path can stay operational.
	out = contracts.ProviderIdentityV2DTO{
		Provider: provider,
	}

	var firstName, lastName, classLabel, schoolName string
	legacyErr := s.pool.QueryRow(ctx, `
		SELECT COALESCE(sp.first_name, ''), COALESCE(sp.last_name, ''), COALESCE(sp.class_label, ''), COALESCE(s.name, '')
		FROM student_profiles sp
		LEFT JOIN schools s ON s.id = sp.school_id
		WHERE sp.student_id = $1
	`, studentID).Scan(&firstName, &lastName, &classLabel, &schoolName)
	if legacyErr != nil && !errors.Is(legacyErr, pgx.ErrNoRows) {
		retErr = legacyErr
		return contracts.ProviderIdentityV2DTO{}, retErr
	}
	s.metrics.Incr("backend.read.fallback_total", map[string]string{
		"path":     "typed_v2_read",
		"endpoint": "profile_overview",
		"provider": provider,
		"stage":    "active",
		"fallback": "provider_identity_legacy_profile",
		"degraded": "true",
	})

	fullName := strings.TrimSpace(strings.TrimSpace(firstName + " " + lastName))
	out.StudentFullName = fullName
	out.SchoolName = schoolName
	out.ClassLabel = classLabel
	out.ProviderPersonID = s.latestSourceIDValue(ctx, studentID, provider, "person_id")
	out.ProviderSchoolID = s.latestSourceIDValue(ctx, studentID, provider, "school_id")
	out.ProviderGroupID = s.latestSourceIDValue(ctx, studentID, provider, "group_id")
	if accountRef, ok := s.latestDiaryAccountRef(ctx, studentID, provider); ok {
		out.ProviderAccountRef = accountRef
	}

	return out, nil
}

func (s *Service) latestDiaryAccountRef(ctx context.Context, studentID uuid.UUID, provider string) (string, bool) {
	var accountID string
	err := s.pool.QueryRow(ctx, `
		SELECT id::text
		FROM diary_accounts
		WHERE student_id = $1 AND source = $2
		ORDER BY updated_at DESC
		LIMIT 1
	`, studentID, provider).Scan(&accountID)
	if err != nil {
		return "", false
	}
	return accountID, true
}

func (s *Service) latestSourceIDValue(ctx context.Context, studentID uuid.UUID, provider, key string) string {
	var value string
	err := s.pool.QueryRow(ctx, `
		SELECT dsi.id_value
		FROM diary_source_ids dsi
		JOIN diary_accounts da ON da.id = dsi.diary_account_id
		WHERE da.student_id = $1 AND da.source = $2 AND dsi.id_key = $3
		ORDER BY dsi.discovered_at DESC
		LIMIT 1
	`, studentID, provider, key).Scan(&value)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(value)
}

func (s *Service) localAppProfile(ctx context.Context, studentID uuid.UUID) (out *contracts.LocalAppProfileV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "local_app_profile", "profile", "")
	defer func() { finish(retErr) }()

	var shift *int
	var p1, p2 string
	err := s.pool.QueryRow(ctx, `
		SELECT shift, parent_phone_1, parent_phone_2
		FROM student_app_profiles
		WHERE student_id = $1
	`, studentID).Scan(&shift, &p1, &p2)
	if err != nil {
		// Keep legacy behavior for profile read compatibility:
		// local profile lookup failures are treated as "not available".
		retErr = nil
		return nil, nil
	}
	out = &contracts.LocalAppProfileV2DTO{
		Shift:        shift,
		ParentPhone1: p1,
		ParentPhone2: p2,
	}
	return out, nil
}

func (s *Service) overviewCounts(ctx context.Context, studentID uuid.UUID, window ReadWindowV2) (out contracts.AcademicOverviewCountsV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "overview_counts", "overview", window.Provider)
	defer func() { finish(retErr) }()

	retErr = s.pool.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*)
			 FROM lessons
			 WHERE student_id = $1 AND provider = $2 AND lesson_date BETWEEN $3::date AND $4::date),
			(SELECT COUNT(*)
			 FROM academic_results
			 WHERE student_id = $1 AND provider = $2 AND recorded_on BETWEEN $3::date AND $4::date),
			(SELECT COUNT(*)
			 FROM academic_aggregates
			 WHERE student_id = $1 AND provider = $2 AND recorded_on BETWEEN $3::date AND $4::date),
			(SELECT COUNT(*)
			 FROM attendance_events
			 WHERE student_id = $1 AND provider = $2
			   AND recorded_on BETWEEN $3::date AND $4::date
			   AND normalized_status IN ('absent', 'late'))
	`, studentID, window.Provider, window.WindowFrom.Format("2006-01-02"), window.WindowTo.Format("2006-01-02")).Scan(
		&out.LessonsInWindow,
		&out.ResultsInWindow,
		&out.AggregatesInWindow,
		&out.AttendanceAlerts,
	)
	return out, retErr
}

func (s *Service) overviewHighlights(ctx context.Context, studentID uuid.UUID, window ReadWindowV2) (contracts.AcademicOverviewHighlightsV2DTO, error) {
	recent, err := s.recentResultHighlights(ctx, studentID, window, defaultOverviewRecentResultsLimit)
	if err != nil {
		return contracts.AcademicOverviewHighlightsV2DTO{}, err
	}
	upcoming, err := s.upcomingLessonHighlights(ctx, studentID, window, defaultOverviewUpcomingLessons)
	if err != nil {
		return contracts.AcademicOverviewHighlightsV2DTO{}, err
	}
	return contracts.AcademicOverviewHighlightsV2DTO{
		RecentResults:   recent,
		UpcomingLessons: upcoming,
	}, nil
}

func (s *Service) recentResultHighlights(ctx context.Context, studentID uuid.UUID, window ReadWindowV2, limit int) (out []contracts.ResultHighlightV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "recent_results", "overview", window.Provider)
	defer func() { finish(retErr) }()

	rows, err := s.pool.Query(ctx, `
		SELECT id::text, result_kind, subject_name, value_text, TO_CHAR(recorded_on, 'YYYY-MM-DD'), resolved_mood
		FROM academic_results
		WHERE student_id = $1
		  AND provider = $2
		  AND recorded_on BETWEEN $3::date AND $4::date
		ORDER BY recorded_on DESC, updated_at DESC
		LIMIT $5
	`, studentID, window.Provider, window.WindowFrom.Format("2006-01-02"), window.WindowTo.Format("2006-01-02"), limit)
	if err != nil {
		retErr = err
		return nil, retErr
	}
	defer rows.Close()
	out = make([]contracts.ResultHighlightV2DTO, 0, limit)
	for rows.Next() {
		var item contracts.ResultHighlightV2DTO
		if err := rows.Scan(&item.ResultID, &item.ResultKind, &item.SubjectName, &item.ValueText, &item.RecordedOn, &item.ResolvedMood); err != nil {
			retErr = err
			return nil, retErr
		}
		out = append(out, item)
	}
	retErr = rows.Err()
	return out, retErr
}

func (s *Service) upcomingLessonHighlights(ctx context.Context, studentID uuid.UUID, window ReadWindowV2, limit int) (out []contracts.LessonHighlightV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "upcoming_lessons", "overview", window.Provider)
	defer func() { finish(retErr) }()

	rows, err := s.pool.Query(ctx, `
		SELECT l.id::text, TO_CHAR(l.lesson_date, 'YYYY-MM-DD'), l.lesson_number, l.subject_name,
		       COALESCE(lt.title, ''), COALESCE(h.description, '')
		FROM lessons l
		LEFT JOIN lesson_topics lt ON lt.lesson_id = l.id AND lt.topic_index = 1
		LEFT JOIN homeworks h ON h.lesson_id = l.id
		WHERE l.student_id = $1
		  AND l.provider = $2
		  AND l.lesson_date BETWEEN $3::date AND $4::date
		  AND l.lesson_date >= $5::date
		ORDER BY l.lesson_date ASC, l.lesson_number ASC
		LIMIT $6
	`, studentID, window.Provider, window.WindowFrom.Format("2006-01-02"), window.WindowTo.Format("2006-01-02"), window.SnapshotAt.Format("2006-01-02"), limit)
	if err != nil {
		retErr = err
		return nil, retErr
	}
	defer rows.Close()
	out = make([]contracts.LessonHighlightV2DTO, 0, limit)
	for rows.Next() {
		var item contracts.LessonHighlightV2DTO
		if err := rows.Scan(&item.LessonID, &item.LessonDate, &item.LessonNumber, &item.SubjectName, &item.Theme, &item.HomeworkText); err != nil {
			retErr = err
			return nil, retErr
		}
		out = append(out, item)
	}
	retErr = rows.Err()
	return out, retErr
}

func (s *Service) resultsLessons(ctx context.Context, studentID uuid.UUID, window ReadWindowV2, limit int) (out []contracts.AcademicLessonV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "results_lessons", "results", window.Provider)
	defer func() { finish(retErr) }()

	rows, err := s.pool.Query(ctx, `
		SELECT l.id::text, l.provider, l.provider_lesson_id, l.provider_subject_id,
		       TO_CHAR(l.lesson_date, 'YYYY-MM-DD'), l.lesson_number, l.subject_name, COALESCE(l.lesson_place, ''),
		       COALESCE(TO_CHAR(l.start_time, 'HH24:MI'), ''), COALESCE(TO_CHAR(l.end_time, 'HH24:MI'), ''),
		       COALESCE(lt.title, ''), COALESCE(h.description, ''), 'active'
		FROM lessons l
		LEFT JOIN lesson_topics lt ON lt.lesson_id = l.id AND lt.topic_index = 1
		LEFT JOIN homeworks h ON h.lesson_id = l.id
		WHERE l.student_id = $1
		  AND l.provider = $2
		  AND l.lesson_date BETWEEN $3::date AND $4::date
		ORDER BY l.lesson_date DESC, l.lesson_number DESC
		LIMIT $5
	`, studentID, window.Provider, window.WindowFrom.Format("2006-01-02"), window.WindowTo.Format("2006-01-02"), limit)
	if err != nil {
		retErr = err
		return nil, retErr
	}
	defer rows.Close()
	out = make([]contracts.AcademicLessonV2DTO, 0, limit)
	for rows.Next() {
		var item contracts.AcademicLessonV2DTO
		if err := rows.Scan(
			&item.LessonID,
			&item.Provider,
			&item.ProviderLessonID,
			&item.ProviderSubjectID,
			&item.LessonDate,
			&item.LessonNumber,
			&item.SubjectName,
			&item.LessonPlace,
			&item.StartTime,
			&item.EndTime,
			&item.Theme,
			&item.HomeworkText,
			&item.HomeworkStatus,
		); err != nil {
			retErr = err
			return nil, retErr
		}
		out = append(out, item)
	}
	retErr = rows.Err()
	return out, retErr
}

func (s *Service) eventResults(ctx context.Context, studentID uuid.UUID, window ReadWindowV2, limit int) (out []contracts.AcademicResultV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "event_results", "results", window.Provider)
	defer func() { finish(retErr) }()

	rows, err := s.pool.Query(ctx, `
		SELECT r.id::text, r.provider, r.result_kind, r.provider_work_id, r.provider_mark_id,
		       r.provider_subject_id, r.subject_name, r.value_text, r.resolved_mood, TO_CHAR(r.recorded_on, 'YYYY-MM-DD'),
		       COALESCE(ev.source_endpoint, ''), COALESCE(ev.source_mood_raw, '')
		FROM academic_results r
		LEFT JOIN LATERAL (
			SELECT source_endpoint, source_mood_raw
			FROM academic_result_evidence
			WHERE result_id = r.id
			ORDER BY captured_at DESC
			LIMIT 1
		) ev ON TRUE
		WHERE r.student_id = $1
		  AND r.provider = $2
		  AND r.recorded_on BETWEEN $3::date AND $4::date
		ORDER BY r.recorded_on DESC, r.updated_at DESC
		LIMIT $5
	`, studentID, window.Provider, window.WindowFrom.Format("2006-01-02"), window.WindowTo.Format("2006-01-02"), limit)
	if err != nil {
		retErr = err
		return nil, retErr
	}
	defer rows.Close()
	out = make([]contracts.AcademicResultV2DTO, 0, limit)
	for rows.Next() {
		var item contracts.AcademicResultV2DTO
		if err := rows.Scan(
			&item.ResultID,
			&item.Provider,
			&item.ResultKind,
			&item.ProviderWorkID,
			&item.ProviderMarkID,
			&item.ProviderSubjectID,
			&item.SubjectName,
			&item.ValueText,
			&item.ResolvedMood,
			&item.RecordedOn,
			&item.SourceEndpoint,
			&item.SourceMoodRaw,
		); err != nil {
			retErr = err
			return nil, retErr
		}
		out = append(out, item)
	}
	retErr = rows.Err()
	return out, retErr
}

func (s *Service) aggregates(ctx context.Context, studentID uuid.UUID, window ReadWindowV2, limit int) (out []contracts.AcademicAggregateV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "aggregates", "results", window.Provider)
	defer func() { finish(retErr) }()

	rows, err := s.pool.Query(ctx, `
		SELECT id::text, provider, result_kind, provider_subject_id, subject_name, value_text, resolved_mood,
		       TO_CHAR(recorded_on, 'YYYY-MM-DD'), term_no, year_label
		FROM academic_aggregates
		WHERE student_id = $1
		  AND provider = $2
		  AND recorded_on BETWEEN $3::date AND $4::date
		ORDER BY recorded_on DESC, updated_at DESC
		LIMIT $5
	`, studentID, window.Provider, window.WindowFrom.Format("2006-01-02"), window.WindowTo.Format("2006-01-02"), limit)
	if err != nil {
		retErr = err
		return nil, retErr
	}
	defer rows.Close()
	out = make([]contracts.AcademicAggregateV2DTO, 0, limit)
	for rows.Next() {
		var item contracts.AcademicAggregateV2DTO
		if err := rows.Scan(
			&item.AggregateID,
			&item.Provider,
			&item.ResultKind,
			&item.ProviderSubjectID,
			&item.SubjectName,
			&item.ValueText,
			&item.ResolvedMood,
			&item.RecordedOn,
			&item.TermNo,
			&item.YearLabel,
		); err != nil {
			retErr = err
			return nil, retErr
		}
		out = append(out, item)
	}
	retErr = rows.Err()
	return out, retErr
}

func (s *Service) attendance(ctx context.Context, studentID uuid.UUID, window ReadWindowV2, limit int) (out []contracts.AcademicAttendanceV2DTO, retErr error) {
	ctx, finish := s.observeDB(ctx, "attendance", "results", window.Provider)
	defer func() { finish(retErr) }()

	rows, err := s.pool.Query(ctx, `
		SELECT a.id::text,
		       a.provider,
		       a.provider_event_key,
		       COALESCE(l.provider_lesson_id, l.source_lesson_key, COALESCE(a.source_event_key, '')),
		       COALESCE(a.provider_subject_id, ''),
		       COALESCE(a.subject_name, ''),
		       COALESCE(a.lesson_number, 0),
		       TO_CHAR(a.recorded_on, 'YYYY-MM-DD'),
		       a.raw_code,
		       a.normalized_status,
		       COALESCE(a.reason, '')
		FROM attendance_events a
		LEFT JOIN lessons l ON l.id = a.lesson_id
		WHERE a.student_id = $1
		  AND a.provider = $2
		  AND a.recorded_on BETWEEN $3::date AND $4::date
		ORDER BY a.recorded_on DESC
		LIMIT $5
	`, studentID, window.Provider, window.WindowFrom.Format("2006-01-02"), window.WindowTo.Format("2006-01-02"), limit)
	if err != nil {
		retErr = err
		return nil, retErr
	}
	defer rows.Close()
	out = make([]contracts.AcademicAttendanceV2DTO, 0, limit)
	for rows.Next() {
		var item contracts.AcademicAttendanceV2DTO
		if err := rows.Scan(
			&item.AttendanceID,
			&item.Provider,
			&item.ProviderEventKey,
			&item.ProviderLessonRef,
			&item.ProviderSubjectID,
			&item.SubjectName,
			&item.LessonNumber,
			&item.RecordedOn,
			&item.RawCode,
			&item.NormalizedStatus,
			&item.Reason,
		); err != nil {
			retErr = err
			return nil, retErr
		}
		out = append(out, item)
	}
	retErr = rows.Err()
	return out, retErr
}

func (s *Service) observeRead(ctx context.Context, endpoint string, provider string) (context.Context, map[string]string, time.Time, func(time.Time, map[string]string, error)) {
	tags := map[string]string{
		"path":     "typed_v2_read",
		"endpoint": endpoint,
		"provider": provider,
		"stage":    "active",
	}
	s.metrics.Incr("backend.read.requests_total", tags)
	ctx, finishSpan := s.tracer.Start(ctx, "read.v2."+endpoint)
	return ctx, tags, time.Now(), func(startedAt time.Time, tags map[string]string, err error) {
		recordReadOutcome(s, startedAt, err, tags)
		finishSpan(err)
	}
}

func (s *Service) observeDB(ctx context.Context, queryName string, endpoint string, provider string) (context.Context, func(error)) {
	spanName := "read.v2.db." + queryName
	ctx, finishSpan := s.tracer.Start(ctx, spanName)
	startedAt := time.Now()
	tags := map[string]string{
		"path":     "typed_v2_read",
		"endpoint": endpoint,
		"query":    queryName,
		"provider": provider,
		"stage":    "active",
	}
	return ctx, func(err error) {
		outcome := "success"
		errorClass := "none"
		if err != nil {
			outcome = "failure"
			errorClass = classifyReadError(err)
		}
		s.metrics.Incr("backend.read.db_query_total", mergeMetricTags(tags, map[string]string{
			"outcome":     outcome,
			"error_class": errorClass,
		}))
		s.metrics.Observe("backend.read.db_query_latency_ms", float64(time.Since(startedAt).Milliseconds()), mergeMetricTags(tags, map[string]string{
			"outcome":     outcome,
			"error_class": errorClass,
		}))
		finishSpan(err)
	}
}

func recordReadOutcome(s *Service, startedAt time.Time, err error, tags map[string]string) {
	if err != nil {
		errorClass := classifyReadError(err)
		s.metrics.Incr("backend.read.failure_total", mergeMetricTags(tags, map[string]string{
			"error_class": errorClass,
		}))
		s.metrics.Observe("backend.read.latency_ms", float64(time.Since(startedAt).Milliseconds()), mergeMetricTags(tags, map[string]string{
			"outcome":     "failure",
			"error_class": errorClass,
		}))
		return
	}
	s.metrics.Incr("backend.read.success_total", tags)
	s.metrics.Observe("backend.read.latency_ms", float64(time.Since(startedAt).Milliseconds()), mergeMetricTags(tags, map[string]string{
		"outcome": "success",
	}))
}

func mergeMetricTags(base map[string]string, extra map[string]string) map[string]string {
	out := make(map[string]string, len(base)+len(extra))
	for key, value := range base {
		out[key] = value
	}
	for key, value := range extra {
		out[key] = value
	}
	return out
}

func classifyReadError(err error) string {
	if errors.Is(err, pgx.ErrNoRows) {
		return "not_found"
	}
	return "internal"
}
