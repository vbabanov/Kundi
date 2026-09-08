package diary_ingest

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/kundi/kundi/backend/internal/platform/apperrors"
	"github.com/kundi/kundi/backend/internal/platform/validate"
)

type RepositoryV2 interface {
	CreateBatchV2(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundleV2, checksum string) (batchID uuid.UUID, inserted bool, err error)
	MergeBundleV2(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundleV2) (MergeStatsV2, error)
	MarkMerged(ctx context.Context, batchID uuid.UUID) error
}

func (s *Service) IngestBundleV2(ctx context.Context, studentID uuid.UUID, bundle CanonicalIngestBundleV2) (IngestResultV2, error) {
	startedAt := time.Now()
	baseTags := map[string]string{
		"path":  "ingest_v2",
		"stage": "active",
	}
	s.metrics.Incr("backend.ingest.requests_total", baseTags)
	ctx, finish := s.tracer.Start(ctx, "ingest.bundle.v2")
	var outcomeErr error
	defer func() {
		outcome := "success"
		errorClass := "none"
		if outcomeErr != nil {
			outcome = "failure"
			errorClass = classifyErrorClass(outcomeErr)
			s.metrics.Incr("backend.ingest.failure_total", mergeTags(baseTags, map[string]string{
				"error_class": errorClass,
			}))
		} else {
			s.metrics.Incr("backend.ingest.success_total", baseTags)
		}
		s.metrics.Observe("backend.ingest.latency_ms", float64(time.Since(startedAt).Milliseconds()), mergeTags(baseTags, map[string]string{
			"outcome":     outcome,
			"error_class": errorClass,
		}))
		finish(outcomeErr)
	}()

	repo, ok := s.repo.(RepositoryV2)
	if !ok {
		outcomeErr = apperrors.Internal("ingest_v2_repository_missing", "ingest v2 repository is not configured", nil)
		return IngestResultV2{}, outcomeErr
	}

	normalized := normalizeBundleV2(bundle)
	if err := validateBundleV2(normalized); err != nil {
		outcomeErr = err
		return IngestResultV2{}, outcomeErr
	}
	checksum, err := checksumBundleV2(normalized)
	if err != nil {
		outcomeErr = apperrors.Internal("bundle_v2_checksum_failed", "failed to compute bundle checksum", err)
		return IngestResultV2{}, outcomeErr
	}

	batchID, inserted, err := repo.CreateBatchV2(ctx, studentID, normalized, checksum)
	if err != nil {
		if errors.Is(err, ErrIdempotencyConflict) {
			outcomeErr = apperrors.Conflict("ingest_v2_idempotency_conflict", "idempotency key already used for another payload")
			return IngestResultV2{}, outcomeErr
		}
		outcomeErr = apperrors.Internal("ingest_v2_batch_failed", "failed to create ingest batch", err)
		return IngestResultV2{}, outcomeErr
	}
	if !inserted {
		return IngestResultV2{BatchID: batchID.String(), AlreadyProcessed: true}, nil
	}

	stats, err := repo.MergeBundleV2(ctx, studentID, normalized)
	if err != nil {
		outcomeErr = apperrors.Internal("ingest_v2_merge_failed", "failed to merge ingest bundle v2", err)
		return IngestResultV2{}, outcomeErr
	}
	if err := repo.MarkMerged(ctx, batchID); err != nil {
		outcomeErr = apperrors.Internal("ingest_v2_finalize_failed", "failed to finalize ingest batch", err)
		return IngestResultV2{}, outcomeErr
	}
	s.metrics.Observe("backend.ingest.merge_lessons", float64(stats.MergedLessons), baseTags)
	s.metrics.Observe("backend.ingest.merge_results", float64(stats.MergedResults), baseTags)
	s.metrics.Observe("backend.ingest.merge_aggregates", float64(stats.MergedAggregates), baseTags)
	s.metrics.Observe("backend.ingest.merge_attendance", float64(stats.MergedAttendance), baseTags)
	s.metrics.Observe("backend.ingest.inserted_evidence", float64(stats.InsertedEvidence), baseTags)
	return IngestResultV2{
		BatchID:          batchID.String(),
		AlreadyProcessed: false,
		MergedLessons:    stats.MergedLessons,
		MergedResults:    stats.MergedResults,
		MergedAggregates: stats.MergedAggregates,
		MergedAttendance: stats.MergedAttendance,
		InsertedEvidence: stats.InsertedEvidence,
	}, nil
}

