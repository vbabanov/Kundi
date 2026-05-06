import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/app_database.dart';
import 'package:kundi_mobile/core/db/canonical_cache_store.dart';
import 'package:kundi_mobile/features/summary/data/summary_repository_impl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.setTestDbNameOverride('kundi_mobile_summary_v2_test.db');
  });

  tearDownAll(() {
    AppDatabase.setTestDbNameOverride(null);
  });

  Future<void> clearTables(Database db) async {
    await db.delete('canonical_read_mode_metadata');
    await db.delete('canonical_lessons_cache_v2');
    await db.delete('canonical_attendance_cache_v2');
    await db.delete('canonical_results_cache_v2');
    await db.delete('canonical_aggregates_cache_v2');
    await db.delete('canonical_overview_highlights_cache_v2');
  }

  test('summary uses single count semantics and filters upcoming to future ASC',
      () async {
    final db = await AppDatabase.open();
    await clearTables(db);
    final store = CanonicalCacheStore();
    final repo = SummaryRepositoryImpl(store);
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
      traceId: 'trace-summary-1',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final today = DateTime.now().toUtc();
    final tomorrow = DateTime.utc(today.year, today.month, today.day + 1);
    final afterTomorrow = DateTime.utc(today.year, today.month, today.day + 2);
    String ymd(DateTime dt) =>
        '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    await db.insert(
      'canonical_lessons_cache_v2',
      {
        'lesson_id': '$studentId:$provider:l1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'provider_lesson_id': 'lr1',
        'provider_subject_id': 'sub-1',
        'lesson_date': ymd(tomorrow),
        'lesson_number': 1,
        'subject_name': 'Math',
        'start_time': '',
        'end_time': '',
        'theme': 'Theme 1',
        'homework_text': 'Task 1',
        'homework_status': 'assigned',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'canonical_lessons_cache_v2',
      {
        'lesson_id': '$studentId:$provider:l2',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'provider_lesson_id': 'lr2',
        'provider_subject_id': 'sub-2',
        'lesson_date': ymd(afterTomorrow),
        'lesson_number': 2,
        'subject_name': 'Biology',
        'start_time': '',
        'end_time': '',
        'theme': 'Theme 2',
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
        'result_id': '$studentId:$provider:r1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'result_kind': 'regular',
        'provider_work_id': '',
        'provider_mark_id': 'm1',
        'provider_subject_id': 'sub-1',
        'subject_name': 'Math',
        'value_text': '9',
        'resolved_mood': 'good',
        'source_endpoint': 'diary',
        'source_mood_raw': 'good',
        'recorded_on': ymd(today),
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'canonical_attendance_cache_v2',
      {
        'attendance_id': '$studentId:$provider:a1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'provider_event_key': 'ev1',
        'provider_lesson_ref': 'lr1',
        'recorded_on': ymd(today),
        'raw_code': 'N',
        'normalized_status': 'absent',
        'reason': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'canonical_aggregates_cache_v2',
      {
        'aggregate_id': '$studentId:$provider:ag1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'result_kind': 'term',
        'provider_subject_id': 'sub-1',
        'subject_name': 'Math',
        'value_text': '4',
        'resolved_mood': 'good',
        'recorded_on': ymd(today),
        'term_no': 3,
        'year_label': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert(
      'canonical_overview_highlights_cache_v2',
      {
        'highlight_key':
            '$studentId:$provider:recent_results:$scopedWindow:$snapshot',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'highlight_kind': 'recent_results',
        'payload_json': jsonEncode([
          {
            'result_id': 'r1',
            'result_kind': 'regular',
            'subject_name': 'Math',
            'value_text': '9',
            'recorded_on': ymd(today),
            'resolved_mood': 'good',
          }
        ]),
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'canonical_overview_highlights_cache_v2',
      {
        'highlight_key':
            '$studentId:$provider:upcoming_lessons:$scopedWindow:$snapshot',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'p1',
        'highlight_kind': 'upcoming_lessons',
        'payload_json': jsonEncode([
          {
            'lesson_id': 'past',
            'lesson_date': ymd(today.subtract(const Duration(days: 1))),
            'lesson_number': 1,
            'subject_name': 'Past',
            'theme': 'Past Theme',
            'homework_text': '',
          },
          {
            'lesson_id': 'future2',
            'lesson_date': ymd(afterTomorrow),
            'lesson_number': 2,
            'subject_name': 'Biology',
            'theme': 'Theme 2',
            'homework_text': '',
          },
          {
            'lesson_id': 'future1',
            'lesson_date': ymd(tomorrow),
            'lesson_number': 1,
            'subject_name': 'Math',
            'theme': 'Theme 1',
            'homework_text': 'Task',
          }
        ]),
        'window_key': scopedWindow,
        'snapshot_at': snapshot,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final summary = await repo.get();
    expect(summary.available, isTrue);
    expect(summary.lessonsCount, 2);
    expect(summary.homeworkCount, 1);
    expect(summary.resultsCount, 1);
    expect(summary.attendanceCount, 1);
    expect(summary.aggregatesCount, 1);
    expect(summary.recentResults, hasLength(1));
    expect(summary.upcomingLessons, hasLength(2));
    expect(summary.upcomingLessons.first.lessonId, 'future1');
    expect(summary.upcomingLessons.last.lessonId, 'future2');
  });
}
