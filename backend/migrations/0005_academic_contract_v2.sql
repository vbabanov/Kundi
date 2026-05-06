-- Canonical Academic Contract v2 (baseline):
-- result kinds baseline: regular, sor, soch, term, year

CREATE TABLE IF NOT EXISTS provider_identity_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('kundelik', 'dnevnikru', 'edupage')),
  provider_account_ref TEXT NOT NULL DEFAULT '',
  provider_person_id TEXT NOT NULL DEFAULT '',
  provider_school_id TEXT NOT NULL DEFAULT '',
  provider_group_id TEXT NOT NULL DEFAULT '',
  school_name TEXT NOT NULL DEFAULT '',
  class_label TEXT NOT NULL DEFAULT '',
  class_teacher_full_name TEXT NOT NULL DEFAULT '',
  student_full_name TEXT NOT NULL DEFAULT '',
  captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, provider)
);

CREATE TABLE IF NOT EXISTS student_app_profiles (
  student_id UUID PRIMARY KEY REFERENCES students(id) ON DELETE CASCADE,
  shift SMALLINT CHECK (shift IN (1, 2)),
  parent_phone_1 TEXT NOT NULL DEFAULT '',
  parent_phone_2 TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS academic_event_result_kinds (
  kind TEXT PRIMARY KEY,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS academic_aggregate_result_kinds (
  kind TEXT PRIMARY KEY,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO academic_event_result_kinds(kind)
VALUES ('regular'), ('sor'), ('soch')
ON CONFLICT (kind) DO NOTHING;

INSERT INTO academic_aggregate_result_kinds(kind)
VALUES ('term'), ('year')
ON CONFLICT (kind) DO NOTHING;

CREATE TABLE IF NOT EXISTS academic_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('kundelik', 'dnevnikru', 'edupage')),
  lesson_id UUID REFERENCES lessons(id) ON DELETE SET NULL,
  result_kind TEXT NOT NULL REFERENCES academic_event_result_kinds(kind),
  provider_subject_id TEXT NOT NULL DEFAULT '',
  subject_name TEXT NOT NULL,
  provider_work_id TEXT NOT NULL DEFAULT '',
  provider_mark_id TEXT NOT NULL DEFAULT '',
  source_result_key TEXT NOT NULL DEFAULT '',
  value_text TEXT NOT NULL,
  value_numeric NUMERIC(7,2),
  resolved_mood TEXT NOT NULL DEFAULT '',
  period_id TEXT NOT NULL DEFAULT '',
  term_no SMALLINT CHECK (term_no BETWEEN 1 AND 4),
  recorded_on DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS academic_aggregates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('kundelik', 'dnevnikru', 'edupage')),
  result_kind TEXT NOT NULL REFERENCES academic_aggregate_result_kinds(kind),
  provider_subject_id TEXT NOT NULL DEFAULT '',
  subject_name TEXT NOT NULL,
  period_id TEXT NOT NULL DEFAULT '',
  term_no SMALLINT CHECK (term_no BETWEEN 1 AND 4),
  year_label TEXT NOT NULL DEFAULT '',
  value_text TEXT NOT NULL,
  value_numeric NUMERIC(7,2),
  resolved_mood TEXT NOT NULL DEFAULT '',
  recorded_on DATE NOT NULL,
  source_aggregate_key TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS academic_result_evidence (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('kundelik', 'dnevnikru', 'edupage')),
  result_id UUID REFERENCES academic_results(id) ON DELETE CASCADE,
  aggregate_id UUID REFERENCES academic_aggregates(id) ON DELETE CASCADE,
  source_endpoint TEXT NOT NULL DEFAULT '',
  provider_work_id TEXT NOT NULL DEFAULT '',
  provider_mark_id TEXT NOT NULL DEFAULT '',
  provider_payload_path TEXT NOT NULL DEFAULT '',
  source_mood_raw TEXT NOT NULL DEFAULT '',
  fingerprint_sha256 TEXT NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE lessons
  ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'kundelik';

ALTER TABLE lessons
  ADD COLUMN IF NOT EXISTS provider_lesson_id TEXT NOT NULL DEFAULT '';

ALTER TABLE lessons
  ADD COLUMN IF NOT EXISTS provider_subject_id TEXT NOT NULL DEFAULT '';

ALTER TABLE ingest_batches
  ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'kundelik';

ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'kundelik';

ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS provider_event_key TEXT NOT NULL DEFAULT '';

ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS raw_code TEXT NOT NULL DEFAULT '';

ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS normalized_status TEXT NOT NULL DEFAULT 'present';

ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS recorded_on DATE;

UPDATE attendance_events
SET provider_event_key = COALESCE(NULLIF(source_event_key, ''), provider_event_key)
WHERE provider_event_key = '';

UPDATE attendance_events
SET raw_code = COALESCE(NULLIF(attendance_code, ''), raw_code)
WHERE raw_code = '';

UPDATE attendance_events
SET normalized_status = CASE
  WHEN attendance_code = 'absent' THEN 'absent'
  WHEN attendance_code = 'late' THEN 'late'
  WHEN attendance_code = 'excused' THEN 'excused'
  ELSE 'present'
END
WHERE normalized_status = '' OR normalized_status IS NULL;

UPDATE attendance_events
SET recorded_on = event_date
WHERE recorded_on IS NULL;

ALTER TABLE attendance_events
  ALTER COLUMN recorded_on SET NOT NULL;