func normalizeBundleV2(bundle CanonicalIngestBundleV2) CanonicalIngestBundleV2 {
	bundle.Source = strings.ToLower(strings.TrimSpace(bundle.Source))
	bundle.SourceAccount = strings.TrimSpace(bundle.SourceAccount)
	bundle.IdempotencyKey = strings.TrimSpace(bundle.IdempotencyKey)
	if bundle.ContractVersion == 0 {
		bundle.ContractVersion = 2
	}
	if !bundle.SyncedAt.IsZero() {
		bundle.SyncedAt = bundle.SyncedAt.UTC()
	}

	bundle.Identity.Provider = strings.ToLower(strings.TrimSpace(bundle.Identity.Provider))
	bundle.Identity.ProviderAccountRef = strings.TrimSpace(bundle.Identity.ProviderAccountRef)
	bundle.Identity.ProviderPersonID = strings.TrimSpace(bundle.Identity.ProviderPersonID)
	bundle.Identity.ProviderSchoolID = strings.TrimSpace(bundle.Identity.ProviderSchoolID)
	bundle.Identity.ProviderGroupID = strings.TrimSpace(bundle.Identity.ProviderGroupID)
	bundle.Identity.StudentFullName = strings.TrimSpace(bundle.Identity.StudentFullName)
	bundle.Identity.SchoolName = strings.TrimSpace(bundle.Identity.SchoolName)
	bundle.Identity.ClassLabel = strings.TrimSpace(bundle.Identity.ClassLabel)
	bundle.Identity.ClassTeacherFullName = strings.TrimSpace(bundle.Identity.ClassTeacherFullName)

	for i := range bundle.Lessons {
		lesson := &bundle.Lessons[i]
		lesson.SourceLessonKey = strings.TrimSpace(lesson.SourceLessonKey)
		lesson.ProviderLessonID = strings.TrimSpace(lesson.ProviderLessonID)
		lesson.ProviderSubjectID = strings.TrimSpace(lesson.ProviderSubjectID)
		lesson.Date = strings.TrimSpace(lesson.Date)
		lesson.SubjectName = strings.TrimSpace(lesson.SubjectName)
		lesson.LessonPlace = strings.TrimSpace(lesson.LessonPlace)
		lesson.StartTime = strings.TrimSpace(lesson.StartTime)
		lesson.EndTime = strings.TrimSpace(lesson.EndTime)
		lesson.Theme = strings.TrimSpace(lesson.Theme)
		lesson.HomeworkText = strings.TrimSpace(lesson.HomeworkText)
	}

	for i := range bundle.Results {
		res := &bundle.Results[i]
		res.SourceResultKey = strings.TrimSpace(res.SourceResultKey)
		res.ResultKind = strings.ToLower(strings.TrimSpace(res.ResultKind))
		res.ProviderWorkID = strings.TrimSpace(res.ProviderWorkID)
		res.ProviderMarkID = strings.TrimSpace(res.ProviderMarkID)
		res.ProviderSubjectID = strings.TrimSpace(res.ProviderSubjectID)
		res.SubjectName = strings.TrimSpace(res.SubjectName)
		res.LessonRefKey = strings.TrimSpace(res.LessonRefKey)
		res.RecordedOn = strings.TrimSpace(res.RecordedOn)
		res.PeriodID = strings.TrimSpace(res.PeriodID)
		res.ValueText = strings.TrimSpace(res.ValueText)
		res.ResolvedMood = strings.TrimSpace(res.ResolvedMood)
	}

	for i := range bundle.Aggregates {
		agg := &bundle.Aggregates[i]
		agg.SourceAggregateKey = strings.TrimSpace(agg.SourceAggregateKey)
		agg.ResultKind = strings.ToLower(strings.TrimSpace(agg.ResultKind))
		agg.ProviderSubjectID = strings.TrimSpace(agg.ProviderSubjectID)
		agg.SubjectName = strings.TrimSpace(agg.SubjectName)
		agg.RecordedOn = strings.TrimSpace(agg.RecordedOn)
		agg.PeriodID = strings.TrimSpace(agg.PeriodID)
		agg.YearLabel = strings.TrimSpace(agg.YearLabel)
		agg.ValueText = strings.TrimSpace(agg.ValueText)
		agg.ResolvedMood = strings.TrimSpace(agg.ResolvedMood)
	}

	for i := range bundle.Attendance {
		att := &bundle.Attendance[i]
		att.SourceEventKey = strings.TrimSpace(att.SourceEventKey)
		att.ProviderEventKey = strings.TrimSpace(att.ProviderEventKey)
		att.ProviderLessonRef = strings.TrimSpace(att.ProviderLessonRef)
		att.RecordedOn = strings.TrimSpace(att.RecordedOn)
		att.RawCode = strings.TrimSpace(att.RawCode)
		att.NormalizedStatus = strings.ToLower(strings.TrimSpace(att.NormalizedStatus))
		att.Reason = strings.TrimSpace(att.Reason)
	}

	for i := range bundle.Evidence {
		ev := &bundle.Evidence[i]
		ev.SourceResultRefKey = strings.TrimSpace(ev.SourceResultRefKey)
		ev.SourceAggregateRefKey = strings.TrimSpace(ev.SourceAggregateRefKey)
		ev.SourceEndpoint = strings.ToLower(strings.TrimSpace(ev.SourceEndpoint))
		ev.ProviderWorkID = strings.TrimSpace(ev.ProviderWorkID)
		ev.ProviderMarkID = strings.TrimSpace(ev.ProviderMarkID)
		ev.ProviderPayloadPath = strings.TrimSpace(ev.ProviderPayloadPath)
		ev.SourceMoodRaw = strings.TrimSpace(ev.SourceMoodRaw)
		ev.FingerprintSHA256 = strings.TrimSpace(ev.FingerprintSHA256)
	}

	if bundle.LocalAppProfile != nil {
		bundle.LocalAppProfile.ParentPhone1 = strings.TrimSpace(bundle.LocalAppProfile.ParentPhone1)
		bundle.LocalAppProfile.ParentPhone2 = strings.TrimSpace(bundle.LocalAppProfile.ParentPhone2)
	}

	return bundle
}

