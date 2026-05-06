package integration

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	ingest "github.com/kundi/kundi/backend/internal/modules/diary_ingest"
)

type inMemoryV2Repo struct {
	mu sync.Mutex

	batches map[string]v2Batch

	results       map[string]*v2ResultRow
	aggregates    map[string]*v2AggregateRow
	evidences     map[string]v2EvidenceRow
	resultByMark  map[string]string
	resultByKey   map[string]string
	resultByRegFP map[string]string
	resultBySumFP map[string]string
	aggByKey      map[string]string
	aggByTermFP   map[string]string
	aggByYearFP   map[string]string

	nextID     int
	mergeCalls int
}

type v2Batch struct {
	checksum string
	id       uuid.UUID
}

type v2ResultRow struct {
	ID                string
	Provider          string
	Kind              string
	ProviderMarkID    string
	SourceResultKey   string
	ProviderSubjectID string
	SubjectName       string
	ProviderWorkID    string
	ValueText         string
	RecordedOn        string
	TermNo            int
	LessonRefKey      string
	ResolvedMood      string
	Precedence        int
}

type v2AggregateRow struct {
	ID                 string
	Provider           string
	Kind               string
	SourceAggregateKey string
	ProviderSubjectID  string
	SubjectName        string
	PeriodID           string
	TermNo             int
	YearLabel          string
	ValueText          string
	RecordedOn         string
	ResolvedMood       string
	Precedence         int
}

type v2EvidenceRow struct {
	OwnerType     string
	OwnerID       string
	Fingerprint   string
	Endpoint      string
	SourceMoodRaw string
}

func newInMemoryV2Repo() *inMemoryV2Repo {
	return &inMemoryV2Repo{
		batches:       make(map[string]v2Batch),
		results:       make(map[string]*v2ResultRow),
		aggregates:    make(map[string]*v2AggregateRow),
		evidences:     make(map[string]v2EvidenceRow),
		resultByMark:  make(map[string]string),
		resultByKey:   make(map[string]string),
		resultByRegFP: make(map[string]string),
		resultBySumFP: make(map[string]string),
		aggByKey:      make(map[string]string),
		aggByTermFP:   make(map[string]string),
		aggByYearFP:   make(map[string]string),
	}
}

func (r *inMemoryV2Repo) CreateBatch(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle, _ string) (uuid.UUID, bool, error) {
	return uuid.New(), true, nil
}

func (r *inMemoryV2Repo) MergeBundle(_ context.Context, _ uuid.UUID, _ ingest.CanonicalIngestBundle) (int, int, error) {
	return 0, 0, nil
}

func (r *inMemoryV2Repo) CreateBatchV2(_ context.Context, studentID uuid.UUID, bundle ingest.CanonicalIngestBundleV2, checksum string) (uuid.UUID, bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	key := studentID.String() + ":" + bundle.IdempotencyKey
	if existing, ok := r.batches[key]; ok {
		if existing.checksum != checksum {
			return existing.id, false, ingest.ErrIdempotencyConflict
		}
		return existing.id, false, nil
	}
	id := uuid.New()
	r.batches[key] = v2Batch{checksum: checksum, id: id}
	return id, true, nil
}

func (r *inMemoryV2Repo) MarkMerged(_ context.Context, _ uuid.UUID) error { return nil }

