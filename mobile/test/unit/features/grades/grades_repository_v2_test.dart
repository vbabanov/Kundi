import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/app_database.dart';
import 'package:kundi_mobile/core/db/canonical_cache_store.dart';
import 'package:kundi_mobile/features/grades/data/grades_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.setTestDbNameOverride('kundi_mobile_grades_repo_v2.db');
  });

  tearDownAll(() {
    AppDatabase.setTestDbNameOverride(null);
  });

  setUp(() async {
    final db = await AppDatabase.open();
    await db.delete('canonical_read_mode_metadata');
    await db.delete('canonical_results_cache_v2');
    await db.delete('canonical_aggregates_cache_v2');
    await db.delete('canonical_lessons_cache_v2');
    await db.delete('canonical_attendance_cache_v2');
    await db.delete('canonical_grades_cache');
  });

  test('groups regular grades by subject/date and keeps summative separate',
      () async {
    final db = await AppDatabase.open();
    final store = CanonicalCacheStore();
    final repo = GradesRepositoryImpl(store);
    const studentId = 'student-1';
    const provider = 'kundelik';
    const windowKey = 'kundelik:2026-04-01:2026-04-14';
    const snapshotAt = '2026-04-05T12:00:00Z';
    const scopedWindow = '$studentId:$provider:$windowKey';
    final now = DateTime.now().toUtc().toIso8601String();

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: windowKey,
      snapshotAt: snapshotAt,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-grades-repo',
    );

    await db.insert(
      'canonical_lessons_cache_v2',
      {
        'lesson_id': '$studentId:$provider:lesson-1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-1',
        'provider_lesson_id': 'lesson-1',
        'provider_subject_id': 'sub-math',
        'lesson_date': '2026-04-06',
        'lesson_number': 1,
        'subject_name': 'Algebra',
        'start_time': '',
        'end_time': '',
        'theme': '',
        'homework_text': '',
        'homework_status': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );
    await db.insert(
      'canonical_lessons_cache_v2',
      {
        'lesson_id': '$studentId:$provider:lesson-2',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-1',
        'provider_lesson_id': 'lesson-2',
        'provider_subject_id': 'sub-hist',
        'lesson_date': '2026-04-07',
        'lesson_number': 2,
        'subject_name': 'History',
        'start_time': '',
        'end_time': '',
        'theme': '',
        'homework_text': '',
        'homework_status': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );

    await db.insert(
      'canonical_results_cache_v2',
      {
        'result_id': '$studentId:$provider:res-1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-1',
        'result_kind': 'regular',
        'provider_work_id': 'work-1',
        'provider_mark_id': 'mark-1',
        'provider_subject_id': 'sub-math',
        'subject_name': 'Algebra',
        'value_text': '9',
        'resolved_mood': 'good',
        'source_endpoint': 'diary',
        'source_mood_raw': 'Good',
        'recorded_on': '2026-04-06',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );
    await db.insert(
      'canonical_results_cache_v2',
      {
        'result_id': '$studentId:$provider:res-2',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-1',
        'result_kind': 'sor',
        'provider_work_id': 'work-sor',
        'provider_mark_id': 'mark-sor',
        'provider_subject_id': 'sub-math',
        'subject_name': 'Algebra',
        'value_text': '12/15',
        'resolved_mood': 'average',
        'source_endpoint': 'period',
        'source_mood_raw': 'Average',
        'recorded_on': '2026-04-08',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );
    await db.insert(
      'canonical_results_cache_v2',
      {
        'result_id': '$studentId:$provider:res-3',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-1',
        'result_kind': 'soch',
        'provider_work_id': 'work-soch',
        'provider_mark_id': 'mark-soch',
        'provider_subject_id': 'sub-math',
        'subject_name': 'Algebra',
        'value_text': '18/20',
        'resolved_mood': 'average',
        'source_endpoint': 'period',
        'source_mood_raw': 'Average',
        'recorded_on': '2026-04-10',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );
    await db.insert(
      'canonical_aggregates_cache_v2',
      {
        'aggregate_id': '$studentId:$provider:agg-1',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-1',
        'result_kind': 'term',
        'provider_subject_id': 'sub-math',
        'subject_name': 'Algebra',
        'value_text': '4',
        'resolved_mood': 'average',
        'recorded_on': '2026-04-12',
        'term_no': 3,
        'year_label': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );

    final data = await repo.get();

    expect(data.readMode, 'v2');
    expect(data.latestRegularResults, isNotEmpty);
    expect(data.latestRegularResults.first.subjectName, 'Algebra');
    expect(data.latestRegularResults.first.value, '9');
    expect(data.availableWeeks, isNotEmpty);
    final rows = data.weeklyRowsByWeek[data.availableWeeks.last.weekKey]!;
    final algebra = rows.firstWhere((row) => row.subjectName == 'Algebra');
    expect(algebra.cellsByWeekday[1]!.regularMarks, contains('9'));
    final history = rows.firstWhere((row) => row.subjectName == 'History');
    expect(history.cellsByWeekday[2]!.showDot, isTrue);

    expect(data.summativeBySubject, hasLength(1));
    expect(data.summativeBySubject.single.providerSubjectId, 'sub-math');
    expect(
      data.summativeBySubject.single.items.map((it) => it.kind).toSet(),
      {'sor', 'soch'},
    );
    expect(data.aggregatesBySubject, hasLength(1));
    expect(data.aggregatesBySubject.single.providerSubjectId, 'sub-math');
    expect(data.aggregatesBySubject.single.termItems, hasLength(1));
    expect(data.aggregatesBySubject.single.yearItems, isEmpty);
  });

  test('aggregates stay separate and year can be empty without error',
      () async {
    final db = await AppDatabase.open();
    final store = CanonicalCacheStore();
    final repo = GradesRepositoryImpl(store);
    const studentId = 'student-2';
    const provider = 'kundelik';
    const windowKey = 'kundelik:2026-03-01:2026-03-31';
    const snapshotAt = '2026-04-05T12:05:00Z';
    const scopedWindow = '$studentId:$provider:$windowKey';
    final now = DateTime.now().toUtc().toIso8601String();

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: windowKey,
      snapshotAt: snapshotAt,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-grades-repo-2',
    );

    await db.insert(
      'canonical_aggregates_cache_v2',
      {
        'aggregate_id': '$studentId:$provider:agg-term',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-2',
        'result_kind': 'term',
        'provider_subject_id': 'sub-phys',
        'subject_name': 'Physics',
        'value_text': '5',
        'resolved_mood': 'good',
        'recorded_on': '2026-03-30',
        'term_no': 3,
        'year_label': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );

    final data = await repo.get();
    final physics = data.aggregatesBySubject.single;
    expect(physics.subjectName, 'Physics');
    expect(physics.providerSubjectId, 'sub-phys');
    expect(physics.termItems.single.value, '5');
    expect(physics.yearItems, isEmpty);
  });

  test(
      'maps attendance by date+provider_subject_id+lesson_number when lesson ref mismatches',
      () async {
    final db = await AppDatabase.open();
    final store = CanonicalCacheStore();
    final repo = GradesRepositoryImpl(store);
    const studentId = 'student-att-map';
    const provider = 'kundelik';
    const windowKey = 'kundelik:2026-04-01:2026-04-14';
    const snapshotAt = '2026-04-05T13:00:00Z';
    const scopedWindow = '$studentId:$provider:$windowKey';
    final now = DateTime.now().toUtc().toIso8601String();

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: windowKey,
      snapshotAt: snapshotAt,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-att-map',
    );

    await db.insert('canonical_lessons_cache_v2', {
      'lesson_id': '$studentId:$provider:lesson-a',
      'student_id': studentId,
      'provider': provider,
      'provider_person_id': 'person-a',
      'provider_lesson_id': 'lesson-real-ref',
      'provider_subject_id': 'sub-math',
      'lesson_date': '2026-04-07',
      'lesson_number': 2,
      'subject_name': 'Algebra',
      'start_time': '',
      'end_time': '',
      'theme': '',
      'homework_text': '',
      'homework_status': '',
      'window_key': scopedWindow,
      'snapshot_at': snapshotAt,
      'updated_at': now,
    });

    await db.insert('canonical_attendance_cache_v2', {
      'attendance_id': '$studentId:$provider:att-a',
      'student_id': studentId,
      'provider': provider,
      'provider_person_id': 'person-a',
      'provider_event_key': 'att-a',
      'provider_lesson_ref': 'non-matching-ref',
      'provider_subject_id': 'sub-math',
      'subject_name': 'Algebra',
      'lesson_number': 2,
      'recorded_on': '2026-04-07',
      'raw_code': 'absent',
      'normalized_status': 'absent',
      'reason': '',
      'window_key': scopedWindow,
      'snapshot_at': snapshotAt,
      'updated_at': now,
    });

    final data = await repo.get();
    final weekKey = data.availableWeeks.single.weekKey;
    final row = data.weeklyRowsByWeek[weekKey]!
        .firstWhere((it) => it.subjectName == 'Algebra');
    expect(row.cellsByWeekday[2]!.attendanceCodes, contains('absent'));
    expect(row.cellsByWeekday[2]!.showDot, isFalse);
  });

  test('does not map ambiguous attendance fallback', () async {
    final db = await AppDatabase.open();
    final store = CanonicalCacheStore();
    final repo = GradesRepositoryImpl(store);
    const studentId = 'student-att-amb';
    const provider = 'kundelik';
    const windowKey = 'kundelik:2026-04-01:2026-04-14';
    const snapshotAt = '2026-04-05T13:10:00Z';
    const scopedWindow = '$studentId:$provider:$windowKey';
    final now = DateTime.now().toUtc().toIso8601String();

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: windowKey,
      snapshotAt: snapshotAt,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-att-amb',
    );

    for (final lessonId in ['lesson-1', 'lesson-2']) {
      await db.insert('canonical_lessons_cache_v2', {
        'lesson_id': '$studentId:$provider:$lessonId',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-a',
        'provider_lesson_id': lessonId,
        'provider_subject_id': '',
        'lesson_date': '2026-04-07',
        'lesson_number': 3,
        'subject_name': 'History',
        'start_time': '',
        'end_time': '',
        'theme': '',
        'homework_text': '',
        'homework_status': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      });
    }

    await db.insert('canonical_attendance_cache_v2', {
      'attendance_id': '$studentId:$provider:att-amb',
      'student_id': studentId,
      'provider': provider,
      'provider_person_id': 'person-a',
      'provider_event_key': 'att-amb',
      'provider_lesson_ref': 'non-matching-ref',
      'provider_subject_id': '',
      'subject_name': 'History',
      'lesson_number': 3,
      'recorded_on': '2026-04-07',
      'raw_code': 'excused',
      'normalized_status': 'excused',
      'reason': '',
      'window_key': scopedWindow,
      'snapshot_at': snapshotAt,
      'updated_at': now,
    });

    final data = await repo.get();
    final weekKey = data.availableWeeks.single.weekKey;
    final row = data.weeklyRowsByWeek[weekKey]!
        .firstWhere((it) => it.subjectName == 'History');
    expect(row.cellsByWeekday[2]!.attendanceCodes, isEmpty);
    expect(row.cellsByWeekday[2]!.showDot, isTrue);
  });

  test(
      'latest and weekly include older school-year records when present in active snapshot',
      () async {
    final db = await AppDatabase.open();
    final store = CanonicalCacheStore();
    final repo = GradesRepositoryImpl(store);
    const studentId = 'student-3';
    const provider = 'kundelik';
    const windowKey = 'kundelik:2025-09-01:2026-04-05';
    const snapshotAt = '2026-04-05T12:10:00Z';
    const scopedWindow = '$studentId:$provider:$windowKey';
    final now = DateTime.now().toUtc().toIso8601String();

    await store.setReadMode(
      studentId: studentId,
      provider: provider,
      mode: 'v2',
      windowKey: windowKey,
      snapshotAt: snapshotAt,
      refreshMode: 'v2',
      refreshStatus: 'success',
      traceId: 'trace-grades-repo-3',
    );

    await db.insert(
      'canonical_lessons_cache_v2',
      {
        'lesson_id': '$studentId:$provider:lesson-old',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-3',
        'provider_lesson_id': 'lesson-old',
        'provider_subject_id': 'sub-math',
        'lesson_date': '2025-09-15',
        'lesson_number': 2,
        'subject_name': 'Algebra',
        'start_time': '',
        'end_time': '',
        'theme': '',
        'homework_text': '',
        'homework_status': '',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );
    await db.insert(
      'canonical_results_cache_v2',
      {
        'result_id': '$studentId:$provider:res-old',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-3',
        'result_kind': 'regular',
        'provider_work_id': 'work-old',
        'provider_mark_id': 'mark-old',
        'provider_subject_id': 'sub-math',
        'subject_name': 'Algebra',
        'value_text': '8',
        'resolved_mood': 'good',
        'source_endpoint': 'diary',
        'source_mood_raw': 'Good',
        'recorded_on': '2025-09-15',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );
    await db.insert(
      'canonical_results_cache_v2',
      {
        'result_id': '$studentId:$provider:res-new',
        'student_id': studentId,
        'provider': provider,
        'provider_person_id': 'person-3',
        'result_kind': 'regular',
        'provider_work_id': 'work-new',
        'provider_mark_id': 'mark-new',
        'provider_subject_id': 'sub-math',
        'subject_name': 'Algebra',
        'value_text': '10',
        'resolved_mood': 'great',
        'source_endpoint': 'diary',
        'source_mood_raw': 'Great',
        'recorded_on': '2026-03-20',
        'window_key': scopedWindow,
        'snapshot_at': snapshotAt,
        'updated_at': now,
      },
    );

    final data = await repo.get();

    expect(data.latestRegularResults.length, greaterThanOrEqualTo(2));
    expect(
      data.latestRegularResults.any((item) => item.recordedOn == '2025-09-15'),
      isTrue,
    );
    expect(
      data.availableWeeks
          .any((week) => week.weekStartDate.startsWith('2025-09')),
      isTrue,
    );
  });
}
