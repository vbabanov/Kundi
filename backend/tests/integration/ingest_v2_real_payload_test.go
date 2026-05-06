package integration

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kundi/kundi/backend/internal/contracts"
	ingest "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
)

func TestV2RealFixturesEndToEndWriteReadConsistency(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	identity := testIdentity()

	diaryRaw := loadJSONFixture(t, fixturePath("fixtures", "kundelik", "diary_real.txt"))
	periodRaw := loadJSONFixture(t, fixturePath("fixtures", "kundelik", "period_real.txt"))
	yearRaw := loadJSONFixture(t, fixturePath("fixtures", "kundelik", "year_real.txt"))

	diaryBundle := buildBundleFromDiaryFixture(identity, "real-diary-001", diaryRaw)
	periodBundle := buildBundleFromPeriodFixture(identity, "real-period-001", periodRaw)
	yearBundle := buildBundleFromYearFixture(identity, "real-year-001", yearRaw)

	ingestV2(t, svc, studentID, diaryBundle)
	ingestV2(t, svc, studentID, periodBundle)
	ingestV2(t, svc, studentID, yearBundle)

	if len(repo.results) == 0 {
		t.Fatalf("expected event-level canonical results from period fixture")
	}
	if len(repo.aggregates) == 0 {
		t.Fatalf("expected aggregate-level rows from year fixture")
	}
	if len(repo.evidences) == 0 {
		t.Fatalf("expected evidences to be persisted")
	}

	readDTO := repo.toAcademicOverviewDTO(identity)
	if len(readDTO.Results) != len(repo.results) {
		t.Fatalf("read/write mismatch for results: dto=%d repo=%d", len(readDTO.Results), len(repo.results))
	}
	if len(readDTO.Aggregates) != len(repo.aggregates) {
		t.Fatalf("read/write mismatch for aggregates: dto=%d repo=%d", len(readDTO.Aggregates), len(repo.aggregates))
	}
	if len(readDTO.Lessons) == 0 {
		t.Fatalf("expected lessons in typed read DTO")
	}
	if strings.TrimSpace(readDTO.Identity.ProviderPersonID) == "" {
		t.Fatalf("expected provider identity in read DTO")
	}
}

func TestV2RealPayloadKindsStayBaselineOnly(t *testing.T) {
	identity := testIdentity()
	periodRaw := loadJSONFixture(t, fixturePath("fixtures", "kundelik", "period_real.txt"))
	yearRaw := loadJSONFixture(t, fixturePath("fixtures", "kundelik", "year_real.txt"))

	periodBundle := buildBundleFromPeriodFixture(identity, "real-period-002", periodRaw)
	yearBundle := buildBundleFromYearFixture(identity, "real-year-002", yearRaw)

	for _, result := range periodBundle.Results {
		if !ingest.IsAllowedEventResultKindV2(result.ResultKind) {
			t.Fatalf("unexpected event kind from real fixture: %s", result.ResultKind)
		}
	}
	for _, aggregate := range yearBundle.Aggregates {
		if !ingest.IsAllowedAggregateResultKindV2(aggregate.ResultKind) {
			t.Fatalf("unexpected aggregate kind from real fixture: %s", aggregate.ResultKind)
		}
	}
}