func (r *inMemoryV2Repo) MergeBundleV2(_ context.Context, _ uuid.UUID, bundle ingest.CanonicalIngestBundleV2) (ingest.MergeStatsV2, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.mergeCalls++

	stats := ingest.MergeStatsV2{}
	for _, lesson := range bundle.Lessons {
		if strings.TrimSpace(lesson.SourceLessonKey) != "" {
			stats.MergedLessons++
		}
	}

	resultEvidenceByRef := map[string]ingest.CanonicalResultEvidenceV2{}
	aggregateEvidenceByRef := map[string]ingest.CanonicalResultEvidenceV2{}
	for _, ev := range bundle.Evidence {
		if key := strings.TrimSpace(ev.SourceResultRefKey); key != "" {
			resultEvidenceByRef[key] = ev
		}
		if key := strings.TrimSpace(ev.SourceAggregateRefKey); key != "" {
			aggregateEvidenceByRef[key] = ev
		}
	}

	for _, incoming := range bundle.Results {
		id, existed := r.findOrCreateResult(bundle.Identity, incoming)
		stats.MergedResults++
		ev, ok := resultEvidenceByRef[incoming.SourceResultKey]
		if !ok {
			ev = syntheticResultEvidence(bundle.Identity, incoming)
		}
		changed := r.applyResultPrecedence(id, incoming, ev)
		if inserted := r.insertEvidence("result", id, ev); inserted || changed {
			if inserted {
				stats.InsertedEvidence++
			}
		}
		_ = existed
	}

	for _, incoming := range bundle.Aggregates {
		id, _ := r.findOrCreateAggregate(bundle.Identity, incoming)
		stats.MergedAggregates++
		ev, ok := aggregateEvidenceByRef[incoming.SourceAggregateKey]
		if !ok {
			ev = syntheticAggregateEvidence(bundle.Identity, incoming)
		}
		changed := r.applyAggregatePrecedence(id, incoming, ev)
		if inserted := r.insertEvidence("aggregate", id, ev); inserted || changed {
			if inserted {
				stats.InsertedEvidence++
			}
		}
	}

	for _, att := range bundle.Attendance {
		if strings.TrimSpace(att.RecordedOn) != "" {
			stats.MergedAttendance++
		}
	}
	return stats, nil
}

func (r *inMemoryV2Repo) findOrCreateResult(identity ingest.CanonicalProviderIdentityV2, incoming ingest.CanonicalAcademicResultV2) (string, bool) {
	if incoming.ProviderMarkID != "" {
		k := incoming.ProviderMarkID
		if id, ok := r.resultByMark[k]; ok {
			return id, true
		}
	}
	if incoming.SourceResultKey != "" {
		k := incoming.SourceResultKey
		if id, ok := r.resultByKey[k]; ok {
			return id, true
		}
	}
	if incoming.ResultKind == string(ingest.EventResultKindRegular) {
		fp := regularFingerprint(identity, incoming)
		if id, ok := r.resultByRegFP[fp]; ok {
			return id, true
		}
	} else {
		fp := summativeFingerprint(identity, incoming)
		if id, ok := r.resultBySumFP[fp]; ok {
			return id, true
		}
	}

	r.nextID++
	id := fmt.Sprintf("res-%d", r.nextID)
	row := &v2ResultRow{
		ID:                id,
		Provider:          identity.Provider,
		Kind:              incoming.ResultKind,
		ProviderMarkID:    incoming.ProviderMarkID,
		SourceResultKey:   incoming.SourceResultKey,
		ProviderSubjectID: incoming.ProviderSubjectID,
		SubjectName:       incoming.SubjectName,
		ProviderWorkID:    incoming.ProviderWorkID,
		ValueText:         incoming.ValueText,
		RecordedOn:        incoming.RecordedOn,
		TermNo:            intValue(incoming.TermNo),
		LessonRefKey:      incoming.LessonRefKey,
		ResolvedMood:      incoming.ResolvedMood,
		Precedence:        0,
	}
	r.results[id] = row
	if incoming.ProviderMarkID != "" {
		r.resultByMark[incoming.ProviderMarkID] = id
	}
	if incoming.SourceResultKey != "" {
		r.resultByKey[incoming.SourceResultKey] = id
	}
	if incoming.ResultKind == string(ingest.EventResultKindRegular) {
		r.resultByRegFP[regularFingerprint(identity, incoming)] = id
	} else {
		r.resultBySumFP[summativeFingerprint(identity, incoming)] = id
	}
	return id, false
}

