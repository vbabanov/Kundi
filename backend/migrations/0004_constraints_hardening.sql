DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_sync_snapshots_window_order'
  ) THEN
    ALTER TABLE sync_snapshots
      ADD CONSTRAINT chk_sync_snapshots_window_order
      CHECK (window_to >= window_from);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_weekly_stats_window_order'
  ) THEN
    ALTER TABLE weekly_stats
      ADD CONSTRAINT chk_weekly_stats_window_order
      CHECK (week_end >= week_start);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_jobs_attempts_range'
  ) THEN
    ALTER TABLE jobs
      ADD CONSTRAINT chk_jobs_attempts_range
      CHECK (attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_job_attempts_attempt_no_positive'
  ) THEN
    ALTER TABLE job_attempts
      ADD CONSTRAINT chk_job_attempts_attempt_no_positive
      CHECK (attempt_no > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_ingest_batches_idempotency_key_not_blank'
  ) THEN
    ALTER TABLE ingest_batches
      ADD CONSTRAINT chk_ingest_batches_idempotency_key_not_blank
      CHECK (length(trim(idempotency_key)) > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_api_idempotency_key_not_blank'
  ) THEN
    ALTER TABLE api_idempotency_keys
      ADD CONSTRAINT chk_api_idempotency_key_not_blank
      CHECK (length(trim(idempotency_key)) > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_homework_photos_size_non_negative'
  ) THEN
    ALTER TABLE homework_photos
      ADD CONSTRAINT chk_homework_photos_size_non_negative
      CHECK (file_size_bytes >= 0);
  END IF;
END $$;