func TestV2SQLConstraintsWithRealPostgresIfConfigured(t *testing.T) {
	dsn := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set; skipping real-postgres constraint test")
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("open test database pool: %v", err)
	}
	defer pool.Close()

	schema := "kundi_v2_test_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	conn, err := pool.Acquire(ctx)
	if err != nil {
		t.Fatalf("acquire test connection: %v", err)
	}
	defer conn.Release()

	if _, err := conn.Exec(ctx, fmt.Sprintf(`CREATE SCHEMA "%s"`, schema)); err != nil {
		t.Fatalf("create schema: %v", err)
	}
	defer conn.Exec(ctx, fmt.Sprintf(`DROP SCHEMA "%s" CASCADE`, schema))

	if _, err := conn.Exec(ctx, fmt.Sprintf(`SET search_path TO "%s", public`, schema)); err != nil {
		t.Fatalf("set search_path: %v", err)
	}

	migrations := mustListMigrationFiles(t, migrationDirPath())
	for _, file := range migrations {
		sqlRaw, readErr := os.ReadFile(file)
		if readErr != nil {
			t.Fatalf("read migration %s: %v", file, readErr)
		}
		if _, execErr := conn.Exec(ctx, string(sqlRaw)); execErr != nil {
			// Some environments may disallow extensions in migration 0001.
			if strings.Contains(execErr.Error(), "permission denied") || strings.Contains(execErr.Error(), "must be owner") {
				t.Skipf("insufficient privileges for full migration execution: %v", execErr)
			}
			t.Fatalf("exec migration %s: %v", file, execErr)
		}
	}

	studentID := uuid.New()
	_, err = conn.Exec(ctx, `INSERT INTO students(id, external_student_ref) VALUES ($1, 'ext-1')`, studentID)
	if err != nil {
		t.Fatalf("insert student: %v", err)
	}
	_, err = conn.Exec(ctx, `
		INSERT INTO student_profiles(student_id, first_name, last_name, grade_level, class_label)
		VALUES ($1, 'A', 'B', 7, '7Ж')
	`, studentID)
	if err != nil {
		t.Fatalf("insert student profile: %v", err)
	}

	_, err = conn.Exec(ctx, `
		INSERT INTO lessons(student_id, provider, source_lesson_key, lesson_date, lesson_number, subject_name)
		VALUES ($1, 'kundelik', 'lesson-uq-1', '2026-03-30', 1, 'Math')
	`, studentID)
	if err != nil {
		t.Fatalf("insert lesson #1: %v", err)
	}
	_, err = conn.Exec(ctx, `
		INSERT INTO lessons(student_id, provider, source_lesson_key, lesson_date, lesson_number, subject_name)
		VALUES ($1, 'kundelik', 'lesson-uq-1', '2026-03-30', 1, 'Math')
	`, studentID)
	if !isPgCode(err, "23505") {
		t.Fatalf("expected unique violation 23505 for lessons uq, got err=%v", err)
	}

	_, err = conn.Exec(ctx, `
		INSERT INTO academic_results(
			student_id, provider, result_kind, provider_subject_id, subject_name, provider_mark_id,
			value_text, recorded_on
		)
		VALUES ($1, 'kundelik', 'regular', 'subj-1', 'Math', 'mark-uq-1', '8', '2026-03-30')
	`, studentID)
	if err != nil {
		t.Fatalf("insert result #1: %v", err)
	}
	_, err = conn.Exec(ctx, `
		INSERT INTO academic_results(
			student_id, provider, result_kind, provider_subject_id, subject_name, provider_mark_id,
			value_text, recorded_on
		)
		VALUES ($1, 'kundelik', 'regular', 'subj-1', 'Math', 'mark-uq-1', '8', '2026-03-30')
	`, studentID)
	if !isPgCode(err, "23505") {
		t.Fatalf("expected unique violation 23505 for result mark identity, got err=%v", err)
	}

	_, err = conn.Exec(ctx, `
		INSERT INTO academic_aggregates(
			student_id, provider, result_kind, provider_subject_id, subject_name,
			period_id, term_no, year_label, value_text, recorded_on
		)
		VALUES ($1, 'kundelik', 'term', 'subj-1', 'Math', 'period-1', NULL, '', '3', '2026-03-30')
	`, studentID)
	if !isPgCode(err, "23514") {
		t.Fatalf("expected check violation 23514 for invalid term aggregate dimensions, got err=%v", err)
	}
}

func mustListMigrationFiles(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("list migrations: %v", err)
	}
	files := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sql") {
			continue
		}
		files = append(files, filepath.Join(dir, entry.Name()))
	}
	sort.Strings(files)
	return files
}

func isPgCode(err error, code string) bool {
	if err == nil {
		return false
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == code
	}
	return false
}

func loadJSONFixture(t *testing.T, path string) map[string]any {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read fixture %s: %v", path, err)
	}
	content := string(raw)
	idx := strings.Index(content, "{")
	if idx < 0 {
		t.Fatalf("fixture %s has no json object", path)
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(content[idx:]), &payload); err != nil {
		t.Fatalf("decode fixture %s: %v", path, err)
	}
	return payload
}

func fixturePath(parts ...string) string {
	_, file, _, _ := runtime.Caller(0)
	base := filepath.Dir(file)
	all := append([]string{filepath.Dir(base)}, parts...)
	return filepath.Join(all...)
}