func validateBundleV2(bundle CanonicalIngestBundleV2) error {
	if !validate.Source(bundle.Source) {
		return apperrors.BadRequest("invalid_source", "bundle source is not supported")
	}
	if !validate.IdempotencyKey(bundle.IdempotencyKey) {
		return apperrors.BadRequest("invalid_idempotency_key", "idempotency key has invalid format")
	}
	if bundle.ContractVersion != 2 {
		return apperrors.BadRequest("invalid_contract_version", "contract_version must be 2")
	}
	if !validate.Source(bundle.Identity.Provider) {
		return apperrors.BadRequest("invalid_provider", "identity provider is not supported")
	}
	if bundle.Identity.Provider != bundle.Source {
		return apperrors.BadRequest("provider_source_mismatch", "identity provider must match source")
	}
	if !hasAcademicDataV2(bundle) {
		if err := validateAuthoritativeAcademicEmptyV2(bundle); err != nil {
			return err
		}
	}

	for _, lesson := range bundle.Lessons {
		if lesson.SourceLessonKey == "" {
			return apperrors.BadRequest("invalid_lesson_key", "source lesson key must not be empty")
		}
		if _, err := time.Parse("2006-01-02", lesson.Date); err != nil {
			return apperrors.BadRequest("invalid_lesson_date", "lesson date must match YYYY-MM-DD")
		}
		if lesson.LessonNumber < 0 {
			return apperrors.BadRequest("invalid_lesson_number", "lesson number must be non-negative")
		}
	}

	for _, res := range bundle.Results {
		if !IsAllowedEventResultKindV2(res.ResultKind) {
			return apperrors.BadRequest("invalid_result_kind", "result_kind must be regular|sor|soch")
		}
		if _, err := time.Parse("2006-01-02", res.RecordedOn); err != nil {
			return apperrors.BadRequest("invalid_result_date", "result recorded_on must match YYYY-MM-DD")
		}
		if strings.TrimSpace(res.ValueText) == "" {
			return apperrors.BadRequest("invalid_result_value", "result value_text is required")
		}
	}

	for _, agg := range bundle.Aggregates {
		if !IsAllowedAggregateResultKindV2(agg.ResultKind) {
			return apperrors.BadRequest("invalid_aggregate_kind", "aggregate result_kind must be term|year")
		}
		if _, err := time.Parse("2006-01-02", agg.RecordedOn); err != nil {
			return apperrors.BadRequest("invalid_aggregate_date", "aggregate recorded_on must match YYYY-MM-DD")
		}
		if strings.TrimSpace(agg.ValueText) == "" {
			return apperrors.BadRequest("invalid_aggregate_value", "aggregate value_text is required")
		}
		if agg.ResultKind == string(AggregateResultKindTerm) && agg.TermNo == nil {
			return apperrors.BadRequest("invalid_term_aggregate", "term aggregate requires term_no")
		}
		if agg.ResultKind == string(AggregateResultKindYear) && strings.TrimSpace(agg.YearLabel) == "" {
			return apperrors.BadRequest("invalid_year_aggregate", "year aggregate requires year_label")
		}
	}

	for _, att := range bundle.Attendance {
		if _, err := time.Parse("2006-01-02", att.RecordedOn); err != nil {
			return apperrors.BadRequest("invalid_attendance_date", "attendance recorded_on must match YYYY-MM-DD")
		}
		if att.NormalizedStatus != "" {
			switch att.NormalizedStatus {
			case "present", "absent", "late", "excused", "unknown":
			default:
				return apperrors.BadRequest("invalid_attendance_status", "attendance normalized_status is invalid")
			}
		}
	}
	return nil
}

