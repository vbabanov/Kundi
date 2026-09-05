DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_academic_results_result_kind_non_blank'
      AND conrelid = 'academic_results'::regclass
  ) THEN
    ALTER TABLE academic_results
      ADD CONSTRAINT chk_academic_results_result_kind_non_blank
      CHECK (length(trim(result_kind)) > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_academic_results_identity_present'
      AND conrelid = 'academic_results'::regclass
  ) THEN
    ALTER TABLE academic_results
      ADD CONSTRAINT chk_academic_results_identity_present
      CHECK (
        length(trim(provider_mark_id)) > 0
        OR length(trim(source_result_key)) > 0
        OR length(trim(provider_work_id)) > 0
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_academic_aggregates_kind_dimensions'
      AND conrelid = 'academic_aggregates'::regclass
  ) THEN
    ALTER TABLE academic_aggregates
      ADD CONSTRAINT chk_academic_aggregates_kind_dimensions
      CHECK (
        (result_kind = 'term' AND term_no IS NOT NULL)
        OR (result_kind = 'year' AND length(trim(year_label)) > 0)
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_academic_result_evidence_owner'
      AND conrelid = 'academic_result_evidence'::regclass
  ) THEN
    ALTER TABLE academic_result_evidence
      ADD CONSTRAINT chk_academic_result_evidence_owner
      CHECK (
        (result_id IS NOT NULL AND aggregate_id IS NULL)
        OR (result_id IS NULL AND aggregate_id IS NOT NULL)
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_attendance_normalized_status'
      AND conrelid = 'attendance_events'::regclass
  ) THEN
    ALTER TABLE attendance_events
      ADD CONSTRAINT chk_attendance_normalized_status
      CHECK (normalized_status IN ('present', 'absent', 'late', 'excused', 'unknown'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_lessons_student_provider_source_lesson_key
ON lessons(student_id, provider, source_lesson_key);

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_results_student_provider_source_result_key
ON academic_results(student_id, provider, source_result_key)
WHERE source_result_key <> '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_results_student_provider_mark_id
ON academic_results(student_id, provider, provider_mark_id)
WHERE provider_mark_id <> '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_results_regular_fingerprint
ON academic_results(
  student_id,
  provider,
  provider_subject_id,
  provider_work_id,
  value_text,
  recorded_on,
  COALESCE(lesson_id, '00000000-0000-0000-0000-000000000000'::uuid)
)
WHERE result_kind = 'regular' AND provider_mark_id = '' AND source_result_key = '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_results_summative_fingerprint
ON academic_results(
  student_id,
  provider,
  result_kind,
  provider_subject_id,
  provider_work_id,
  COALESCE(term_no, -1)
)
WHERE result_kind IN ('sor', 'soch') AND provider_mark_id = '' AND source_result_key = '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_aggregates_student_provider_source_key
ON academic_aggregates(student_id, provider, source_aggregate_key)
WHERE source_aggregate_key <> '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_aggregates_term_identity
ON academic_aggregates(
  student_id,
  provider,
  provider_subject_id,
  result_kind,
  term_no,
  period_id
)
WHERE result_kind = 'term';

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_aggregates_year_identity
ON academic_aggregates(
  student_id,
  provider,
  provider_subject_id,
  result_kind,
  year_label
)
WHERE result_kind = 'year';

CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_student_provider_event_key
ON attendance_events(student_id, provider, provider_event_key)
WHERE provider_event_key <> '';

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_result_evidence_fingerprint_per_result
ON academic_result_evidence(result_id, fingerprint_sha256)
WHERE result_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_result_evidence_fingerprint_per_aggregate
ON academic_result_evidence(aggregate_id, fingerprint_sha256)
WHERE aggregate_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_academic_results_lookup
ON academic_results(student_id, provider, result_kind, recorded_on DESC);

CREATE INDEX IF NOT EXISTS idx_academic_aggregates_lookup
ON academic_aggregates(student_id, provider, result_kind, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_provider_identity_snapshots_lookup
ON provider_identity_snapshots(student_id, provider);

CREATE INDEX IF NOT EXISTS idx_ingest_batches_provider
ON ingest_batches(student_id, provider, ingested_at DESC);