func migrationDirPath() string {
	_, file, _, _ := runtime.Caller(0)
	base := filepath.Dir(file)
	return filepath.Clean(filepath.Join(base, "..", "..", "migrations"))
}

func buildBundleFromDiaryFixture(identity ingest.CanonicalProviderIdentityV2, idempotency string, payload map[string]any) ingest.CanonicalIngestBundleV2 {
	days, _ := payload["days"].([]any)
	lessons := make([]ingest.CanonicalLessonV2, 0, 64)
	attendance := make([]ingest.CanonicalAttendanceEventV2, 0, 64)
	evidence := make([]ingest.CanonicalResultEvidenceV2, 0, 64)

	for _, dayRaw := range days {
		day, ok := dayRaw.(map[string]any)
		if !ok {
			continue
		}
		dayDate := unixStringToYMD(day["date"])
		dayLessons, _ := day["lessons"].([]any)
		for _, lessonRaw := range dayLessons {
			lessonMap, ok := lessonRaw.(map[string]any)
			if !ok {
				continue
			}
			subj := toMap(lessonMap["subject"])
			homework := toMap(lessonMap["homework"])
			hours := toMap(lessonMap["hours"])

			sourceLessonKey := toString(lessonMap["id"])
			lesson := ingest.CanonicalLessonV2{
				SourceLessonKey:   sourceLessonKey,
				ProviderLessonID:  sourceLessonKey,
				ProviderSubjectID: toString(subj["id"]),
				Date:              dayDate,
				LessonNumber:      toInt(lessonMap["number"]),
				SubjectName:       toString(subj["name"]),
				StartTime:         hhmm(hours["startHour"], hours["startMinute"]),
				EndTime:           hhmm(hours["endHour"], hours["endMinute"]),
				Theme:             toString(lessonMap["theme"]),
				HomeworkText:      toString(homework["text"]),
				RequiresPhoto:     toBool(homework["workIsAttachRequired"]),
			}
			if lesson.SourceLessonKey == "" || lesson.Date == "" || lesson.LessonNumber <= 0 {
				continue
			}
			lessons = append(lessons, lesson)

			logEntry := toMap(lessonMap["logEntry"])
			if len(logEntry) > 0 {
				rawCode := toString(logEntry["lessonLogEntryValue"])
				attendance = append(attendance, ingest.CanonicalAttendanceEventV2{
					SourceEventKey:    toString(logEntry["lessonId"]),
					ProviderEventKey:  toString(logEntry["lessonId"]),
					ProviderLessonRef: sourceLessonKey,
					RecordedOn:        dayDate,
					RawCode:           rawCode,
					NormalizedStatus:  normalizeStatusRaw(rawCode),
					Reason:            toString(logEntry["fullName"]),
				})
				evidence = append(evidence, ingest.CanonicalResultEvidenceV2{
					SourceEndpoint:      "diary",
					ProviderPayloadPath: "days[].lessons[].logEntry",
					FingerprintSHA256:   digestString("att", sourceLessonKey, dayDate, rawCode),
				})
			}
		}
	}

	return ingest.CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "fixture-real",
		IdempotencyKey:  idempotency,
		SyncedAt:        time.Now().UTC(),
		Identity:        identity,
		Lessons:         lessons,
		Results:         nil,
		Aggregates:      nil,
		Attendance:      attendance,
		Evidence:        evidence,
	}
}

