import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/app_database.dart';
import 'package:kundi_mobile/core/db/canonical_cache_store.dart';
import 'package:kundi_mobile/core/db/sync_queue_repository.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/core/network/read_source_policy.dart';
import 'package:kundi_mobile/core/network/v2_read_models.dart';
import 'package:kundi_mobile/features/auth/data/auth_repository_impl.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/connector_runtime.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/contracts/models.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/ingest_uploader.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/sync_orchestrator.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/sync_queue_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../test_support/fake_secure_storage_service.dart';

class _FakeQueueGateway implements SyncQueueGateway {
  @override
  Future<List<SyncQueueItem>> listReady() async => const <SyncQueueItem>[];

  @override
  Future<void> markFailure(String requestID, SyncFailure failure, int attempts) async {}

  @override
  Future<void> markSynced(String requestID) async {}
}

class _FakeUploader implements IngestUploader {
  @override
  Future<void> uploadBundle({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.setTestDbNameOverride('kundi_mobile_pr1_integrity_gate.db');
  });

  tearDownAll(() {
    AppDatabase.setTestDbNameOverride(null);
  });

  Future<void> clearAll(Database db) async {
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
    await db.delete('canonical_homework_cache');
    await db.delete('canonical_grades_cache');
  }

  AuthRepositoryImpl buildRepo(String baseUrl) {
    return AuthRepositoryImpl(
      apiClient: ApiClient(baseUrl: baseUrl),
      secureStorage: FakeSecureStorageService(),
      connectorRuntime: ConnectorRuntime(),
      canonicalCacheStore: CanonicalCacheStore(),
      syncQueueService: SyncQueueService(),
      syncOrchestrator: SyncOrchestrator(
        queue: _FakeQueueGateway(),
        uploader: _FakeUploader(),
      ),
      readSourcePolicy: const ReadSourcePolicy(
        useTypedV2Read: true,
        enableV2ParityShadow: false,
      ),
    );
  }

  Future<String> metaValue(Database db, String key) async {
    final rows = await db.query(
      'canonical_read_mode_metadata',
      columns: ['meta_value'],
      where: 'meta_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return '';
    }
    return (rows.first['meta_value'] ?? '').toString();
  }