func (r *inMemoryV2Repo) findOrCreateAggregate(identity ingest.CanonicalProviderIdentityV2, incoming ingest.CanonicalAcademicAggregate) (string, bool) {
	if incoming.SourceAggregateKey != "" {
		if id, ok := r.aggByKey[incoming.SourceAggregateKey]; ok {
			return id, true
		}
	}
	if incoming.ResultKind == string(ingest.AggregateResultKindTerm) {
		fp := termFingerprint(identity, incoming)
		if id, ok := r.aggByTermFP[fp]; ok {
			return id, true
		}
	} else {
		fp := yearFingerprint(identity, incoming)
		if id, ok := r.aggByYearFP[fp]; ok {
			return id, true
		}
	}

	r.nextID++
	id := fmt.Sprintf("agg-%d", r.nextID)
	row := &v2AggregateRow{
		ID:                 id,
		Provider:           identity.Provider,
		Kind:               incoming.ResultKind,
		SourceAggregateKey: incoming.SourceAggregateKey,
		ProviderSubjectID:  incoming.ProviderSubjectID,
		SubjectName:        incoming.SubjectName,
		PeriodID:           incoming.PeriodID,
		TermNo:             intValue(incoming.TermNo),
		YearLabel:          incoming.YearLabel,
		ValueText:          incoming.ValueText,
		RecordedOn:         incoming.RecordedOn,
		ResolvedMood:       incoming.ResolvedMood,
		Precedence:         0,
	}
	r.aggregates[id] = row
	if incoming.SourceAggregateKey != "" {
		r.aggByKey[incoming.SourceAggregateKey] = id
	}
	if incoming.ResultKind == string(ingest.AggregateResultKindTerm) {
		r.aggByTermFP[termFingerprint(identity, incoming)] = id
	} else {
		r.aggByYearFP[yearFingerprint(identity, incoming)] = id
	}
	return id, false
}

func (r *inMemoryV2Repo) insertEvidence(ownerType string, ownerID string, ev ingest.CanonicalResultEvidenceV2) bool {
	fp := strings.TrimSpace(ev.FingerprintSHA256)
	if fp == "" {
		return false
	}
	key := ownerType + ":" + ownerID + ":" + fp
	if _, exists := r.evidences[key]; exists {
		return false
	}
	r.evidences[key] = v2EvidenceRow{
		OwnerType:     ownerType,
		OwnerID:       ownerID,
		Fingerprint:   fp,
		Endpoint:      strings.ToLower(strings.TrimSpace(ev.SourceEndpoint)),
		SourceMoodRaw: ev.SourceMoodRaw,
	}
	return true
}

func (r *inMemoryV2Repo) applyResultPrecedence(id string, incoming ingest.CanonicalAcademicResultV2, ev ingest.CanonicalResultEvidenceV2) bool {
	row := r.results[id]
	if row == nil {
		return false
	}
	incomingP := endpointPrecedence(ev.SourceEndpoint)
	changed := false
	if incomingP > row.Precedence {
		if strings.TrimSpace(incoming.ResolvedMood) != "" && row.ResolvedMood != incoming.ResolvedMood {
			row.ResolvedMood = incoming.ResolvedMood
			changed = true
		}
		if strings.TrimSpace(incoming.LessonRefKey) != "" && row.LessonRefKey != incoming.LessonRefKey {
			row.LessonRefKey = incoming.LessonRefKey
			changed = true
		}
		row.Precedence = incomingP
	}
	return changed
}

func (r *inMemoryV2Repo) applyAggregatePrecedence(id string, incoming ingest.CanonicalAcademicAggregate, ev ingest.CanonicalResultEvidenceV2) bool {
	row := r.aggregates[id]
	if row == nil {
		return false
	}
	incomingP := endpointPrecedence(ev.SourceEndpoint)
	changed := false
	if incomingP > row.Precedence {
		if strings.TrimSpace(incoming.ResolvedMood) != "" && row.ResolvedMood != incoming.ResolvedMood {
			row.ResolvedMood = incoming.ResolvedMood
			changed = true
		}
		row.Precedence = incomingP
	}
	return changed
}

