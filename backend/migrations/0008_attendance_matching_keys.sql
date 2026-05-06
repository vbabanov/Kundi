ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS provider_subject_id TEXT NOT NULL DEFAULT '';

ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS subject_name TEXT NOT NULL DEFAULT '';

ALTER TABLE attendance_events
  ADD COLUMN IF NOT EXISTS lesson_number INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_attendance_student_provider_day_subject_lesson
ON attendance_events(student_id, provider, recorded_on, provider_subject_id, lesson_number);