func hasAcademicDataV2(bundle CanonicalIngestBundleV2) bool {
	return len(bundle.Lessons) > 0 ||
		len(bundle.Results) > 0 ||
		len(bundle.Aggregates) > 0 ||
		len(bundle.Attendance) > 0
}

// validateAuthoritativeAcademicEmptyV2 intentionally admits only the
// identity shape produced after a complete Kundelik connector sync. The
// authenticated mobile pipeline is responsible for not submitting a bundle
// when any required provider request fails; the backend additionally binds
// the provider identity to the submitted source account before accepting an
// academically empty snapshot.
func validateAuthoritativeAcademicEmptyV2(bundle CanonicalIngestBundleV2) error {
	identity := bundle.Identity
	if bundle.Source != "kundelik" {
		return apperrors.BadRequest("empty_bundle_not_authoritative", "academic-empty ingest is supported only for an authoritative Kundelik snapshot")
	}
	if bundle.SyncedAt.IsZero() ||
		bundle.SourceAccount == "" ||
		identity.ProviderAccountRef == "" ||
		identity.ProviderAccountRef != bundle.SourceAccount ||
		identity.ProviderPersonID == "" ||
		identity.ProviderSchoolID == "" ||
		identity.ProviderGroupID == "" {
		return apperrors.BadRequest("empty_bundle_not_authoritative", "academic-empty ingest requires a complete provider-bound identity")
	}
	return nil
}

func checksumBundleV2(bundle CanonicalIngestBundleV2) (string, error) {
	payload, err := json.Marshal(bundle)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(payload)
	return hex.EncodeToString(sum[:]), nil
}
