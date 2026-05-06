CREATE INDEX IF NOT EXISTS idx_students_created_at ON students(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_student_profiles_school_class ON student_profiles(school_id, classroom_id);
CREATE INDEX IF NOT EXISTS idx_guardians_student_id ON guardians(student_id);
CREATE INDEX IF NOT EXISTS idx_guardian_contacts_guardian_id ON guardian_contacts(guardian_id);

CREATE INDEX IF NOT EXISTS idx_diary_accounts_student_source ON diary_accounts(student_id, source);
CREATE INDEX IF NOT EXISTS idx_diary_source_ids_account ON diary_source_ids(diary_account_id);
CREATE INDEX IF NOT EXISTS idx_ingest_batches_student_time ON ingest_batches(student_id, ingested_at DESC);
CREATE INDEX IF NOT EXISTS idx_ingest_batches_status_time ON ingest_batches(status, ingested_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_snapshots_student_window ON sync_snapshots(student_id, window_from, window_to);

CREATE INDEX IF NOT EXISTS idx_lessons_student_date ON lessons(student_id, lesson_date, lesson_number);
CREATE INDEX IF NOT EXISTS idx_lessons_classroom_date ON lessons(classroom_id, lesson_date);
CREATE INDEX IF NOT EXISTS idx_lesson_topics_lesson ON lesson_topics(lesson_id, topic_index);
CREATE UNIQUE INDEX IF NOT EXISTS ux_homeworks_student_source_key ON homeworks(student_id, source_homework_key) WHERE source_homework_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_homework_completions_student_status ON homework_completions(student_id, status);
CREATE INDEX IF NOT EXISTS idx_homework_photos_completion ON homework_photos(homework_completion_id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_grades_student_source_key ON grades(student_id, source_grade_key) WHERE source_grade_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_grades_student_lesson ON grades(student_id, lesson_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_summative_grades_source_key ON summative_grades(student_id, source_key) WHERE source_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_summative_grades_student_term ON summative_grades(student_id, term_no);
CREATE INDEX IF NOT EXISTS idx_term_grades_student ON term_grades(student_id);
CREATE INDEX IF NOT EXISTS idx_year_grades_student ON year_grades(student_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_attendance_source_event ON attendance_events(student_id, source_event_key) WHERE source_event_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_attendance_student_date ON attendance_events(student_id, event_date);

CREATE INDEX IF NOT EXISTS idx_daily_stats_student_date ON daily_stats(student_id, stats_date DESC);
CREATE INDEX IF NOT EXISTS idx_weekly_stats_student_week ON weekly_stats(student_id, week_start DESC);
CREATE INDEX IF NOT EXISTS idx_risk_flags_student_status ON risk_flags(student_id, status, detected_at DESC);

CREATE INDEX IF NOT EXISTS idx_assistant_sessions_student_start ON assistant_sessions(student_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_assistant_messages_session_time ON assistant_messages(session_id, created_at);
CREATE INDEX IF NOT EXISTS idx_persona_profiles_student ON persona_profiles(student_id);
CREATE INDEX IF NOT EXISTS idx_avatar_cues_message ON avatar_cues(message_id, emitted_at);

CREATE INDEX IF NOT EXISTS idx_whatsapp_dispatches_student_status ON whatsapp_dispatches(student_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_queue_pickup ON jobs(status, available_at, priority, created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_lease_until ON jobs(lease_until) WHERE status = 'leased';
CREATE INDEX IF NOT EXISTS idx_job_attempts_job_id ON job_attempts(job_id, attempt_no);

CREATE INDEX IF NOT EXISTS idx_refresh_sessions_student ON auth_refresh_sessions(student_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_idempotency_expiry ON api_idempotency_keys(expires_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor_student ON audit_log(actor_student_id, created_at DESC);