func endpointPrecedence(endpoint string) int {
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

func regularFingerprint(identity ingest.CanonicalProviderIdentityV2, incoming ingest.CanonicalAcademicResultV2) string {
	return digest(
		identity.Provider,
		identity.ProviderPersonID,
		incoming.ProviderSubjectID,
		incoming.ProviderWorkID,
		incoming.ValueText,
		incoming.RecordedOn,
		incoming.LessonRefKey,
	)
}

func summativeFingerprint(identity ingest.CanonicalProviderIdentityV2, incoming ingest.CanonicalAcademicResultV2) string {
	return digest(
		identity.Provider,
		identity.ProviderPersonID,
		incoming.ResultKind,
		incoming.ProviderSubjectID,
		incoming.ProviderWorkID,
		intString(incoming.TermNo),
		incoming.ValueText,
		incoming.RecordedOn,
	)
}

func termFingerprint(identity ingest.CanonicalProviderIdentityV2, incoming ingest.CanonicalAcademicAggregate) string {
	return digest(identity.Provider, identity.ProviderPersonID, incoming.ResultKind, incoming.ProviderSubjectID, incoming.PeriodID, intString(incoming.TermNo))
}

func yearFingerprint(identity ingest.CanonicalProviderIdentityV2, incoming ingest.CanonicalAcademicAggregate) string {
	return digest(identity.Provider, identity.ProviderPersonID, incoming.ResultKind, incoming.ProviderSubjectID, incoming.YearLabel)
}

func syntheticResultEvidence(identity ingest.CanonicalProviderIdentityV2, incoming ingest.CanonicalAcademicResultV2) ingest.CanonicalResultEvidenceV2 {
	fp := digest(
		"res",
		identity.Provider,
		identity.ProviderPersonID,
		incoming.ResultKind,
		incoming.ProviderSubjectID,
		incoming.ProviderWorkID,
		incoming.ProviderMarkID,
		incoming.SourceResultKey,
		incoming.ValueText,
		incoming.RecordedOn,
		incoming.LessonRefKey,
	)
	return ingest.CanonicalResultEvidenceV2{
		SourceResultRefKey: incoming.SourceResultKey,
		SourceEndpoint:     "unknown",
		ProviderWorkID:     incoming.ProviderWorkID,
		ProviderMarkID:     incoming.ProviderMarkID,
		SourceMoodRaw:      incoming.ResolvedMood,
		FingerprintSHA256:  fp,
	}
}

func syntheticAggregateEvidence(identity ingest.CanonicalProviderIdentityV2, incoming ingest.CanonicalAcademicAggregate) ingest.CanonicalResultEvidenceV2 {
	fp := digest(
		"agg",
		identity.Provider,
		identity.ProviderPersonID,
		incoming.ResultKind,
		incoming.ProviderSubjectID,
		incoming.SourceAggregateKey,
		incoming.PeriodID,
		incoming.YearLabel,
		incoming.ValueText,
		incoming.RecordedOn,
	)
	return ingest.CanonicalResultEvidenceV2{
		SourceAggregateRefKey: incoming.SourceAggregateKey,
		SourceEndpoint:        "unknown",
		SourceMoodRaw:         incoming.ResolvedMood,
		FingerprintSHA256:     fp,
	}
}

func digest(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, "|")))
	return hex.EncodeToString(sum[:])
}

func intString(v *int) string {
	if v == nil {
		return ""
	}
	return fmt.Sprintf("%d", *v)
}

func intValue(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}

