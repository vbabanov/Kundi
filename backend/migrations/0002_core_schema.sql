CREATE TABLE IF NOT EXISTS schools (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_school_code TEXT,
  country TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (name, city)
);

CREATE TABLE IF NOT EXISTS classrooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  grade_level SMALLINT NOT NULL CHECK (grade_level BETWEEN 1 AND 12),
  label TEXT NOT NULL,
  shift SMALLINT NOT NULL CHECK (shift IN (1, 2)),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, grade_level, label, shift)
);

CREATE TABLE IF NOT EXISTS teachers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id UUID REFERENCES schools(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL,
  subject TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_student_ref TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (external_student_ref)
);

CREATE TABLE IF NOT EXISTS student_profiles (
  student_id UUID PRIMARY KEY REFERENCES students(id) ON DELETE CASCADE,
  school_id UUID REFERENCES schools(id) ON DELETE SET NULL,
  classroom_id UUID REFERENCES classrooms(id) ON DELETE SET NULL,
  first_name TEXT NOT NULL DEFAULT '',
  last_name TEXT NOT NULL DEFAULT '',
  grade_level SMALLINT NOT NULL DEFAULT 1 CHECK (grade_level BETWEEN 1 AND 12),
  class_label TEXT NOT NULL DEFAULT '',
  locale TEXT NOT NULL DEFAULT 'ru-KZ',
  timezone TEXT NOT NULL DEFAULT 'Asia/Qyzylorda',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS guardians (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  relationship_type TEXT NOT NULL,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS guardian_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  guardian_id UUID NOT NULL REFERENCES guardians(id) ON DELETE CASCADE,
  contact_type TEXT NOT NULL CHECK (contact_type IN ('phone', 'email', 'whatsapp')),
  contact_value CITEXT NOT NULL,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (guardian_id, contact_type, contact_value)
);

CREATE TABLE IF NOT EXISTS diary_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('kundelik', 'dnevnikru', 'edupage')),
  login_fingerprint TEXT NOT NULL,
  source_login_ciphertext BYTEA NOT NULL,
  source_password_ciphertext BYTEA NOT NULL,
  session_secret_ciphertext BYTEA,
  last_authenticated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, source),
  UNIQUE (source, login_fingerprint)
);

CREATE TABLE IF NOT EXISTS diary_source_ids (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diary_account_id UUID NOT NULL REFERENCES diary_accounts(id) ON DELETE CASCADE,
  id_key TEXT NOT NULL,
  id_value TEXT NOT NULL,
  discovered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (diary_account_id, id_key, id_value)
);

CREATE TABLE IF NOT EXISTS ingest_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  diary_account_id UUID REFERENCES diary_accounts(id) ON DELETE SET NULL,
  idempotency_key TEXT NOT NULL,
  bundle_checksum TEXT NOT NULL,
  bundle_version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL CHECK (status IN ('accepted', 'merged', 'rejected')),
  error_reason TEXT,
  request_payload JSONB NOT NULL,
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS sync_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  diary_account_id UUID REFERENCES diary_accounts(id) ON DELETE SET NULL,
  window_from DATE NOT NULL,
  window_to DATE NOT NULL,
  snapshot_hash TEXT NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, diary_account_id, window_from, window_to, snapshot_hash)
);

CREATE TABLE IF NOT EXISTS lessons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  source_lesson_key TEXT NOT NULL,
  lesson_date DATE NOT NULL,
  lesson_number SMALLINT NOT NULL CHECK (lesson_number > 0),
  subject_name TEXT NOT NULL,
  teacher_id UUID REFERENCES teachers(id) ON DELETE SET NULL,
  classroom_id UUID REFERENCES classrooms(id) ON DELETE SET NULL,
  start_time TIME,
  end_time TIME,
  source_updated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, source_lesson_key)
);

CREATE TABLE IF NOT EXISTS lesson_topics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id UUID NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  topic_index SMALLINT NOT NULL DEFAULT 1,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (lesson_id, topic_index)
);

CREATE TABLE IF NOT EXISTS homeworks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  lesson_id UUID NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  source_homework_key TEXT,
  description TEXT NOT NULL DEFAULT '',
  due_at TIMESTAMPTZ,
  requires_photo BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (lesson_id)
);

CREATE TABLE IF NOT EXISTS homework_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  homework_id UUID NOT NULL REFERENCES homeworks(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'submitted', 'reviewed')),
  completed_at TIMESTAMPTZ,
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (homework_id, student_id)
);

CREATE TABLE IF NOT EXISTS homework_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  homework_completion_id UUID NOT NULL REFERENCES homework_completions(id) ON DELETE CASCADE,
  storage_key TEXT NOT NULL,
  content_type TEXT NOT NULL DEFAULT 'image/jpeg',
  file_size_bytes BIGINT NOT NULL DEFAULT 0,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (homework_completion_id, storage_key)
);

