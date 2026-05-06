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
    AppDatabase.setTestDbNameOverride('kundi_mobile_cache_isolation.db');
  });

  tearDownAll(() {
    AppDatabase.setTestDbNameOverride(null);
  });

  test('CacheIsolation_DifferentStudents_NoLeak', () async {
    final db = await AppDatabase.open();
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

    final store = CanonicalCacheStore();
    const windowKey = 'kundelik:2026-03-01:2026-03-31';
    const snapshot1 = '2026-04-01T10:00:00Z';
    const snapshot2 = '2026-04-02T10:00:00Z';

    Future<void> writeStudent({
      required String studentId,
      required String personId,
      required String snapshot,
      required String value,
    }) async {
      final profile = V2ProfileResponse.fromJson({
        'window': {
          'provider': 'kundelik',
          'window_from': '2026-03-01',
          'window_to': '2026-03-31',
          'snapshot_at': snapshot,
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

      final results = V2ResultsResponse.fromJson({
        'window': {
          'provider': 'kundelik',
          'window_from': '2026-03-01',
          'window_to': '2026-03-31',
          'snapshot_at': snapshot,
          'window_key': windowKey,
        },
        'lessons': [
          {
            'lesson_id': 'lesson-shared',
            'provider': 'kundelik',
            'provider_lesson_id': 'l1',
            'provider_subject_id': 'subject-1',
            'lesson_date': '2026-03-10',
            'lesson_number': 2,
            'subject_name': 'Math',
            'start_time': '08:30',
            'end_time': '09:15',
            'theme': 'Topic',
            'homework_text': 'Do exercise',
            'homework_status': 'assigned',
          },
        ],
        'results': [
          {
            'result_id': 'result-shared',
            'provider': 'kundelik',
            'result_kind': 'regular',
            'provider_work_id': 'work-1',
            'provider_mark_id': '',
            'provider_subject_id': 'subject-1',
            'subject_name': 'Math',
            'value_text': value,
            'resolved_mood': 'good',
            'source_endpoint': 'diary',
            'source_mood_raw': 'good',
            'recorded_on': '2026-03-10',
          },
        ],
        'aggregates': [
          {
            'aggregate_id': 'aggregate-shared',
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
            'attendance_id': 'attendance-shared',
            'provider': 'kundelik',
            'provider_event_key': 'event-1',
            'provider_lesson_ref': 'l1',
            'recorded_on': '2026-03-10',
            'raw_code': 'N',
            'normalized_status': 'absent',
            'reason': '',
          },
        ],
      });

      final overview = V2OverviewResponse.fromJson({
        'window': {
          'provider': 'kundelik',
          'window_from': '2026-03-01',
          'window_to': '2026-03-31',
          'snapshot_at': snapshot,
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
        'highlights': const {
          'recent_results': <dynamic>[],
          'upcoming_lessons': <dynamic>[],
        },
      });

      await store.applyV2RefreshSnapshot(
        studentId: studentId,
        profile: profile,
        results: results,
        overview: overview,
        traceId: 'trace-$studentId-$snapshot',
      );
    }

    await writeStudent(
      studentId: 'student-1',
      personId: 'person-1',
      snapshot: snapshot1,
      value: '5',
    );
    await writeStudent(
      studentId: 'student-2',
      personId: 'person-2',
      snapshot: snapshot1,
      value: '4',
    );

    await writeStudent(
      studentId: 'student-1',
      personId: 'person-1',
      snapshot: snapshot2,
      value: '3',
    );

    final student2Rows = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_results_cache_v2 WHERE student_id = 'student-2'",
    ));
    final student1OldRows = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_results_cache_v2 WHERE student_id = 'student-1' AND snapshot_at = '$snapshot1'",
    ));
    final student1NewRows = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM canonical_results_cache_v2 WHERE student_id = 'student-1' AND snapshot_at = '$snapshot2'",
    ));

    expect(student2Rows, 1);
    expect(student1OldRows, 0);
    expect(student1NewRows, 1);
  });
}
