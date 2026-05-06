import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/app_database.dart';
import 'package:kundi_mobile/core/db/canonical_cache_store.dart';
import 'package:kundi_mobile/features/lessons/data/lessons_repository_impl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.setTestDbNameOverride('kundi_mobile_lessons_v2_test.db');
  });

  tearDownAll(() {
    AppDatabase.setTestDbNameOverride(null);
  });

  Future<void> clearTables(Database db) async {
    await db.delete('canonical_read_mode_metadata');
    await db.delete('canonical_lessons_cache_v2');
    await db.delete('canonical_attendance_cache_v2');
    await db.delete('canonical_results_cache_v2');
  }

  test('primary provider linkage wins over weaker fallback', () async {
    final db = await AppDatabase.open();
    await clearTables(db);
    final store = CanonicalCacheStore();
    final repo = LessonsRepositoryImpl(store);
    const studentId = 's1';
    const provider = 'kundelik';
    const window = 'kundelik:2025-09-01:2026-04-05';
    const snapshot = '2026-04-05T10:00:00Z';
    const scopedWindow = '$studentId:$provider:$window';

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: window,
      snapshotAt: snapshot,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-lessons-1',
    );

    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'canonical_lessons_cache_v2',
      {
        'lesson_id': '$studentId:$provider:lesson-1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'provider_lesson_id': 'work-linked',
        'provider_subject_id': 'sub-1',
        'lesson_date': '2026-03-10',
        'lesson_number': 1,
        'subject_name': 'Algebra',
        'start_time': '',
        'end_time': '',
        'theme': 'Quadratic',
        'homework_text': 'p.10',
        'homework_status': 'assigned',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Correct primary match via provider_work_id.
    await db.insert(
      'canonical_results_cache_v2',
      {
        'result_id': '$studentId:$provider:r1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'result_kind': 'regular',
        'provider_work_id': 'work-linked',
        'provider_mark_id': 'm1',
        'provider_subject_id': 'sub-1',
        'subject_name': 'Algebra',
        'value_text': '9',
        'resolved_mood': 'good',
        'source_endpoint': 'diary',
        'source_mood_raw': 'good',
        'recorded_on': '2026-03-10',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Same date+subject fallback candidate should not override primary.
    await db.insert(
      'canonical_results_cache_v2',
      {
        'result_id': '$studentId:$provider:r2',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'result_kind': 'regular',
        'provider_work_id': '',
        'provider_mark_id': 'm2',
        'provider_subject_id': 'sub-1',
        'subject_name': 'Algebra',
        'value_text': '5',
        'resolved_mood': 'bad',
        'source_endpoint': 'period',
        'source_mood_raw': 'bad',
        'recorded_on': '2026-03-10',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final lessons = await repo.list();
    expect(lessons, hasLength(1));
    expect(lessons.single.gradeValue, '9');
  });

  test('fallback by subject identity/date is used when primary missing',
      () async {
    final db = await AppDatabase.open();
    await clearTables(db);
    final store = CanonicalCacheStore();
    final repo = LessonsRepositoryImpl(store);
    const studentId = 's1';
    const provider = 'kundelik';
    const window = 'kundelik:2025-09-01:2026-04-05';
    const snapshot = '2026-04-05T10:00:00Z';
    const scopedWindow = '$studentId:$provider:$window';
    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: window,
      snapshotAt: snapshot,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-lessons-2',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'canonical_lessons_cache_v2',
      {
        'lesson_id': '$studentId:$provider:lesson-2',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'provider_lesson_id': '',
        'provider_subject_id': 'sub-2',
        'lesson_date': '2026-03-12',
        'lesson_number': 3,
        'subject_name': 'Biology',
        'start_time': '',
        'end_time': '',
        'theme': '',
        'homework_text': '',
        'homework_status': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'canonical_results_cache_v2',
      {
        'result_id': '$studentId:$provider:r3',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'result_kind': 'regular',
        'provider_work_id': '',
        'provider_mark_id': 'm3',
        'provider_subject_id': 'sub-2',
        'subject_name': 'Biology',
        'value_text': '8',
        'resolved_mood': 'good',
        'source_endpoint': 'diary',
        'source_mood_raw': 'good',
        'recorded_on': '2026-03-12',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final lessons = await repo.list();
    expect(lessons, hasLength(1));
    expect(lessons.single.gradeValue, '8');
  });

  test('v2 lessons keep lesson_number=0, place and display time fields',
      () async {
    final db = await AppDatabase.open();
    await clearTables(db);
    final store = CanonicalCacheStore();
    final repo = LessonsRepositoryImpl(store);
    const studentId = 's1';
    const provider = 'kundelik';
    const window = 'kundelik:2025-09-01:2026-04-05';
    const snapshot = '2026-04-05T10:00:00Z';
    const scopedWindow = '$studentId:$provider:$window';
    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: window,
      snapshotAt: snapshot,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-lessons-3',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'canonical_lessons_cache_v2',
      {
        'lesson_id': '$studentId:$provider:lesson-3',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'provider_lesson_id': 'proof-lesson-zero',
        'provider_subject_id': 'sub-3',
        'lesson_date': '2026-04-11',
        'lesson_number': 0,
        'subject_name': 'Physics',
        'lesson_place': '312',
        'start_time': '17:30',
        'end_time': '18:15',
        'theme': 'Контрольная работа',
        'homework_text': 'Подготовиться к СОЧ',
        'homework_status': 'active',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final lessons = await repo.list();
    expect(lessons, hasLength(1));
    expect(lessons.single.lessonNumber, 0);
    expect(lessons.single.lessonPlace, '312');
    expect(lessons.single.startTime, '17:30');
    expect(lessons.single.endTime, '18:15');
  });
}