func bundleV2(identity ingest.CanonicalProviderIdentityV2, idempotency string, lessons []ingest.CanonicalLessonV2, results []ingest.CanonicalAcademicResultV2, aggregates []ingest.CanonicalAcademicAggregate, evidence []ingest.CanonicalResultEvidenceV2) ingest.CanonicalIngestBundleV2 {
	return ingest.CanonicalIngestBundleV2{
		ContractVersion: 2,
		Source:          "kundelik",
		SourceAccount:   "student",
		IdempotencyKey:  idempotency,
		SyncedAt:        time.Now().UTC(),
		Identity:        identity,
		Lessons:         lessons,
		Results:         results,
		Aggregates:      aggregates,
		Attendance:      nil,
		Evidence:        evidence,
	}
}

func testIdentity() ingest.CanonicalProviderIdentityV2 {
	return ingest.CanonicalProviderIdentityV2{
		Provider:         "kundelik",
		ProviderPersonID: "1000016003118",
		ProviderSchoolID: "1000001828996",
		ProviderGroupID:  "2370210495004756744",
	}
}

func ingestV2(t *testing.T, svc *ingest.Service, studentID uuid.UUID, bundle ingest.CanonicalIngestBundleV2) ingest.IngestResultV2 {
	t.Helper()
	result, err := svc.IngestBundleV2(context.Background(), studentID, bundle)
	if err != nil {
		t.Fatalf("ingest v2 failed: %v", err)
	}
	return result
}

func TestV2DiaryThenPeriodDuplicateRegularCreatesOneCanonicalTwoEvidence(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()

	lesson := ingest.CanonicalLessonV2{
		SourceLessonKey:   "lesson-1",
		ProviderLessonID:  "241",
		Date:              "2026-03-11",
		LessonNumber:      3,
		ProviderSubjectID: "subj-1",
		SubjectName:       "Physics",
	}
	regular := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "res-regular-1",
		ResultKind:        "regular",
		ProviderMarkID:    "mark-777",
		ProviderWorkID:    "work-777",
		ProviderSubjectID: "subj-1",
		SubjectName:       "Physics",
		LessonRefKey:      "lesson-1",
		RecordedOn:        "2026-03-11",
		ValueText:         "8",
		ResolvedMood:      "Good",
	}

	ingestV2(t, svc, studentID, bundleV2(id, "v2-dup-1", []ingest.CanonicalLessonV2{lesson}, []ingest.CanonicalAcademicResultV2{regular}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-regular-1", SourceEndpoint: "diary", FingerprintSHA256: "fp-diary-1", SourceMoodRaw: "Good"},
	}))
	ingestV2(t, svc, studentID, bundleV2(id, "v2-dup-2", nil, []ingest.CanonicalAcademicResultV2{regular}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-regular-1", SourceEndpoint: "period", FingerprintSHA256: "fp-period-1", SourceMoodRaw: "Average"},
	}))

	if got := len(repo.results); got != 1 {
		t.Fatalf("expected 1 canonical result, got %d", got)
	}
	if got := len(repo.evidences); got != 2 {
		t.Fatalf("expected 2 evidences, got %d", got)
	}
}

func TestV2PeriodThenDiaryDuplicateRegularDiaryPrecedenceWins(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()

	periodResult := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "res-period-first",
		ResultKind:        "regular",
		ProviderMarkID:    "mark-900",
		ProviderWorkID:    "work-900",
		ProviderSubjectID: "subj-2",
		SubjectName:       "Math",
		LessonRefKey:      "",
		RecordedOn:        "2026-03-12",
		ValueText:         "7",
		ResolvedMood:      "Average",
	}
	diaryResult := periodResult
	diaryResult.LessonRefKey = "lesson-x"
	diaryResult.ResolvedMood = "Good"

	ingestV2(t, svc, studentID, bundleV2(id, "v2-order-1", nil, []ingest.CanonicalAcademicResultV2{periodResult}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-period-first", SourceEndpoint: "period", FingerprintSHA256: "fp-order-period", SourceMoodRaw: "Average"},
	}))
	ingestV2(t, svc, studentID, bundleV2(id, "v2-order-2", nil, []ingest.CanonicalAcademicResultV2{diaryResult}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-period-first", SourceEndpoint: "diary", FingerprintSHA256: "fp-order-diary", SourceMoodRaw: "Good"},
	}))

	if got := len(repo.results); got != 1 {
		t.Fatalf("expected 1 canonical result, got %d", got)
	}
	if got := len(repo.evidences); got != 2 {
		t.Fatalf("expected 2 evidences, got %d", got)
	}
	for _, row := range repo.results {
		if row.ResolvedMood != "Good" {
			t.Fatalf("expected diary precedence mood=Good, got %s", row.ResolvedMood)
		}
		if row.LessonRefKey != "lesson-x" {
			t.Fatalf("expected lesson linkage from diary, got %s", row.LessonRefKey)
		}
	}
}