  V2ProfileResponse profileDto(String snapshotAt) {
    return V2ProfileResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': snapshotAt,
        'window_key': 'kundelik:2026-03-01:2026-03-31',
      },
      'provider_identity': {
        'provider': 'kundelik',
        'provider_account_ref': 'acc',
        'provider_person_id': 'person-1',
        'provider_school_id': 'school-1',
        'provider_group_id': 'group-1',
        'student_full_name': 'Student One',
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

  V2ResultsResponse resultsDto(String snapshotAt, {required bool validAttendance}) {
    return V2ResultsResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': snapshotAt,
        'window_key': 'kundelik:2026-03-01:2026-03-31',
      },
      'lessons': [
        {
          'lesson_id': 'l1',
          'provider': 'kundelik',
          'provider_lesson_id': 'pl1',
          'provider_subject_id': 'sub1',
          'lesson_date': '2026-03-10',
          'lesson_number': 1,
          'subject_name': 'Math',
          'start_time': '08:30',
          'end_time': '09:15',
          'theme': 'Topic',
          'homework_text': 'Homework',
          'homework_status': 'assigned',
        },
      ],
      'results': [
        {
          'result_id': 'r1',
          'provider': 'kundelik',
          'result_kind': 'regular',
          'provider_work_id': 'w1',
          'provider_mark_id': 'm1',
          'provider_subject_id': 'sub1',
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
          'aggregate_id': 'a1',
          'provider': 'kundelik',
          'result_kind': 'term',
          'provider_subject_id': 'sub1',
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
          'attendance_id': validAttendance ? 'att1' : '',
          'provider': 'kundelik',
          'provider_event_key': 'evt1',
          'provider_lesson_ref': 'pl1',
          'recorded_on': '2026-03-10',
          'raw_code': 'N',
          'normalized_status': 'absent',
          'reason': '',
        },
      ],
    });
  }

  V2OverviewResponse overviewDto(String snapshotAt) {
    return V2OverviewResponse.fromJson({
      'window': {
        'provider': 'kundelik',
        'window_from': '2026-03-01',
        'window_to': '2026-03-31',
        'snapshot_at': snapshotAt,
        'window_key': 'kundelik:2026-03-01:2026-03-31',
      },
      'provider_identity': {
        'provider': 'kundelik',
        'provider_account_ref': 'acc',
        'provider_person_id': 'person-1',
        'provider_school_id': 'school-1',
        'provider_group_id': 'group-1',
        'student_full_name': 'Student One',
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
            'result_id': 'r1',
            'result_kind': 'regular',
            'subject_name': 'Math',
            'value_text': '5',
            'recorded_on': '2026-03-10',
            'resolved_mood': 'good',
          },
        ],
        'upcoming_lessons': [
          {
            'lesson_id': 'l1',
            'lesson_date': '2026-03-20',
            'lesson_number': 1,
            'subject_name': 'Math',
            'theme': 'Topic',
            'homework_text': 'Homework',
          },
        ],
      },
    });
  }

  Map<String, dynamic> authResponse(String studentId) => {
        'data': {
          'student_id': studentId,
          'access_token': 'token-$studentId',
          'refresh_token': 'refresh-$studentId',
          'expires_at': '2026-12-31T00:00:00Z',
        }
      };

  Map<String, dynamic> v1Profile(String studentId) => {
        'data': {
          'student_id': studentId,
          'first_name': 'Legacy',
          'last_name': 'User',
          'grade_level': 7,
          'class_label': '7A',
          'school_name': 'Legacy School',
        }
      };

  Map<String, dynamic> v1List() => {
        'data': {'items': <dynamic>[]}
      };

  test('PR1 gate: applyV2RefreshSnapshot rollback keeps previous snapshot and active pointer (no partial commit)', () async {
    final db = await AppDatabase.open();
    await clearAll(db);
    final store = CanonicalCacheStore();

    const studentId = 'student-1';
    const provider = 'kundelik';
    const snapshotOld = '2026-04-01T10:00:00Z';
    const snapshotNew = '2026-04-02T10:00:00Z';

    await store.applyV2RefreshSnapshot(
      studentId: studentId,
      profile: profileDto(snapshotOld),
      results: resultsDto(snapshotOld, validAttendance: true),
      overview: overviewDto(snapshotOld),
      traceId: 'trace-old',
    );

    await expectLater(
      () => store.applyV2RefreshSnapshot(
        studentId: studentId,
        profile: profileDto(snapshotNew),
        results: resultsDto(snapshotNew, validAttendance: false),
        overview: overviewDto(snapshotNew),
        traceId: 'trace-new',
      ),
      throwsA(isA<FormatException>()),
    );

    final scopedWindow = '$studentId:$provider:kundelik:2026-03-01:2026-03-31';
    Future<int> scopedCount(String table) async {
      return Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM $table WHERE student_id = '$studentId' AND provider = '$provider' AND window_key = '$scopedWindow' AND snapshot_at = '$snapshotOld'",
          )) ??
          0;
    }

    expect(await scopedCount('canonical_results_cache_v2'), 1);
    expect(await scopedCount('canonical_aggregates_cache_v2'), 1);
    expect(await scopedCount('canonical_lessons_cache_v2'), 1);
    expect(await scopedCount('canonical_attendance_cache_v2'), 1);
    expect(await scopedCount('canonical_overview_counts_cache_v2'), 1);

    final oldHighlights = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM canonical_overview_highlights_cache_v2 WHERE student_id = '$studentId' AND provider = '$provider' AND window_key = '$scopedWindow' AND snapshot_at = '$snapshotOld'",
        )) ??
        0;
    expect(oldHighlights, 2);

    final newRows = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM canonical_results_cache_v2 WHERE student_id = '$studentId' AND provider = '$provider' AND snapshot_at = '$snapshotNew'",
        )) ??
        0;
    expect(newRows, 0);

    final activeSnapshot = await metaValue(db, '${studentId}_${provider}_active_snapshot_at');
    final refreshStatus = await metaValue(db, '${studentId}_${provider}_last_refresh_status');
    expect(activeSnapshot, snapshotOld);
    expect(refreshStatus, 'success');
  });

  test('PR1 gate: refresh_status recorded for success/degraded/failed; active snapshot published only on success', () async {
    final db = await AppDatabase.open();
    await clearAll(db);
    late HttpServer server;
    var mode = 'success';

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/v1/auth/login') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(authResponse('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v2/profile') {
        if (mode == 'degraded') {
          request.response.statusCode = 503;
          request.response.write(jsonEncode({'error': {'code': 'unavailable'}}));
          await request.response.close();
          return;
        }
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.write(jsonEncode(profileDto(snapshot).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v2/results') {
        if (mode == 'failed') {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'data': {'results': []}}));
          await request.response.close();
          return;
        }
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(resultsDto(snapshot, validAttendance: true).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v2/academic/overview') {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(overviewDto(snapshot).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v1/profile') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(v1Profile('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v1/lessons' || path == '/v1/homework' || path == '/v1/grades') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(v1List()));
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final repo = buildRepo('http://127.0.0.1:${server.port}');

    mode = 'success';
    await repo.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'user_login',
        password: 'user_password',
      ),
    );

    final activeAfterSuccess = await metaValue(db, 'student-1_kundelik_active_snapshot_at');
    expect(activeAfterSuccess.isNotEmpty, isTrue);
    expect(await metaValue(db, 'student-1_kundelik_last_refresh_status'), 'success');

    mode = 'degraded';
    await repo.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'user_login',
        password: 'user_password',
      ),
    );
    expect(await metaValue(db, 'student-1_kundelik_last_refresh_status'), 'degraded');
    expect(await metaValue(db, 'student-1_kundelik_last_refresh_mode'), 'degraded_v1_fallback');
    expect(await metaValue(db, 'student-1_kundelik_active_snapshot_at'), activeAfterSuccess);

    mode = 'failed';
    await expectLater(
      () => repo.login(
        credentials: const DiaryAuthCredentials(
          source: 'dnevnikru',
          login: 'user_login',
          password: 'user_password',
        ),
      ),
      throwsException,
    );
    expect(await metaValue(db, 'student-1_kundelik_last_refresh_status'), 'failed');
    expect(await metaValue(db, 'student-1_kundelik_active_snapshot_at'), activeAfterSuccess);

    await server.close(force: true);
  });

  test('PR1 gate: coalesced refresh real flow performs one v2 request triplet', () async {
    final db = await AppDatabase.open();
    await clearAll(db);

    late HttpServer server;
    var profileCalls = 0;
    var resultsCalls = 0;
    var overviewCalls = 0;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/v1/auth/login') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(authResponse('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v2/profile') {
        profileCalls += 1;
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        await Future<void>.delayed(const Duration(milliseconds: 220));
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(profileDto(snapshot).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v2/results') {
        resultsCalls += 1;
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(resultsDto(snapshot, validAttendance: true).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v2/academic/overview') {
        overviewCalls += 1;
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(overviewDto(snapshot).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v1/profile') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(v1Profile('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v1/lessons' || path == '/v1/homework' || path == '/v1/grades') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(v1List()));
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final repo = buildRepo('http://127.0.0.1:${server.port}');
    final first = repo.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'user_login',
        password: 'user_password',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final second = repo.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'user_login',
        password: 'user_password',
      ),
    );
    await Future.wait([first, second]);
    await server.close(force: true);

    expect(profileCalls, 1);
    expect(resultsCalls, 1);
    expect(overviewCalls, 1);
    expect(await metaValue(db, 'student-1_kundelik_last_refresh_status'), 'success');
  });

  test('PR1 gate: successful v2 refresh does not write into legacy canonical_grades_cache', () async {
    final db = await AppDatabase.open();
    await clearAll(db);

    late HttpServer server;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/v1/auth/login') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(authResponse('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v2/profile') {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(profileDto(snapshot).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v2/results') {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(resultsDto(snapshot, validAttendance: true).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v2/academic/overview') {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(overviewDto(snapshot).toJsonForTest()));
        await request.response.close();
        return;
      }
      if (path == '/v1/profile') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(v1Profile('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v1/lessons' || path == '/v1/homework' || path == '/v1/grades') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(v1List()));
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final repo = buildRepo('http://127.0.0.1:${server.port}');
    await repo.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'user_login',
        password: 'user_password',
      ),
    );

    final legacyGradesCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM canonical_grades_cache',
        )) ??
        0;
    final v2ResultsCount = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM canonical_results_cache_v2 WHERE student_id = 'student-1'",
        )) ??
        0;

    expect(legacyGradesCount, 0);
    expect(v2ResultsCount, greaterThan(0));

    await server.close(force: true);
  });
}

