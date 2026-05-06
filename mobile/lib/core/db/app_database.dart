import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static const _dbName = 'kundi_mobile.db';
  static const _dbVersion = 7;
  static String? _testDbNameOverride;

  static void setTestDbNameOverride(String? dbName) {
    _testDbNameOverride = dbName;
  }

  static Future<Database> open() async {
    final fileName = _testDbNameOverride ?? _dbName;
    final path = p.join(await getDatabasesPath(), fileName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV2Schema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2Schema(db);
          await _migrateV1QueueToV2(db);
        }
        if (oldVersion < 3) {
          await _createV3TypedReadSchema(db);
        }
        if (oldVersion < 4) {
          await _migrateV4TypedReadScope(db);
        }
        if (oldVersion < 5) {
          await _migrateV5TypedReadRefreshSchema(db);
        }
        if (oldVersion < 6) {
          await _migrateV6LessonsPlaceSchema(db);
        }
        if (oldVersion < 7) {
          await _migrateV7AttendanceMatchingKeysSchema(db);
        }
      },
    );
  }

  static Future<void> _createV2Schema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_profile_cache (
        student_id TEXT PRIMARY KEY,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        grade_level INTEGER NOT NULL,
        class_label TEXT NOT NULL,
        school_name TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_lessons_cache (
        lesson_id TEXT PRIMARY KEY,
        lesson_date TEXT NOT NULL,
        lesson_number INTEGER NOT NULL,
        subject_name TEXT NOT NULL,
        topic TEXT NOT NULL,
        homework_text TEXT NOT NULL,
        requires_photo INTEGER NOT NULL DEFAULT 0,
        grade_value TEXT NOT NULL,
        grade_mood TEXT NOT NULL,
        attendance_code TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_homework_cache (
        homework_id TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        requires_photo INTEGER NOT NULL DEFAULT 0,
        lesson_date TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_grades_cache (
        grade_id TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        mood TEXT NOT NULL,
        grade_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_attendance_cache (
        attendance_id TEXT PRIMARY KEY,
        event_date TEXT NOT NULL,
        code TEXT NOT NULL,
        reason TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_sync_queue (
        request_id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT NOT NULL,
        last_error TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_sync_metadata (
        meta_key TEXT PRIMARY KEY,
        meta_value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_lessons_cache_date
      ON canonical_lessons_cache(lesson_date, lesson_number)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_homework_cache_date
      ON canonical_homework_cache(lesson_date DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_grades_cache_created_at
      ON canonical_grades_cache(created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_status_next_retry
      ON canonical_sync_queue(status, next_retry_at)
    ''');
    await _createV3TypedReadSchema(db);
  }

  static Future<void> _createV3TypedReadSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_provider_identity_cache_v2 (
        student_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        provider_account_ref TEXT NOT NULL DEFAULT '',
        provider_person_id TEXT NOT NULL DEFAULT '',
        provider_school_id TEXT NOT NULL DEFAULT '',
        provider_group_id TEXT NOT NULL DEFAULT '',
        student_full_name TEXT NOT NULL DEFAULT '',
        school_name TEXT NOT NULL DEFAULT '',
        class_label TEXT NOT NULL DEFAULT '',
        class_teacher_full_name TEXT NOT NULL DEFAULT '',
        window_key TEXT NOT NULL,
        snapshot_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(student_id, provider, window_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_local_app_profile_cache_v2 (
        profile_scope TEXT PRIMARY KEY,
        student_id TEXT NOT NULL DEFAULT '',
        provider TEXT NOT NULL DEFAULT '',
        provider_person_id TEXT NOT NULL DEFAULT '',
        shift INTEGER,
        parent_phone_1 TEXT NOT NULL DEFAULT '',
        parent_phone_2 TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_results_cache_v2 (
        result_id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        provider_person_id TEXT NOT NULL DEFAULT '',
        result_kind TEXT NOT NULL,
        provider_work_id TEXT NOT NULL DEFAULT '',
        provider_mark_id TEXT NOT NULL DEFAULT '',
        provider_subject_id TEXT NOT NULL DEFAULT '',
        subject_name TEXT NOT NULL DEFAULT '',
        value_text TEXT NOT NULL DEFAULT '',
        resolved_mood TEXT NOT NULL DEFAULT '',
        source_endpoint TEXT NOT NULL DEFAULT '',
        source_mood_raw TEXT NOT NULL DEFAULT '',
        recorded_on TEXT NOT NULL,
        window_key TEXT NOT NULL,
        snapshot_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_aggregates_cache_v2 (
        aggregate_id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        provider_person_id TEXT NOT NULL DEFAULT '',
        result_kind TEXT NOT NULL,
        provider_subject_id TEXT NOT NULL DEFAULT '',
        subject_name TEXT NOT NULL DEFAULT '',
        value_text TEXT NOT NULL DEFAULT '',
        resolved_mood TEXT NOT NULL DEFAULT '',
        recorded_on TEXT NOT NULL,
        term_no INTEGER,
        year_label TEXT NOT NULL DEFAULT '',
        window_key TEXT NOT NULL,
        snapshot_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_overview_highlights_cache_v2 (
        highlight_key TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        provider TEXT NOT NULL DEFAULT '',
        provider_person_id TEXT NOT NULL DEFAULT '',
        highlight_kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        window_key TEXT NOT NULL,
        snapshot_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_read_mode_metadata (
        meta_key TEXT PRIMARY KEY,
        student_id TEXT NOT NULL DEFAULT '',
        provider TEXT NOT NULL DEFAULT '',
        meta_value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_results_cache_v2_window
      ON canonical_results_cache_v2(student_id, provider, window_key, snapshot_at, recorded_on DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_aggregates_cache_v2_window
      ON canonical_aggregates_cache_v2(student_id, provider, window_key, snapshot_at, recorded_on DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_highlights_cache_v2_window
      ON canonical_overview_highlights_cache_v2(student_id, provider, window_key, snapshot_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_read_mode_metadata_scope
      ON canonical_read_mode_metadata(student_id, provider, meta_key)
    ''');
    await _createV5TypedReadRefreshSchema(db);
  }

  static Future<void> _createV5TypedReadRefreshSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_lessons_cache_v2 (
        lesson_id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        provider_person_id TEXT NOT NULL DEFAULT '',
        provider_lesson_id TEXT NOT NULL DEFAULT '',
        provider_subject_id TEXT NOT NULL DEFAULT '',
        lesson_date TEXT NOT NULL,
        lesson_number INTEGER NOT NULL DEFAULT 0,
        subject_name TEXT NOT NULL DEFAULT '',
        lesson_place TEXT NOT NULL DEFAULT '',
        start_time TEXT NOT NULL DEFAULT '',
        end_time TEXT NOT NULL DEFAULT '',
        theme TEXT NOT NULL DEFAULT '',
        homework_text TEXT NOT NULL DEFAULT '',
        homework_status TEXT NOT NULL DEFAULT '',
        window_key TEXT NOT NULL,
        snapshot_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_attendance_cache_v2 (
        attendance_id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        provider_person_id TEXT NOT NULL DEFAULT '',
        provider_event_key TEXT NOT NULL DEFAULT '',
        provider_lesson_ref TEXT NOT NULL DEFAULT '',
        provider_subject_id TEXT NOT NULL DEFAULT '',
        subject_name TEXT NOT NULL DEFAULT '',
        lesson_number INTEGER NOT NULL DEFAULT 0,
        recorded_on TEXT NOT NULL,
        raw_code TEXT NOT NULL DEFAULT '',
        normalized_status TEXT NOT NULL DEFAULT '',
        reason TEXT NOT NULL DEFAULT '',
        window_key TEXT NOT NULL,
        snapshot_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canonical_overview_counts_cache_v2 (
        overview_counts_key TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        provider_person_id TEXT NOT NULL DEFAULT '',
        lessons_in_window INTEGER NOT NULL DEFAULT 0,
        results_in_window INTEGER NOT NULL DEFAULT 0,
        aggregates_in_window INTEGER NOT NULL DEFAULT 0,
        attendance_alerts INTEGER NOT NULL DEFAULT 0,
        window_key TEXT NOT NULL,
        snapshot_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_lessons_cache_v2_scope
      ON canonical_lessons_cache_v2(student_id, provider, provider_person_id, window_key, snapshot_at, lesson_date, lesson_number)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_attendance_cache_v2_scope
      ON canonical_attendance_cache_v2(student_id, provider, provider_person_id, window_key, snapshot_at, recorded_on)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_overview_counts_cache_v2_scope
      ON canonical_overview_counts_cache_v2(student_id, provider, provider_person_id, window_key, snapshot_at)
    ''');
  }

  static Future<void> _migrateV4TypedReadScope(Database db) async {
    await _ensureColumn(
      db,
      'canonical_provider_identity_cache_v2',
      'student_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_local_app_profile_cache_v2',
      'student_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_local_app_profile_cache_v2',
      'provider',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_local_app_profile_cache_v2',
      'provider_person_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_results_cache_v2',
      'student_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_results_cache_v2',
      'provider_person_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_aggregates_cache_v2',
      'student_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_aggregates_cache_v2',
      'provider_person_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_overview_highlights_cache_v2',
      'student_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_overview_highlights_cache_v2',
      'provider',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_overview_highlights_cache_v2',
      'provider_person_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_read_mode_metadata',
      'student_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_read_mode_metadata',
      'provider',
      "TEXT NOT NULL DEFAULT ''",
    );

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_provider_identity_cache_v2_scope
      ON canonical_provider_identity_cache_v2(student_id, provider, window_key, snapshot_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_profile_cache_v2_scope
      ON canonical_local_app_profile_cache_v2(student_id, provider)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_results_cache_v2_scope
      ON canonical_results_cache_v2(student_id, provider, provider_person_id, window_key, snapshot_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_aggregates_cache_v2_scope
      ON canonical_aggregates_cache_v2(student_id, provider, provider_person_id, window_key, snapshot_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_highlights_cache_v2_scope
      ON canonical_overview_highlights_cache_v2(student_id, provider, provider_person_id, window_key, snapshot_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_read_mode_metadata_scope
      ON canonical_read_mode_metadata(student_id, provider, meta_key)
    ''');
  }

  static Future<void> _migrateV5TypedReadRefreshSchema(Database db) async {
    await _createV5TypedReadRefreshSchema(db);
  }

  static Future<void> _migrateV6LessonsPlaceSchema(Database db) async {
    await _ensureColumn(
      db,
      'canonical_lessons_cache_v2',
      'lesson_place',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  static Future<void> _migrateV7AttendanceMatchingKeysSchema(
      Database db) async {
    await _ensureColumn(
      db,
      'canonical_attendance_cache_v2',
      'provider_subject_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_attendance_cache_v2',
      'subject_name',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      'canonical_attendance_cache_v2',
      'lesson_number',
      "INTEGER NOT NULL DEFAULT 0",
    );
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_attendance_cache_v2_match_keys
      ON canonical_attendance_cache_v2(student_id, provider, provider_person_id, window_key, snapshot_at, recorded_on, provider_subject_id, lesson_number)
    ''');
  }

  static Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((row) => row['name'] == column);
    if (exists) {
      return;
    }
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  static Future<void> _migrateV1QueueToV2(Database db) async {
    final exists = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'canonical_sync_queue'
    ''');
    if (exists.isEmpty) {
      return;
    }

    final columns =
        await db.rawQuery('PRAGMA table_info(canonical_sync_queue)');
    final hasStatusColumn = columns.any((column) => column['name'] == 'status');
    if (hasStatusColumn) {
      return;
    }

    await db.execute(
        'ALTER TABLE canonical_sync_queue RENAME TO canonical_sync_queue_legacy_v1');
    await db.execute('''
      CREATE TABLE canonical_sync_queue (
        request_id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT NOT NULL,
        last_error TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      INSERT INTO canonical_sync_queue (
        request_id,
        payload_json,
        status,
        attempts,
        next_retry_at,
        last_error,
        created_at,
        updated_at
      )
      SELECT
        request_id,
        payload_json,
        'pending',
        attempts,
        created_at,
        '',
        created_at,
        created_at
      FROM canonical_sync_queue_legacy_v1
    ''');
    await db.execute('DROP TABLE canonical_sync_queue_legacy_v1');
  }
}