func TestV2EvidenceOnlyScenarioAddsEvidenceWithoutNewCanonical(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()

	result := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "res-ev-1",
		ResultKind:        "regular",
		ProviderMarkID:    "mark-ev-1",
		ProviderWorkID:    "work-ev-1",
		ProviderSubjectID: "subj-3",
		SubjectName:       "Chem",
		LessonRefKey:      "lesson-a",
		RecordedOn:        "2026-03-13",
		ValueText:         "9",
		ResolvedMood:      "Good",
	}

	ingestV2(t, svc, studentID, bundleV2(id, "v2-ev-01", nil, []ingest.CanonicalAcademicResultV2{result}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-ev-1", SourceEndpoint: "diary", FingerprintSHA256: "fp-ev-a", SourceMoodRaw: "Good"},
	}))
	ingestV2(t, svc, studentID, bundleV2(id, "v2-ev-02", nil, []ingest.CanonicalAcademicResultV2{result}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-ev-1", SourceEndpoint: "period", FingerprintSHA256: "fp-ev-b", SourceMoodRaw: "Average"},
	}))

	if got := len(repo.results); got != 1 {
		t.Fatalf("expected 1 canonical result, got %d", got)
	}
	if got := len(repo.evidences); got != 2 {
		t.Fatalf("expected evidence-only insert to increase evidences to 2, got %d", got)
	}
}

func TestV2NoMatchCreatesNewCanonicalRow(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()

	a := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "res-nm-a",
		ResultKind:        "regular",
		ProviderMarkID:    "",
		ProviderWorkID:    "work-1",
		ProviderSubjectID: "subj-4",
		SubjectName:       "Biology",
		LessonRefKey:      "lesson-1",
		RecordedOn:        "2026-03-14",
		ValueText:         "8",
		ResolvedMood:      "Good",
	}
	b := a
	b.SourceResultKey = "res-nm-b"
	b.ProviderWorkID = "work-2"

	ingestV2(t, svc, studentID, bundleV2(id, "v2-nm-01", nil, []ingest.CanonicalAcademicResultV2{a}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-nm-a", SourceEndpoint: "diary", FingerprintSHA256: "fp-nm-a"},
	}))
	ingestV2(t, svc, studentID, bundleV2(id, "v2-nm-02", nil, []ingest.CanonicalAcademicResultV2{b}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-nm-b", SourceEndpoint: "period", FingerprintSHA256: "fp-nm-b"},
	}))

	if got := len(repo.results); got != 2 {
		t.Fatalf("expected 2 canonical rows for no-match scenario, got %d", got)
	}
}

func TestV2SorSochSeparatedFromRegular(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()
	term := 3

	regular := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "res-kind-regular",
		ResultKind:        "regular",
		ProviderWorkID:    "work-shared",
		ProviderSubjectID: "subj-5",
		SubjectName:       "History",
		RecordedOn:        "2026-03-15",
		ValueText:         "10",
	}
	sor := regular
	sor.SourceResultKey = "res-kind-sor"
	sor.ResultKind = "sor"
	sor.TermNo = &term

	ingestV2(t, svc, studentID, bundleV2(id, "v2-kind-1", nil, []ingest.CanonicalAcademicResultV2{regular, sor}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-kind-regular", SourceEndpoint: "diary", FingerprintSHA256: "fp-kind-regular"},
		{SourceResultRefKey: "res-kind-sor", SourceEndpoint: "period", FingerprintSHA256: "fp-kind-sor"},
	}))

	if got := len(repo.results); got != 2 {
		t.Fatalf("expected separate canonical rows for regular and sor, got %d", got)
	}
}

