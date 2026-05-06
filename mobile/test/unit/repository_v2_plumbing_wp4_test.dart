import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/app_database.dart';
import 'package:kundi_mobile/core/db/canonical_cache_store.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/features/grades/data/grades_repository_impl.dart';
import 'package:kundi_mobile/features/lessons/data/lessons_repository_impl.dart';
import 'package:kundi_mobile/features/profile/data/profile_repository_impl.dart';
import 'package:kundi_mobile/features/summary/data/summary_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.setTestDbNameOverride('kundi_mobile_wp4_repos.db');
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
    await db.delete('canonical_lessons_cache');
    await db.delete('canonical_grades_cache');
  }

  test('WP4 repositories read only active v2 snapshot context', () async {
    final db = await AppDatabase.open();
    await clearTables(db);

    final store = CanonicalCacheStore();
    final profileRepo = ProfileRepositoryImpl(
      store,
      _NoopApiClient(),
      _noSession,
    );
    final gradesRepo = GradesRepositoryImpl(store);
    final lessonsRepo = LessonsRepositoryImpl(store);
    final summaryRepo = SummaryRepositoryImpl(store);

    const studentId = 'student-1';
    const provider = 'kundelik';
    const window = 'kundelik:2026-03-01:2026-03-31';
    const scopedWindow = '$studentId:$provider:$window';
    const snapshotOld = '2026-04-01T10:00:00Z';
    const snapshotNew = '2026-04-02T10:00:00Z';
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    final futureYmd =
        '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: window,
      snapshotAt: snapshotNew,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-wp4',
    );

    Future<void> insertSnapshot(String snapshotAt, String marker) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert(
          'canonical_provider_identity_cache_v2',
          {
            'student_id': studentId,
            'provider': provider,
            'provider_account_ref': 'acc',
            'provider_person_id': 'person-1',
            'provider_school_id': 'school-1',
            'provider_group_id': 'group-1',
            'student_full_name': 'Name $marker',
            'school_name': 'School $marker',
            'class_label': '7$marker',
            'class_teacher_full_name': 'Teacher $marker',
            'window_key': scopedWindow,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert(
          'canonical_results_cache_v2',
          {
            'result_id': '$studentId:$provider:r-$marker',
            'student_id': studentId,
            'provider': provider,
            'provider_person_id': 'person-1',
            'result_kind': 'regular',
            'provider_work_id': 'work-$marker',
            'provider_mark_id': 'mark-$marker',
            'provider_subject_id': 'subject-1',
            'subject_name': 'Math',
            'value_text': marker,
            'resolved_mood': marker == 'NEW' ? 'good' : 'bad',
            'source_endpoint': 'diary',
            'source_mood_raw': marker.toLowerCase(),
            'recorded_on': '2026-03-10',
            'window_key': scopedWindow,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert(
          'canonical_aggregates_cache_v2',
          {
            'aggregate_id': '$studentId:$provider:a-$marker',
            'student_id': studentId,
            'provider': provider,
            'provider_person_id': 'person-1',
            'result_kind': 'term',
            'provider_subject_id': 'subject-1',
            'subject_name': 'Math',
            'value_text': marker,
            'resolved_mood': 'neutral',
            'recorded_on': '2026-03-30',
            'term_no': 3,
            'year_label': '',
            'window_key': scopedWindow,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert(
          'canonical_lessons_cache_v2',
          {
            'lesson_id': '$studentId:$provider:l-$marker',
            'student_id': studentId,
            'provider': provider,
            'provider_person_id': 'person-1',
            'provider_lesson_id': 'lesson-ref',
            'provider_subject_id': 'subject-1',
            'lesson_date': '2026-03-10',
            'lesson_number': 1,
            'subject_name': 'Math',
            'start_time': '08:30',
            'end_time': '09:15',
            'theme': 'Theme $marker',
            'homework_text': 'Homework $marker',
            'homework_status': 'assigned',
            'window_key': scopedWindow,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert(
          'canonical_attendance_cache_v2',
          {
            'attendance_id': '$studentId:$provider:att-$marker',
            'student_id': studentId,
            'provider': provider,
            'provider_person_id': 'person-1',
            'provider_event_key': 'evt-$marker',
            'provider_lesson_ref': 'lesson-ref',
            'recorded_on': '2026-03-10',
            'raw_code': 'N',
            'normalized_status': marker == 'NEW' ? 'present' : 'absent',
            'reason': '',
            'window_key': scopedWindow,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert(
          'canonical_overview_counts_cache_v2',
          {
            'overview_counts_key':
                '$studentId:$provider:$scopedWindow:counts:$marker',
            'student_id': studentId,
            'provider': provider,
            'provider_person_id': 'person-1',
            'lessons_in_window': marker == 'NEW' ? 10 : 1,
            'results_in_window': marker == 'NEW' ? 20 : 2,
            'aggregates_in_window': marker == 'NEW' ? 3 : 1,
            'attendance_alerts': marker == 'NEW' ? 0 : 5,
            'window_key': scopedWindow,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert(
          'canonical_overview_highlights_cache_v2',
          {
            'highlight_key':
                '$studentId:$provider:recent_results:$scopedWindow:$snapshotAt',
            'student_id': studentId,
            'provider': provider,
            'provider_person_id': 'person-1',
            'highlight_kind': 'recent_results',
            'payload_json': jsonEncode([
              {
                'result_id': 'r-$marker',
                'result_kind': 'regular',
                'subject_name': 'Math',
                'value_text': marker,
                'recorded_on': '2026-03-10',
                'resolved_mood': marker == 'NEW' ? 'good' : 'bad',
              }
            ]),
            'window_key': scopedWindow,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert(
          'canonical_overview_highlights_cache_v2',
          {
            'highlight_key':
                '$studentId:$provider:upcoming_lessons:$scopedWindow:$snapshotAt',
            'student_id': studentId,
            'provider': provider,
            'provider_person_id': 'person-1',
            'highlight_kind': 'upcoming_lessons',
            'payload_json': jsonEncode([
              {
                'lesson_id': 'l-$marker',
                'lesson_date': futureYmd,
                'lesson_number': 1,
                'subject_name': 'Math',
                'theme': 'Theme $marker',
                'homework_text': 'Homework $marker',
              }
            ]),
            'window_key': scopedWindow,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await insertSnapshot(snapshotOld, 'OLD');
    await insertSnapshot(snapshotNew, 'NEW');

    final profile = await profileRepo.get();
    final grades = await gradesRepo.get();
    final lessons = await lessonsRepo.list();
    final summary = await summaryRepo.get();

    expect(profile, isNotNull);
    expect(profile!.readMode, 'v2');
    expect(profile.providerIdentity, isNotNull);
    expect(profile.providerIdentity!.schoolName, 'School NEW');
    expect(grades.readMode, 'v2');
    final weeklyRows = grades.weeklyRowsByWeek.values.expand((x) => x).toList();
    final weeklyMarks = weeklyRows
        .expand((row) => row.cellsByWeekday.values)
        .expand((cell) => cell.regularMarks)
        .toList();
    expect(
      weeklyMarks.any((value) => value == 'NEW'),
      isTrue,
    );
    expect(
      weeklyMarks.any((value) => value == 'OLD'),
      isFalse,
    );
    expect(lessons.single.topic, 'Theme NEW');
    expect(lessons.single.gradeValue, 'NEW');
    expect(lessons.single.attendanceCode, 'N');

    expect(summary.available, isTrue);
    expect(summary.lessonsCount, 1);
    expect(summary.homeworkCount, 1);
    expect(summary.resultsCount, 1);
    expect(summary.attendanceCount, 1);
    expect(summary.aggregatesCount, 1);
    expect(summary.recentResults.single.valueText, 'NEW');
    expect(summary.upcomingLessons.single.theme, 'Theme NEW');
  });

  test('WP4 repositories fallback to v1 cache when active mode is v1',
      () async {
    final db = await AppDatabase.open();
    await clearTables(db);

    final store = CanonicalCacheStore();
    final profileRepo = ProfileRepositoryImpl(
      store,
      _NoopApiClient(),
      _noSession,
    );
    final gradesRepo = GradesRepositoryImpl(store);
    final lessonsRepo = LessonsRepositoryImpl(store);
    final summaryRepo = SummaryRepositoryImpl(store);

    await store.setReadMode(
      studentId: 'student-1',
      provider: 'kundelik',
      mode: 'v1',
      windowKey: 'kundelik:v1',
      snapshotAt: '2026-04-02T10:00:00Z',
      refreshMode: 'v1',
      refreshStatus: 'success',
      traceId: 'trace-v1',
    );

    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
        'canonical_profile_cache',
        {
          'student_id': 'student-1',
          'first_name': 'Old',
          'last_name': 'Profile',
          'grade_level': 7,
          'class_label': '7A',
          'school_name': 'Legacy School',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert(
        'canonical_grades_cache',
        {
          'grade_id': 'g-1',
          'value': '5',
          'mood': 'good',
          'grade_type': 'regular',
          'created_at': '2026-03-10',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert(
        'canonical_lessons_cache',
        {
          'lesson_id': 'l-1',
          'lesson_date': '2026-03-10',
          'lesson_number': 1,
          'subject_name': 'Math',
          'topic': 'Legacy Topic',
          'homework_text': 'Legacy Homework',
          'requires_photo': 0,
          'grade_value': '5',
          'grade_mood': 'good',
          'attendance_code': 'N',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    final profile = await profileRepo.get();
    final grades = await gradesRepo.get();
    final lessons = await lessonsRepo.list();
    final summary = await summaryRepo.get();

    expect(profile, isNotNull);
    expect(profile!.readMode, 'v1');
    expect(profile.providerIdentity, isNotNull);
    expect(profile.providerIdentity!.schoolName, 'Legacy School');
    expect(grades.readMode, 'v1');
    expect(grades.summativeBySubject.single.items.single.value, '5');
    expect(lessons.single.topic, 'Legacy Topic');
    expect(summary.available, isTrue);
  });
}

AuthSession? _noSession() => null;

class _NoopApiClient extends ApiClient {
  _NoopApiClient() : super(baseUrl: 'http://127.0.0.1:1');
}