CREATE TABLE IF NOT EXISTS grades (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  lesson_id UUID REFERENCES lessons(id) ON DELETE CASCADE,
  source_grade_key TEXT,
  grade_type TEXT NOT NULL DEFAULT 'regular' CHECK (grade_type IN ('regular', 'absence', 'behavior')),
  grade_value TEXT NOT NULL,
  grade_numeric NUMERIC(5, 2),
  grade_mood TEXT,
  is_absent BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS summative_grades (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  source_key TEXT,
  subject_name TEXT NOT NULL,
  term_no SMALLINT NOT NULL CHECK (term_no BETWEEN 1 AND 4),
  summative_kind TEXT NOT NULL CHECK (summative_kind IN ('sor', 'soch')),
  score TEXT NOT NULL,
  recorded_on DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS term_grades (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  subject_name TEXT NOT NULL,
  term_no SMALLINT NOT NULL CHECK (term_no BETWEEN 1 AND 4),
  term_grade TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, subject_name, term_no)
);

CREATE TABLE IF NOT EXISTS year_grades (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  subject_name TEXT NOT NULL,
  year_label TEXT NOT NULL DEFAULT 'current',
  year_grade TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, subject_name, year_label)
);

CREATE TABLE IF NOT EXISTS attendance_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  lesson_id UUID REFERENCES lessons(id) ON DELETE SET NULL,
  source_event_key TEXT,
  event_date DATE NOT NULL,
  attendance_code TEXT NOT NULL CHECK (attendance_code IN ('present', 'absent', 'late', 'excused')),
  reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS daily_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  stats_date DATE NOT NULL,
  lessons_total INTEGER NOT NULL DEFAULT 0,
  homework_total INTEGER NOT NULL DEFAULT 0,
  homework_completed INTEGER NOT NULL DEFAULT 0,
  absences_total INTEGER NOT NULL DEFAULT 0,
  avg_grade NUMERIC(5, 2),
  risk_score NUMERIC(5, 2) NOT NULL DEFAULT 0,
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, stats_date)
);

CREATE TABLE IF NOT EXISTS weekly_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  week_end DATE NOT NULL,
  lessons_total INTEGER NOT NULL DEFAULT 0,
  homework_total INTEGER NOT NULL DEFAULT 0,
  homework_completed INTEGER NOT NULL DEFAULT 0,
  absences_total INTEGER NOT NULL DEFAULT 0,
  avg_grade NUMERIC(5, 2),
  risk_score NUMERIC(5, 2) NOT NULL DEFAULT 0,
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, week_start, week_end)
);

CREATE TABLE IF NOT EXISTS risk_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  flag_type TEXT NOT NULL,
  severity SMALLINT NOT NULL CHECK (severity BETWEEN 1 AND 5),
  status TEXT NOT NULL CHECK (status IN ('open', 'resolved', 'ignored')),
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS assistant_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  mode TEXT NOT NULL CHECK (mode IN ('tutor', 'general_chat')),
  session_state JSONB NOT NULL DEFAULT '{}'::jsonb,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS assistant_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES assistant_sessions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('system', 'user', 'assistant', 'tool')),
  text_content TEXT NOT NULL,
  audio_url TEXT,
  visemes JSONB NOT NULL DEFAULT '[]'::jsonb,
  avatar_emotion TEXT NOT NULL DEFAULT 'neutral',
  gesture_tags TEXT[] NOT NULL DEFAULT '{}',
  pedagogy_flags JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS persona_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL UNIQUE REFERENCES students(id) ON DELETE CASCADE,
  tone_profile TEXT NOT NULL DEFAULT 'default',
  style_profile TEXT NOT NULL DEFAULT 'default',
  grade_adaptation JSONB NOT NULL DEFAULT '{}'::jsonb,
  tts_voice TEXT NOT NULL DEFAULT '',
  locale TEXT NOT NULL DEFAULT 'ru-KZ',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS avatar_cues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES assistant_sessions(id) ON DELETE SET NULL,
  message_id UUID REFERENCES assistant_messages(id) ON DELETE SET NULL,
  cue_type TEXT NOT NULL,
  cue_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  emitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS whatsapp_dispatches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  guardian_id UUID REFERENCES guardians(id) ON DELETE SET NULL,
  dispatch_type TEXT NOT NULL CHECK (dispatch_type IN ('homework_digest', 'homework_photo', 'weekly_digest', 'manual')),
  channel TEXT NOT NULL DEFAULT 'whatsapp',
  payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'cancelled')),
  idempotency_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  UNIQUE (idempotency_key)
);

CREATE TABLE IF NOT EXISTS jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_type TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  priority SMALLINT NOT NULL DEFAULT 50,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'leased', 'succeeded', 'failed', 'dead_letter')),
  available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  lease_owner TEXT,
  lease_until TIMESTAMPTZ,
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  UNIQUE (job_type, idempotency_key)
);

CREATE TABLE IF NOT EXISTS job_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  attempt_no INTEGER NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  success BOOLEAN NOT NULL DEFAULT FALSE,
  error_message TEXT,
  worker_name TEXT NOT NULL,
  UNIQUE (job_id, attempt_no)
);

CREATE TABLE IF NOT EXISTS auth_refresh_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  refresh_token_hash TEXT NOT NULL UNIQUE,
  user_agent TEXT NOT NULL DEFAULT '',
  ip_address INET,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS api_idempotency_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scope TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  response_status INTEGER,
  response_body JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  UNIQUE (scope, idempotency_key)
);

CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_student_id UUID REFERENCES students(id) ON DELETE SET NULL,
  actor_guardian_id UUID REFERENCES guardians(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  request_id TEXT,
  ip_address INET,
  user_agent TEXT NOT NULL DEFAULT '',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