func buildBundleFromPeriodFixture(identity ingest.CanonicalProviderIdentityV2, idempotency string, payload map[string]any) ingest.CanonicalIngestBundleV2 {
	subjects, _ := payload["subjects"].([]any)
	results := make([]ingest.CanonicalAcademicResultV2, 0, 128)
	evidence := make([]ingest.CanonicalResultEvidenceV2, 0, 128)

	for _, subjectRaw := range subjects {
		subject := toMap(subjectRaw)
		subjectID := toString(subject["id"])
		subjectName := toString(subject["name"])
		works, _ := subject["works"].([]any)
		for _, workRaw := range works {
			work := toMap(workRaw)
			workID := toString(work["workId"])
			recordedOn := unixStringToYMD(work["date"])
			marks, _ := work["marks"].([]any)
			for _, markRaw := range marks {
				mark := toMap(markRaw)
				markID := toString(mark["id"])
				value := toString(mark["value"])
				if value == "" {
					continue
				}
				sourceKey := fmt.Sprintf("period:%s:%s:%s", subjectID, workID, markID)
				results = append(results, ingest.CanonicalAcademicResultV2{
					SourceResultKey:   sourceKey,
					ResultKind:        "regular",
					ProviderWorkID:    workID,
					ProviderMarkID:    markID,
					ProviderSubjectID: subjectID,
					SubjectName:       subjectName,
					RecordedOn:        recordedOn,
					PeriodID:          toString(payload["periodId"]),
					ValueText:         value,
					ResolvedMood:      toString(mark["mood"]),
				})
				evidence = append(evidence, ingest.CanonicalResultEvidenceV2{
					SourceResultRefKey:  sourceKey,
					SourceEndpoint:      "period",
					ProviderWorkID:      workID,
					ProviderMarkID:      markID,
					ProviderPayloadPath: "subjects[].works[].marks[]",
					SourceMoodRaw:       toString(mark["mood"]),
					FingerprintSHA256:   digestString("period", subjectID, workID, markID, value, recordedOn),
				})
			}
		}
	}

	return ingest.CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "fixture-real",
		IdempotencyKey:  idempotency,
		SyncedAt:        time.Now().UTC(),
		Identity:        identity,
		Results:         results,
		Evidence:        evidence,
	}
}

func buildBundleFromYearFixture(identity ingest.CanonicalProviderIdentityV2, idempotency string, payload map[string]any) ingest.CanonicalIngestBundleV2 {
	subjects, _ := payload["subjects"].([]any)
	aggregates := make([]ingest.CanonicalAcademicAggregate, 0, 128)
	evidence := make([]ingest.CanonicalResultEvidenceV2, 0, 128)

	for _, subjectRaw := range subjects {
		subject := toMap(subjectRaw)
		subjectID := toString(subject["id"])
		subjectName := toString(subject["name"])
		finalWorks, _ := subject["finalWorks"].([]any)
		for _, workRaw := range finalWorks {
			work := toMap(workRaw)
			workID := toString(work["workId"])
			periodID := toString(work["periodId"])
			marks, _ := work["marks"].([]any)
			for idx, markRaw := range marks {
				mark := toMap(markRaw)
				markID := toString(mark["id"])
				value := toString(mark["value"])
				if value == "" {
					continue
				}
				sourceKey := fmt.Sprintf("year:%s:%s:%s:%d", subjectID, workID, markID, idx)
				aggregates = append(aggregates, ingest.CanonicalAcademicAggregate{
					SourceAggregateKey: sourceKey,
					ResultKind:         "year",
					ProviderSubjectID:  subjectID,
					SubjectName:        subjectName,
					RecordedOn:         "2026-03-30",
					PeriodID:           periodID,
					YearLabel:          "2025/2026",
					ValueText:          value,
					ResolvedMood:       toString(mark["mood"]),
				})
				evidence = append(evidence, ingest.CanonicalResultEvidenceV2{
					SourceAggregateRefKey: sourceKey,
					SourceEndpoint:        "final",
					ProviderWorkID:        workID,
					ProviderMarkID:        markID,
					ProviderPayloadPath:   "subjects[].finalWorks[].marks[]",
					SourceMoodRaw:         toString(mark["mood"]),
					FingerprintSHA256:     digestString("year", subjectID, workID, markID, value, periodID),
				})
			}
		}
	}

	return ingest.CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "fixture-real",
		IdempotencyKey:  idempotency,
		SyncedAt:        time.Now().UTC(),
		Identity:        identity,
		Aggregates:      aggregates,
		Evidence:        evidence,
	}
}

