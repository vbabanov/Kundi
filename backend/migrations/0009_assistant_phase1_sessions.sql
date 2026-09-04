-- Phase 1 text assistant session/history contract.
-- The repository migrator is forward-only; rollback is intentionally not embedded.

ALTER TABLE assistant_sessions
  ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL DEFAULT 'ru-KZ',
  ADD COLUMN IF NOT EXISTS grade_level SMALLINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_message_at TIMESTAMPTZ;

UPDATE assistant_sessions
SET created_at = COALESCE(created_at, started_at),
    updated_at = COALESCE(updated_at, started_at),
    last_message_at = COALESCE(last_message_at, started_at)
WHERE created_at IS NULL OR updated_at IS NULL OR last_message_at IS NULL;

UPDATE assistant_sessions s
SET locale = sp.locale,
    grade_level = sp.grade_level
FROM student_profiles sp
WHERE sp.student_id = s.student_id;

ALTER TABLE assistant_sessions
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN created_at SET DEFAULT NOW(),
  ALTER COLUMN updated_at SET NOT NULL,
  ALTER COLUMN updated_at SET DEFAULT NOW(),
  ALTER COLUMN last_message_at SET NOT NULL,
  ALTER COLUMN last_message_at SET DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_assistant_sessions_grade_level'
  ) THEN
    ALTER TABLE assistant_sessions
      ADD CONSTRAINT chk_assistant_sessions_grade_level
      CHECK (grade_level BETWEEN 1 AND 12);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_assistant_sessions_locale_length'
  ) THEN
    ALTER TABLE assistant_sessions
      ADD CONSTRAINT chk_assistant_sessions_locale_length
      CHECK (length(locale) BETWEEN 2 AND 16);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_assistant_sessions_title_length'
  ) THEN
    ALTER TABLE assistant_sessions
      ADD CONSTRAINT chk_assistant_sessions_title_length
      CHECK (length(title) <= 120);
  END IF;
END $$;

ALTER TABLE assistant_messages
  ADD COLUMN IF NOT EXISTS client_message_id UUID,
  ADD COLUMN IF NOT EXISTS content TEXT,
  ADD COLUMN IF NOT EXISTS input_mode TEXT NOT NULL DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS model TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS response_mode TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS tutoring_policy_result JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS safety_category TEXT;

UPDATE assistant_messages
SET content = text_content
WHERE content IS NULL;

ALTER TABLE assistant_messages
  ALTER COLUMN content SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_assistant_messages_content_length'
  ) THEN
    ALTER TABLE assistant_messages
      ADD CONSTRAINT chk_assistant_messages_content_length
      CHECK (length(content) BETWEEN 1 AND 12000) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_assistant_messages_input_mode'
  ) THEN
    ALTER TABLE assistant_messages
      ADD CONSTRAINT chk_assistant_messages_input_mode
      CHECK (input_mode = 'text');
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_assistant_messages_session_client_message_id
ON assistant_messages(session_id, client_message_id)
WHERE client_message_id IS NOT NULL AND role = 'user';

CREATE INDEX IF NOT EXISTS idx_assistant_sessions_student_last_message
ON assistant_sessions(student_id, last_message_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_assistant_messages_session_created
ON assistant_messages(session_id, created_at DESC, id DESC);