extension on V2ProfileResponse {
  Map<String, dynamic> toJsonForTest() {
    return {
      'data': {
        'window': {
          'provider': window.provider,
          'window_from': window.windowFrom,
          'window_to': window.windowTo,
          'snapshot_at': window.snapshotAt,
          'window_key': window.windowKey,
        },
        'provider_identity': {
          'provider': providerIdentity.provider,
          'provider_account_ref': providerIdentity.providerAccountRef,
          'provider_person_id': providerIdentity.providerPersonId,
          'provider_school_id': providerIdentity.providerSchoolId,
          'provider_group_id': providerIdentity.providerGroupId,
          'student_full_name': providerIdentity.studentFullName,
          'school_name': providerIdentity.schoolName,
          'class_label': providerIdentity.classLabel,
          'class_teacher_full_name': providerIdentity.classTeacherFullName,
        },
        if (localAppProfile != null)
          'local_app_profile': {
            'shift': localAppProfile!.shift,
            'parent_phone_1': localAppProfile!.parentPhone1,
            'parent_phone_2': localAppProfile!.parentPhone2,
          },
      }
    };
  }
}

extension on V2ResultsResponse {
  Map<String, dynamic> toJsonForTest() {
    return {
      'data': {
        'window': {
          'provider': window.provider,
          'window_from': window.windowFrom,
          'window_to': window.windowTo,
          'snapshot_at': window.snapshotAt,
          'window_key': window.windowKey,
        },
        'lessons': lessons
            .map((it) => {
                  'lesson_id': it.lessonId,
                  'provider': it.provider,
                  'provider_lesson_id': it.providerLessonId,
                  'provider_subject_id': it.providerSubjectId,
                  'lesson_date': it.lessonDate,
                  'lesson_number': it.lessonNumber,
                  'subject_name': it.subjectName,
                  'start_time': it.startTime,
                  'end_time': it.endTime,
                  'theme': it.theme,
                  'homework_text': it.homeworkText,
                  'homework_status': it.homeworkStatus,
                })
            .toList(growable: false),
        'results': results
            .map((it) => {
                  'result_id': it.resultId,
                  'provider': it.provider,
                  'result_kind': it.resultKind,
                  'provider_work_id': it.providerWorkId,
                  'provider_mark_id': it.providerMarkId,
                  'provider_subject_id': it.providerSubjectId,
                  'subject_name': it.subjectName,
                  'value_text': it.valueText,
                  'resolved_mood': it.resolvedMood,
                  'recorded_on': it.recordedOn,
                  'source_endpoint': it.sourceEndpoint,
                  'source_mood_raw': it.sourceMoodRaw,
                })
            .toList(growable: false),
        'aggregates': aggregates
            .map((it) => {
                  'aggregate_id': it.aggregateId,
                  'provider': it.provider,
                  'result_kind': it.resultKind,
                  'provider_subject_id': it.providerSubjectId,
                  'subject_name': it.subjectName,
                  'value_text': it.valueText,
                  'resolved_mood': it.resolvedMood,
                  'recorded_on': it.recordedOn,
                  'term_no': it.termNo,
                  'year_label': it.yearLabel,
                })
            .toList(growable: false),
        'attendance': attendance
            .map((it) => {
                  'attendance_id': it.attendanceId,
                  'provider': it.provider,
                  'provider_event_key': it.providerEventKey,
                  'provider_lesson_ref': it.providerLessonRef,
                  'recorded_on': it.recordedOn,
                  'raw_code': it.rawCode,
                  'normalized_status': it.normalizedStatus,
                  'reason': it.reason,
                })
            .toList(growable: false),
      }
    };
  }
}