func TestV2TermYearWrittenOnlyToAggregates(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()
	term := 3

	termAgg := ingest.CanonicalAcademicAggregate{
		SourceAggregateKey: "agg-term-1",
		ResultKind:         "term",
		ProviderSubjectID:  "subj-6",
		SubjectName:        "Geo",
		PeriodID:           "period-3",
		TermNo:             &term,
		RecordedOn:         "2026-03-16",
		ValueText:          "3",
	}
	yearAgg := ingest.CanonicalAcademicAggregate{
		SourceAggregateKey: "agg-year-1",
		ResultKind:         "year",
		ProviderSubjectID:  "subj-6",
		SubjectName:        "Geo",
		YearLabel:          "2025/2026",
		RecordedOn:         "2026-03-16",
		ValueText:          "4",
	}

	ingestV2(t, svc, studentID, bundleV2(id, "v2-agg-1", nil, nil, []ingest.CanonicalAcademicAggregate{termAgg, yearAgg}, []ingest.CanonicalResultEvidenceV2{
		{SourceAggregateRefKey: "agg-term-1", SourceEndpoint: "period", FingerprintSHA256: "fp-agg-term"},
		{SourceAggregateRefKey: "agg-year-1", SourceEndpoint: "final", FingerprintSHA256: "fp-agg-year"},
	}))

	if got := len(repo.results); got != 0 {
		t.Fatalf("expected no event-level results, got %d", got)
	}
	if got := len(repo.aggregates); got != 2 {
		t.Fatalf("expected 2 aggregates, got %d", got)
	}
	for _, ev := range repo.evidences {
		if ev.OwnerType != "aggregate" {
			t.Fatalf("expected aggregate-linked evidence only, got owner=%s", ev.OwnerType)
		}
	}
}

func TestV2MoodPrecedencePreservesBothSources(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()

	res := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "res-mood-1",
		ResultKind:        "regular",
		ProviderMarkID:    "mark-mood-1",
		ProviderWorkID:    "work-mood-1",
		ProviderSubjectID: "subj-7",
		SubjectName:       "Eng",
		RecordedOn:        "2026-03-17",
		ValueText:         "8",
		ResolvedMood:      "Average",
	}
	ingestV2(t, svc, studentID, bundleV2(id, "v2-mood-1", nil, []ingest.CanonicalAcademicResultV2{res}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-mood-1", SourceEndpoint: "period", FingerprintSHA256: "fp-mood-period", SourceMoodRaw: "Average"},
	}))
	res.ResolvedMood = "Good"
	ingestV2(t, svc, studentID, bundleV2(id, "v2-mood-2", nil, []ingest.CanonicalAcademicResultV2{res}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-mood-1", SourceEndpoint: "diary", FingerprintSHA256: "fp-mood-diary", SourceMoodRaw: "Good"},
	}))

	if got := len(repo.results); got != 1 {
		t.Fatalf("expected 1 result, got %d", got)
	}
	var row *v2ResultRow
	for _, v := range repo.results {
		row = v
	}
	if row.ResolvedMood != "Good" {
		t.Fatalf("expected resolved mood from diary=Good, got %s", row.ResolvedMood)
	}
	if got := len(repo.evidences); got != 2 {
		t.Fatalf("expected both mood sources in evidence, got %d", got)
	}
}