func (r *inMemoryV2Repo) toAcademicOverviewDTO(identity ingest.CanonicalProviderIdentityV2) contracts.AcademicOverviewV2DTO {
	lessons := make([]contracts.AcademicLessonV2DTO, 0)
	for _, row := range r.results {
		lessons = append(lessons, contracts.AcademicLessonV2DTO{
			LessonID:       row.LessonRefKey,
			Provider:       row.Provider,
			LessonDate:     row.RecordedOn,
			LessonNumber:   0,
			SubjectName:    row.SubjectNameOrFallback(),
			HomeworkText:   "",
			HomeworkStatus: "unknown",
		})
	}
	results := make([]contracts.AcademicResultV2DTO, 0, len(r.results))
	for _, row := range r.results {
		results = append(results, contracts.AcademicResultV2DTO{
			ResultID:          row.ID,
			Provider:          row.Provider,
			ResultKind:        row.Kind,
			ProviderWorkID:    row.ProviderWorkID,
			ProviderMarkID:    row.ProviderMarkID,
			ProviderSubjectID: row.ProviderSubjectID,
			SubjectName:       row.SubjectNameOrFallback(),
			ValueText:         row.ValueText,
			ResolvedMood:      row.ResolvedMood,
			RecordedOn:        row.RecordedOn,
		})
	}
	aggregates := make([]contracts.AcademicAggregateV2DTO, 0, len(r.aggregates))
	for _, row := range r.aggregates {
		term := row.TermNo
		var termPtr *int
		if term > 0 {
			termPtr = &term
		}
		aggregates = append(aggregates, contracts.AcademicAggregateV2DTO{
			AggregateID:       row.ID,
			Provider:          row.Provider,
			ResultKind:        row.Kind,
			ProviderSubjectID: row.ProviderSubjectID,
			SubjectName:       row.SubjectNameOrFallback(),
			ValueText:         row.ValueText,
			ResolvedMood:      row.ResolvedMood,
			RecordedOn:        row.RecordedOn,
			TermNo:            termPtr,
			YearLabel:         row.YearLabel,
		})
	}
	sort.Slice(results, func(i, j int) bool { return results[i].ResultID < results[j].ResultID })
	sort.Slice(aggregates, func(i, j int) bool { return aggregates[i].AggregateID < aggregates[j].AggregateID })

	return contracts.AcademicOverviewV2DTO{
		Identity: contracts.AcademicIdentityV2DTO{
			Provider:             identity.Provider,
			ProviderPersonID:     identity.ProviderPersonID,
			ProviderSchoolID:     identity.ProviderSchoolID,
			ProviderGroupID:      identity.ProviderGroupID,
			StudentFullName:      identity.StudentFullName,
			SchoolName:           identity.SchoolName,
			ClassLabel:           identity.ClassLabel,
			ClassTeacherFullName: identity.ClassTeacherFullName,
		},
		Lessons:    lessons,
		Results:    results,
		Aggregates: aggregates,
	}
}

func (r *v2ResultRow) SubjectNameOrFallback() string {
	if strings.TrimSpace(r.SubjectName) == "" {
		return "unknown"
	}
	return r.SubjectName
}

func (r *v2AggregateRow) SubjectNameOrFallback() string {
	if strings.TrimSpace(r.SubjectName) == "" {
		return "unknown"
	}
	return r.SubjectName
}

func toMap(v any) map[string]any {
	if v == nil {
		return map[string]any{}
	}
	if m, ok := v.(map[string]any); ok {
		return m
	}
	return map[string]any{}
}

func toString(v any) string {
	if v == nil {
		return ""
	}
	switch value := v.(type) {
	case string:
		return strings.TrimSpace(value)
	case float64:
		return strconv.FormatInt(int64(value), 10)
	default:
		return strings.TrimSpace(fmt.Sprintf("%v", value))
	}
}

func toInt(v any) int {
	if v == nil {
		return 0
	}
	switch value := v.(type) {
	case float64:
		return int(value)
	case int:
		return value
	default:
		n, _ := strconv.Atoi(toString(v))
		return n
	}
}

func toBool(v any) bool {
	switch value := v.(type) {
	case bool:
		return value
	case string:
		l := strings.ToLower(strings.TrimSpace(value))
		return l == "true" || l == "1"
	default:
		return false
	}
}

func hhmm(h any, m any) string {
	hour := toString(h)
	minute := toString(m)
	if hour == "" || minute == "" {
		return ""
	}
	if len(hour) == 1 {
		hour = "0" + hour
	}
	if len(minute) == 1 {
		minute = "0" + minute
	}
	return hour + ":" + minute
}

func unixStringToYMD(v any) string {
	raw := toString(v)
	if raw == "" {
		return ""
	}
	sec, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return ""
	}
	dt := time.Unix(sec, 0).UTC()
	return dt.Format("2006-01-02")
}

func normalizeStatusRaw(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "н":
		return "absent"
	case "б":
		return "excused"
	case "о":
		return "late"
	case "п", "+":
		return "present"
	default:
		return "unknown"
	}
}

func digestString(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, "|")))
	return hex.EncodeToString(sum[:])
}
