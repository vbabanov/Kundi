-- Enforce relation-local assistant constraints and session/message ownership.
-- This migration is forward-only and intentionally does not repair invalid rows.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_assistant_sessions_grade_level'
      AND conrelid = 'assistant_sessions'::regclass
  ) THEN
    ALTER TABLE assistant_sessions
      ADD CONSTRAINT chk_assistant_sessions_grade_level
      CHECK (grade_level BETWEEN 1 AND 12);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_assistant_sessions_locale_length'
      AND conrelid = 'assistant_sessions'::regclass
  ) THEN
    ALTER TABLE assistant_sessions
      ADD CONSTRAINT chk_assistant_sessions_locale_length
      CHECK (length(locale) BETWEEN 2 AND 16);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_assistant_sessions_title_length'
      AND conrelid = 'assistant_sessions'::regclass
  ) THEN
    ALTER TABLE assistant_sessions
      ADD CONSTRAINT chk_assistant_sessions_title_length
      CHECK (length(title) <= 120);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_assistant_messages_content_length'
      AND conrelid = 'assistant_messages'::regclass
  ) THEN
    ALTER TABLE assistant_messages
      ADD CONSTRAINT chk_assistant_messages_content_length
      CHECK (length(content) BETWEEN 1 AND 12000) NOT VALID;
  END IF;
END $$;

ALTER TABLE assistant_messages
  VALIDATE CONSTRAINT chk_assistant_messages_content_length;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'uq_assistant_sessions_id_student_id'
      AND conrelid = 'assistant_sessions'::regclass
  ) THEN
    ALTER TABLE assistant_sessions
      ADD CONSTRAINT uq_assistant_sessions_id_student_id
      UNIQUE (id, student_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_assistant_messages_session_owner'
      AND conrelid = 'assistant_messages'::regclass
  ) THEN
    ALTER TABLE assistant_messages
      ADD CONSTRAINT fk_assistant_messages_session_owner
      FOREIGN KEY (session_id, student_id)
      REFERENCES assistant_sessions(id, student_id)
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END $$;

ALTER TABLE assistant_messages
  VALIDATE CONSTRAINT fk_assistant_messages_session_owner;