func TestV2IdempotencyReplayDoesNotDuplicateCanonicalOrEvidence(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()

	res := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "res-replay-1",
		ResultKind:        "regular",
		ProviderMarkID:    "mark-replay-1",
		ProviderWorkID:    "work-replay-1",
		ProviderSubjectID: "subj-8",
		SubjectName:       "Lit",
		RecordedOn:        "2026-03-18",
		ValueText:         "7",
	}
	b := bundleV2(id, "v2-replay-key", nil, []ingest.CanonicalAcademicResultV2{res}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-replay-1", SourceEndpoint: "diary", FingerprintSHA256: "fp-replay-1"},
	})

	first := ingestV2(t, svc, studentID, b)
	second := ingestV2(t, svc, studentID, b)

	if first.AlreadyProcessed {
		t.Fatalf("expected first replay attempt to be fresh")
	}
	if !second.AlreadyProcessed {
		t.Fatalf("expected second replay attempt to be idempotent")
	}
	if got := len(repo.results); got != 1 {
		t.Fatalf("expected 1 result, got %d", got)
	}
	if got := len(repo.evidences); got != 1 {
		t.Fatalf("expected 1 evidence, got %d", got)
	}
	if repo.mergeCalls != 1 {
		t.Fatalf("expected merge to run once, got %d", repo.mergeCalls)
	}
}

func TestV2WeakFingerprintProtectionNoFalseMerge(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()

	a := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "res-wfp-a",
		ResultKind:        "regular",
		ProviderWorkID:    "work-a",
		ProviderSubjectID: "subj-9",
		SubjectName:       "Chem",
		RecordedOn:        "2026-03-19",
		ValueText:         "8",
		LessonRefKey:      "lesson-1",
	}
	b := a
	b.SourceResultKey = "res-wfp-b"
	b.ProviderWorkID = "work-b"

	ingestV2(t, svc, studentID, bundleV2(id, "v2-wfp-1", nil, []ingest.CanonicalAcademicResultV2{a, b}, nil, []ingest.CanonicalResultEvidenceV2{
		{SourceResultRefKey: "res-wfp-a", SourceEndpoint: "diary", FingerprintSHA256: "fp-wfp-a"},
		{SourceResultRefKey: "res-wfp-b", SourceEndpoint: "diary", FingerprintSHA256: "fp-wfp-b"},
	}))

	if got := len(repo.results); got != 2 {
		t.Fatalf("expected 2 different results (no false merge), got %d", got)
	}
}

func TestV2SummativeKeepsMultipleEntriesSameTermAndSubject(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()
	term := 2

	first := ingest.CanonicalAcademicResultV2{
		SourceResultKey:   "",
		ResultKind:        "sor",
		ProviderWorkID:    "section-1",
		ProviderMarkID:    "",
		ProviderSubjectID: "subject-1",
		SubjectName:       "Алгебра",
		RecordedOn:        "2026-03-20",
		TermNo:            &term,
		ValueText:         "8/10",
	}
	second := first
	second.ValueText = "9/10"

	ingestV2(t, svc, studentID, bundleV2(id, "v2-summative-multi", nil, []ingest.CanonicalAcademicResultV2{first, second}, nil, nil))

	if got := len(repo.results); got != 2 {
		t.Fatalf("expected 2 summative rows, got %d", got)
	}
}

func TestV2LessonNumberZeroAccepted(t *testing.T) {
	repo := newInMemoryV2Repo()
	svc := ingest.NewService(repo)
	studentID := uuid.New()
	id := testIdentity()

	lesson := ingest.CanonicalLessonV2{
		SourceLessonKey: "lesson-zero",
		Date:            "2026-03-21",
		LessonNumber:    0,
		SubjectName:     "Информатика",
		LessonPlace:     "312",
		StartTime:       "17:30",
		EndTime:         "18:15",
	}

	result := ingestV2(t, svc, studentID, bundleV2(id, "v2-lesson-zero", []ingest.CanonicalLessonV2{lesson}, nil, nil, nil))
	if result.MergedLessons != 1 {
		t.Fatalf("expected merged lessons = 1, got %d", result.MergedLessons)
	}
}