extension on V2OverviewResponse {
  Map<String, dynamic> toJsonForTest() {
    return {
      'data': {
        'window': {
          'provider': window.provider,
          'window_from': window.windowFrom,
          'window_to': window.windowTo,
          'snapshot_at': window.snapshotAt,
          'window_key': window.windowKey,
        },
        'provider_identity': {
          'provider': providerIdentity.provider,
          'provider_account_ref': providerIdentity.providerAccountRef,
          'provider_person_id': providerIdentity.providerPersonId,
          'provider_school_id': providerIdentity.providerSchoolId,
          'provider_group_id': providerIdentity.providerGroupId,
          'student_full_name': providerIdentity.studentFullName,
          'school_name': providerIdentity.schoolName,
          'class_label': providerIdentity.classLabel,
          'class_teacher_full_name': providerIdentity.classTeacherFullName,
        },
        if (localAppProfile != null)
          'local_app_profile': {
            'shift': localAppProfile!.shift,
            'parent_phone_1': localAppProfile!.parentPhone1,
            'parent_phone_2': localAppProfile!.parentPhone2,
          },
        'counts': {
          'lessons_in_window': counts.lessonsInWindow,
          'results_in_window': counts.resultsInWindow,
          'aggregates_in_window': counts.aggregatesInWindow,
          'attendance_alerts': counts.attendanceAlerts,
        },
        'highlights': highlights.toJson(),
      }
    };
  }
}
