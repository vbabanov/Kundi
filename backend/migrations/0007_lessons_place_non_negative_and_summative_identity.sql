ALTER TABLE lessons
  ADD COLUMN IF NOT EXISTS lesson_place TEXT NOT NULL DEFAULT '';

DO $$
DECLARE
  lesson_number_check_name TEXT;
BEGIN
  SELECT c.conname
  INTO lesson_number_check_name
  FROM pg_constraint c
  WHERE c.conrelid = 'lessons'::regclass
    AND pg_get_constraintdef(c.oid) ILIKE '%lesson_number > 0%';

  IF lesson_number_check_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE lessons DROP CONSTRAINT %I', lesson_number_check_name);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.conrelid = 'lessons'::regclass
      AND pg_get_constraintdef(c.oid) ILIKE '%lesson_number >= 0%'
  ) THEN
    ALTER TABLE lessons
      ADD CONSTRAINT chk_lessons_lesson_number_non_negative
      CHECK (lesson_number >= 0);
  END IF;
END $$;

DROP INDEX IF EXISTS uq_academic_results_summative_fingerprint;

CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_results_summative_fingerprint
ON academic_results(
  student_id,
  provider,
  result_kind,
  provider_subject_id,
  provider_work_id,
  COALESCE(term_no, -1),
  value_text,
  recorded_on
)
WHERE result_kind IN ('sor', 'soch')
  AND provider_mark_id = ''
  AND source_result_key = '';
