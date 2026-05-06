import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/app_database.dart';
import 'package:kundi_mobile/core/db/canonical_cache_store.dart';
import 'package:kundi_mobile/core/network/v2_read_models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.setTestDbNameOverride('kundi_mobile_v2_refresh_apply.db');
  });

  tearDownAll(() {
    AppDatabase.setTestDbNameOverride(null);
  });

  Future<void> clearTables(Database db) async {
    await db.delete('canonical_provider_identity_cache_v2');
    await db.delete('canonical_local_app_profile_cache_v2');
    await db.delete('canonical_results_cache_v2');
    await db.delete('canonical_aggregates_cache_v2');
    await db.delete('canonical_lessons_cache_v2');
    await db.delete('canonical_attendance_cache_v2');
    await db.delete('canonical_overview_counts_cache_v2');
    await db.delete('canonical_overview_highlights_cache_v2');
    await db.delete('canonical_read_mode_metadata');
    await db.delete('canonical_profile_cache');
    await db.delete('canonical_grades_cache');
  }

  V2ProfileResponse buildProfile({
    required String studentId,
    required String personId,
    required String snapshotAt,
    required String windowKey,
  }) {
    return V2ProfileResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': snapshotAt,
        'window_key': windowKey,
      },
      'provider_identity': {
        'provider': 'kundelik',
        'provider_account_ref': 'acc-$studentId',
        'provider_person_id': personId,
        'provider_school_id': 'school-1',
        'provider_group_id': 'group-1',
        'student_full_name': 'Student $studentId',
        'school_name': 'School',
        'class_label': '7zh',
        'class_teacher_full_name': 'Teacher',
      },
      'local_app_profile': {
        'shift': 2,
        'parent_phone_1': '+77010000001',
        'parent_phone_2': '+77010000002',
      },
    });
  }

  V2ResultsResponse buildResults({
    required String snapshotAt,
    required String windowKey,
    required String resultId,
  }) {
    return V2ResultsResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': snapshotAt,
        'window_key': windowKey,
      },
      'lessons': [
        {
          'lesson_id': 'lesson-1',
          'provider': 'kundelik',
          'provider_lesson_id': 'pl-1',
          'provider_subject_id': 'subject-1',
          'lesson_date': '2026-03-10',
          'lesson_number': 2,
          'subject_name': 'Math',
          'start_time': '08:30',
          'end_time': '09:15',
          'theme': 'Linear equations',
          'homework_text': 'Solve 1-10',
          'homework_status': 'assigned',
        },
      ],
      'results': [
        {
          'result_id': resultId,
          'provider': 'kundelik',
          'result_kind': 'regular',
          'provider_work_id': 'work-1',
          'provider_mark_id': 'mark-1',
          'provider_subject_id': 'subject-1',
          'subject_name': 'Math',
          'value_text': '5',
          'resolved_mood': 'good',
          'recorded_on': '2026-03-10',
          'source_endpoint': 'diary',
          'source_mood_raw': 'good',
        },
      ],
      'aggregates': [
        {
          'aggregate_id': 'aggregate-1',
          'provider': 'kundelik',
          'result_kind': 'term',
          'provider_subject_id': 'subject-1',
          'subject_name': 'Math',
          'value_text': '4',
          'resolved_mood': 'neutral',
          'recorded_on': '2026-03-30',
          'term_no': 3,
          'year_label': '',
        },
      ],
      'attendance': [
        {
          'attendance_id': 'attendance-1',
          'provider': 'kundelik',
          'provider_event_key': 'event-1',
          'provider_lesson_ref': 'pl-1',
          'recorded_on': '2026-03-10',
          'raw_code': 'N',
          'normalized_status': 'absent',
          'reason': 'ill',
        },
      ],
    });
  }

  V2OverviewResponse buildOverview({
    required String studentId,
    required String personId,
    required String snapshotAt,
    required String windowKey,
  }) {
    return V2OverviewResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': snapshotAt,
        'window_key': windowKey,
      },
      'provider_identity': {
        'provider': 'kundelik',
        'provider_account_ref': 'acc-$studentId',
        'provider_person_id': personId,
        'provider_school_id': 'school-1',
        'provider_group_id': 'group-1',
        'student_full_name': 'Student $studentId',
        'school_name': 'School',
        'class_label': '7zh',
        'class_teacher_full_name': 'Teacher',
      },
      'local_app_profile': {
        'shift': 2,
        'parent_phone_1': '+77010000001',
        'parent_phone_2': '+77010000002',
      },
      'counts': {
        'lessons_in_window': 1,
        'results_in_window': 1,
        'aggregates_in_window': 1,
        'attendance_alerts': 1,
      },
      'highlights': {
        'recent_results': [
          {
            'result_id': 'result-1',
            'result_kind': 'regular',
            'subject_name': 'Math',
            'value_text': '5',
            'recorded_on': '2026-03-10',
            'resolved_mood': 'good',
          },
        ],
        'upcoming_lessons': [
          {
            'lesson_id': 'lesson-1',
            'lesson_date': '2026-03-20',
            'lesson_number': 1,
            'subject_name': 'Math',
            'theme': 'Quadratic equations',
            'homework_text': 'Solve 11-20',
          },
        ],
      },
    });
  }

  test(
      'applyV2RefreshSnapshot writes full snapshot and publishes active pointer',
      () async {
    final db = await AppDatabase.open();
    await clearTables(db);
    final store = CanonicalCacheStore();

    const studentId = 'student-1';
    const personId = 'person-1';
    const snapshot = '2026-04-01T10:00:00Z';
    const windowKey = 'kundelik:2026-03-01:2026-03-31';

    final stats = await store.applyV2RefreshSnapshot(
      studentId: studentId,
      profile: buildProfile(
        studentId: studentId,
        personId: personId,
        snapshotAt: snapshot,
        windowKey: windowKey,
      ),
      results: buildResults(
        snapshotAt: snapshot,
        windowKey: windowKey,
        resultId: 'result-1',
      ),
      overview: buildOverview(
        studentId: studentId,
        personId: personId,
        snapshotAt: snapshot,
        windowKey: windowKey,
      ),
      traceId: 'trace-1',
    );

    expect(stats.rowsWritten, greaterThan(0));

    final resultCount = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_results_cache_v2 WHERE student_id = '$studentId'",
    ));
    final aggregateCount = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_aggregates_cache_v2 WHERE student_id = '$studentId'",
    ));
    final lessonCount = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_lessons_cache_v2 WHERE student_id = '$studentId'",
    ));
    final attendanceCount = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_attendance_cache_v2 WHERE student_id = '$studentId'",
    ));
    final countsRows = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_overview_counts_cache_v2 WHERE student_id = '$studentId'",
    ));
    final highlightsRows = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_overview_highlights_cache_v2 WHERE student_id = '$studentId'",
    ));

    expect(resultCount, 1);
    expect(aggregateCount, 1);
    expect(lessonCount, 1);
    expect(attendanceCount, 1);
    expect(countsRows, 1);
    expect(highlightsRows, 2);

    final activeSnapshotRows = await db.query(
      'canonical_read_mode_metadata',
      columns: ['meta_value'],
      where: 'meta_key = ?',
      whereArgs: ['${studentId}_kundelik_active_snapshot_at'],
      limit: 1,
    );
    expect(activeSnapshotRows.single['meta_value'], snapshot);

    final refreshStatusRows = await db.query(
      'canonical_read_mode_metadata',
      columns: ['meta_value'],
      where: 'meta_key = ?',
      whereArgs: ['${studentId}_kundelik_last_refresh_status'],
      limit: 1,
    );
    expect(refreshStatusRows.single['meta_value'], 'success');
  });

  test(
      'stale cleanup rollback safety keeps previous snapshot and pointer on failed write',
      () async {
    final db = await AppDatabase.open();
    await clearTables(db);
    final store = CanonicalCacheStore();

    const studentId = 'student-1';
    const personId = 'person-1';
    const snapshot1 = '2026-04-01T10:00:00Z';
    const snapshot2 = '2026-04-02T10:00:00Z';
    const windowKey = 'kundelik:2026-03-01:2026-03-31';

    await store.applyV2RefreshSnapshot(
      studentId: studentId,
      profile: buildProfile(
        studentId: studentId,
        personId: personId,
        snapshotAt: snapshot1,
        windowKey: windowKey,
      ),
      results: buildResults(
        snapshotAt: snapshot1,
        windowKey: windowKey,
        resultId: 'result-1',
      ),
      overview: buildOverview(
        studentId: studentId,
        personId: personId,
        snapshotAt: snapshot1,
        windowKey: windowKey,
      ),
      traceId: 'trace-1',
    );

    await expectLater(
      () => store.applyV2RefreshSnapshot(
        studentId: studentId,
        profile: buildProfile(
          studentId: studentId,
          personId: personId,
          snapshotAt: snapshot2,
          windowKey: windowKey,
        ),
        results: buildResults(
          snapshotAt: snapshot2,
          windowKey: windowKey,
          resultId: '',
        ),
        overview: buildOverview(
          studentId: studentId,
          personId: personId,
          snapshotAt: snapshot2,
          windowKey: windowKey,
        ),
        traceId: 'trace-2',
      ),
      throwsA(isA<FormatException>()),
    );

    final snapshot1Rows = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_results_cache_v2 WHERE student_id = '$studentId' AND snapshot_at = '$snapshot1'",
    ));
    final snapshot2Rows = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_results_cache_v2 WHERE student_id = '$studentId' AND snapshot_at = '$snapshot2'",
    ));

    expect(snapshot1Rows, 1);
    expect(snapshot2Rows, 0);

    final activeSnapshotRows = await db.query(
      'canonical_read_mode_metadata',
      columns: ['meta_value'],
      where: 'meta_key = ?',
      whereArgs: ['${studentId}_kundelik_active_snapshot_at'],
      limit: 1,
    );
    expect(activeSnapshotRows.single['meta_value'], snapshot1);

    final refreshStatusRows = await db.query(
      'canonical_read_mode_metadata',
      columns: ['meta_value'],
      where: 'meta_key = ?',
      whereArgs: ['${studentId}_kundelik_last_refresh_status'],
      limit: 1,
    );
    expect(refreshStatusRows.single['meta_value'], 'success');
  });

  test('v2 refresh snapshot does not write legacy canonical_grades_cache',
      () async {
    final db = await AppDatabase.open();
    await clearTables(db);
    final store = CanonicalCacheStore();

    await db.insert('canonical_grades_cache', {
      'grade_id': 'legacy-1',
      'value': '3',
      'mood': 'neutral',
      'grade_type': 'regular',
      'created_at': '2026-03-01T00:00:00Z',
      'updated_at': '2026-03-01T00:00:00Z',
    });

    await store.applyV2RefreshSnapshot(
      studentId: 'student-1',
      profile: buildProfile(
        studentId: 'student-1',
        personId: 'person-1',
        snapshotAt: '2026-04-01T10:00:00Z',
        windowKey: 'kundelik:2026-03-01:2026-03-31',
      ),
      results: buildResults(
        snapshotAt: '2026-04-01T10:00:00Z',
        windowKey: 'kundelik:2026-03-01:2026-03-31',
        resultId: 'result-1',
      ),
      overview: buildOverview(
        studentId: 'student-1',
        personId: 'person-1',
        snapshotAt: '2026-04-01T10:00:00Z',
        windowKey: 'kundelik:2026-03-01:2026-03-31',
      ),
      traceId: 'trace-1',
    );

    final legacyRows = await db.query('canonical_grades_cache');
    expect(legacyRows.length, 1);
    expect(legacyRows.single['grade_id'], 'legacy-1');
    expect(legacyRows.single['value'], '3');
  });
}
