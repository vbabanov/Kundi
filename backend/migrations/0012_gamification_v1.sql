-- Kundi Gamification / Achievements v1.
-- Additive tables only: the previous runtime can safely ignore this schema.

CREATE TABLE IF NOT EXISTS gamification_activity_days (
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  activity_date DATE NOT NULL,
  timezone TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (student_id, activity_date),
  CHECK (length(timezone) BETWEEN 1 AND 64),
  CHECK (last_seen_at >= first_seen_at)
);

CREATE TABLE IF NOT EXISTS gamification_facts (
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  fact_type TEXT NOT NULL CHECK (fact_type IN ('grade_five', 'learning_question', 'attempt_check')),
  source_key TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  local_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (student_id, fact_type, source_key),
  CHECK (length(source_key) BETWEEN 1 AND 128)
);

CREATE TABLE IF NOT EXISTS gamification_achievement_unlocks (
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  achievement_code TEXT NOT NULL,
  catalog_version INTEGER NOT NULL,
  unlocked_at TIMESTAMPTZ NOT NULL,
  seen_at TIMESTAMPTZ,
  PRIMARY KEY (student_id, achievement_code),
  CHECK (length(achievement_code) BETWEEN 1 AND 64),
  CHECK (catalog_version > 0),
  CHECK (seen_at IS NULL OR seen_at >= unlocked_at)
);

CREATE TABLE IF NOT EXISTS gamification_profiles (
  student_id UUID PRIMARY KEY REFERENCES students(id) ON DELETE CASCADE,
  catalog_version INTEGER NOT NULL,
  points INTEGER NOT NULL DEFAULT 0 CHECK (points >= 0),
  level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
  current_streak INTEGER NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
  longest_streak INTEGER NOT NULL DEFAULT 0 CHECK (longest_streak >= 0),
  last_active_date DATE,
  reconciled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (catalog_version > 0),
  CHECK (longest_streak >= current_streak)
);

CREATE INDEX IF NOT EXISTS idx_gamification_activity_student_date
ON gamification_activity_days(student_id, activity_date DESC);

CREATE INDEX IF NOT EXISTS idx_gamification_facts_student_type_date
ON gamification_facts(student_id, fact_type, local_date, occurred_at);

CREATE INDEX IF NOT EXISTS idx_gamification_unlocks_student_unseen
ON gamification_achievement_unlocks(student_id, unlocked_at, achievement_code)
WHERE seen_at IS NULL;
