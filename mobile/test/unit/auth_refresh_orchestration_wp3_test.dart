import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/app_database.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/core/network/read_source_policy.dart';
import 'package:kundi_mobile/core/db/sync_queue_repository.dart';
import 'package:kundi_mobile/features/auth/data/auth_repository_impl.dart';
import 'package:kundi_mobile/features/auth/data/academic_year_window.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/connector_runtime.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/contracts/diary_connector.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/contracts/errors.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/ingest_uploader.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/sync_orchestrator.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/sync_queue_service.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/contracts/models.dart';
import 'package:kundi_mobile/core/db/canonical_cache_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../test_support/fake_secure_storage_service.dart';

class _FakeQueueGateway implements SyncQueueGateway {
  @override
  Future<List<SyncQueueItem>> listReady() async => const <SyncQueueItem>[];

  @override
  Future<void> markFailure(
    String requestID,
    SyncFailure failure,
    int attempts,
  ) async {}

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

class _FakeKundelikConnector implements DiaryConnector {
  _FakeKundelikConnector({this.bundleError});

  final Object? bundleError;
  int authenticateCalls = 0;
  int bundleCalls = 0;

  @override
  Future<void> authenticate(DiaryAuthCredentials credentials) async {
    authenticateCalls += 1;
    expect(credentials.source, 'kundelik');
    expect(credentials.login, 'saved-login');
    expect(credentials.password, 'saved-password');
  }

  @override
  Future<CanonicalBundle> buildCanonicalBundle(
    DiarySyncRequest syncRequest,
  ) async {
    bundleCalls += 1;
    final error = bundleError;
    if (error != null) {
      throw error;
    }
    return CanonicalBundle(
      source: 'kundelik',
      sourceAccount: 'account-1',
      idempotencyKey: syncRequest.idempotencyKey,
      syncedAt: DateTime.now().toUtc(),
      sourceIds: const {
        'person_id': 'person-1',
        'school_id': 'school-1',
        'group_id': 'group-1',
      },
      profile: const SourceProfile(
        firstName: 'Student',
        lastName: 'One',
        gradeLevel: 7,
        classLabel: '7zh',
        schoolName: 'School',
        classTeacherFullName: 'Teacher',
      ),
      lessons: const [
        SourceLesson(
          sourceLessonKey: 'lesson-1',
          date: '2026-09-08',
          lessonNumber: 1,
          subjectName: 'Math',
          lessonPlace: '101',
          startTime: '08:00',
          endTime: '08:45',
          topicTitle: 'Topic',
          homeworkText: 'Exercise 1',
          requiresPhoto: false,
          grades: [],
        ),
      ],
      attendance: const [],
    );
  }

  @override
  Future<Map<String, String>> bootstrapSourceIds() async => const {};

  @override
  Future<List<SourceGrade>> fetchGrades(DateTimeRange weekWindow) async =>
      const [];

  @override
  Future<List<SourceLesson>> fetchHomework(DateTimeRange window) async =>
      const [];

  @override
  Future<List<SourceLesson>> fetchLessons(DateTimeRange window) async =>
      const [];

  @override
  Future<SourceProfile> fetchProfile() async => const SourceProfile(
        firstName: 'Student',
        lastName: 'One',
        gradeLevel: 7,
        classLabel: '7zh',
        schoolName: 'School',
        classTeacherFullName: 'Teacher',
      );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.setTestDbNameOverride('kundi_mobile_wp3_refresh.db');
  });

  tearDownAll(() {
    AppDatabase.setTestDbNameOverride(null);
  });

  Future<void> clearCacheTables() async {
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
    await db.delete('canonical_lessons_cache');
    await db.delete('canonical_homework_cache');
    await db.delete('canonical_grades_cache');
  }

  AuthRepositoryImpl buildRepository(
    String baseUrl, {
    FakeSecureStorageService? secureStorage,
    ConnectorRuntime? connectorRuntime,
  }) {
    return AuthRepositoryImpl(
      apiClient: ApiClient(baseUrl: baseUrl),
      secureStorage: secureStorage ?? FakeSecureStorageService(),
      connectorRuntime: connectorRuntime ?? ConnectorRuntime(),
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

  Future<Map<String, String>> readRefreshMetadata(String studentId) async {
    final db = await AppDatabase.open();
    final rows = await db.query('canonical_read_mode_metadata');
    final out = <String, String>{};
    for (final row in rows) {
      final key = (row['meta_key'] ?? '').toString();
      final value = (row['meta_value'] ?? '').toString();
      out[key] = value;
    }
    return <String, String>{
      'active_snapshot_at':
          out['${studentId}_kundelik_active_snapshot_at'] ?? '',
      'active_read_mode': out['${studentId}_kundelik_active_read_mode'] ?? '',
      'last_refresh_status':
          out['${studentId}_kundelik_last_refresh_status'] ?? '',
      'last_refresh_mode': out['${studentId}_kundelik_last_refresh_mode'] ?? '',
    };
  }

  Map<String, dynamic> _authLoginResponse(String studentId) {
    return {
      'data': {
        'student_id': studentId,
        'access_token': 'token-$studentId',
        'refresh_token': 'refresh-$studentId',
        'expires_at': '2026-12-31T00:00:00Z',
      }
    };
  }

  Map<String, dynamic> _v2ProfilePayload(String snapshotAt) {
    return {
      'data': {
        'window': {
          'provider': 'kundelik',
          'window_from': '2026-03-01',
          'window_to': '2026-03-31',
          'snapshot_at': snapshotAt,
          'window_key': 'kundelik:2026-03-01:2026-03-31',
        },
        'provider_identity': {
          'provider': 'kundelik',
          'provider_account_ref': 'acc-1',
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
      }
    };
  }

  Map<String, dynamic> _v2ResultsPayload(String snapshotAt) {
    return {
      'data': {
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
            'theme': 'Linear equations',
            'homework_text': 'Solve 1-10',
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
          }
        ],
        'attendance': [
          {
            'attendance_id': 'att1',
            'provider': 'kundelik',
            'provider_event_key': 'evt1',
            'provider_lesson_ref': 'pl1',
            'recorded_on': '2026-03-10',
            'raw_code': 'N',
            'normalized_status': 'absent',
            'reason': '',
          }
        ],
      }
    };
  }

  Map<String, dynamic> _v2OverviewPayload(String snapshotAt) {
    return {
      'data': {
        'window': {
          'provider': 'kundelik',
          'window_from': '2026-03-01',
          'window_to': '2026-03-31',
          'snapshot_at': snapshotAt,
          'window_key': 'kundelik:2026-03-01:2026-03-31',
        },
        'provider_identity': {
          'provider': 'kundelik',
          'provider_account_ref': 'acc-1',
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
            }
          ],
          'upcoming_lessons': [
            {
              'lesson_id': 'l1',
              'lesson_date': '2026-03-20',
              'lesson_number': 1,
              'subject_name': 'Math',
              'theme': 'Quadratic equations',
              'homework_text': 'Solve 11-20',
            }
          ],
        },
      }
    };
  }

  Map<String, dynamic> _v1ListPayload() => {
        'data': {'items': <dynamic>[]}
      };

  Map<String, dynamic> _v1ProfilePayload(String studentId) => {
        'data': {
          'student_id': studentId,
          'first_name': 'Student',
          'last_name': 'One',
          'grade_level': 7,
          'class_label': '7zh',
          'school_name': 'School',
        }
      };

  test(
      'WP3: one snapshot_at is passed to all v2 endpoints and success publishes active snapshot',
      () async {
    await clearCacheTables();
    final snapshotsSeen = <String>[];
    final pathsSeen = <String>[];
    final windowFromSeen = <String>[];
    final windowToSeen = <String>[];
    late HttpServer server;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/v1/auth/login' && request.method == 'POST') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_authLoginResponse('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v2/profile' ||
          path == '/v2/results' ||
          path == '/v2/academic/overview') {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        windowFromSeen.add(request.uri.queryParameters['window_from'] ?? '');
        windowToSeen.add(request.uri.queryParameters['window_to'] ?? '');
        snapshotsSeen.add(snapshot);
        pathsSeen.add(path);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        if (path == '/v2/profile') {
          request.response.write(jsonEncode(_v2ProfilePayload(snapshot)));
        } else if (path == '/v2/results') {
          request.response.write(jsonEncode(_v2ResultsPayload(snapshot)));
        } else {
          request.response.write(jsonEncode(_v2OverviewPayload(snapshot)));
        }
        await request.response.close();
        return;
      }
      if (path == '/v1/profile') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v1ProfilePayload('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v1/lessons' ||
          path == '/v1/homework' ||
          path == '/v1/grades') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v1ListPayload()));
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final repository = buildRepository('http://127.0.0.1:${server.port}');
    await repository.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'student_login',
        password: 'student_password',
      ),
    );
    await server.close(force: true);

    expect(
        pathsSeen,
        containsAll(<String>[
          '/v2/profile',
          '/v2/results',
          '/v2/academic/overview',
        ]));
    final nonEmptySnapshots =
        snapshotsSeen.where((item) => item.isNotEmpty).toList();
    expect(nonEmptySnapshots.length, 3);
    expect(nonEmptySnapshots.toSet().length, 1);
    final expectedWindow = AcademicYearWindow.forNowUtc(DateTime.now().toUtc());
    expect(windowFromSeen.toSet(), {expectedWindow.windowFrom});
    expect(windowToSeen.toSet(), {expectedWindow.windowTo});

    final metadata = await readRefreshMetadata('student-1');
    expect(metadata['active_snapshot_at'], nonEmptySnapshots.first);
    expect(metadata['active_read_mode'], 'v2');
    expect(metadata['last_refresh_status'], 'success');
    expect(metadata['last_refresh_mode'], 'v2');
  });

  test(
      'WP3: degraded fallback records status but does not publish new active v2 snapshot',
      () async {
    await clearCacheTables();
    late HttpServer server;
    var loginCount = 0;
    var firstSnapshot = '';

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/v1/auth/login' && request.method == 'POST') {
        loginCount += 1;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_authLoginResponse('student-1')));
        await request.response.close();
        return;
      }

      if (loginCount == 1 &&
          (path == '/v2/profile' ||
              path == '/v2/results' ||
              path == '/v2/academic/overview')) {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        firstSnapshot = snapshot;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        if (path == '/v2/profile') {
          request.response.write(jsonEncode(_v2ProfilePayload(snapshot)));
        } else if (path == '/v2/results') {
          request.response.write(jsonEncode(_v2ResultsPayload(snapshot)));
        } else {
          request.response.write(jsonEncode(_v2OverviewPayload(snapshot)));
        }
        await request.response.close();
        return;
      }

      if (loginCount >= 2 && path == '/v2/profile') {
        request.response.statusCode = 503;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'code': 'unavailable'}
        }));
        await request.response.close();
        return;
      }

      if (path == '/v1/profile') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v1ProfilePayload('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v1/lessons' ||
          path == '/v1/homework' ||
          path == '/v1/grades') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v1ListPayload()));
        await request.response.close();
        return;
      }

      request.response.statusCode = 404;
      await request.response.close();
    });

    final repository = buildRepository('http://127.0.0.1:${server.port}');

    await repository.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'student_login',
        password: 'student_password',
      ),
    );

    await repository.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'student_login',
        password: 'student_password',
      ),
    );

    await server.close(force: true);

    final metadata = await readRefreshMetadata('student-1');
    expect(firstSnapshot.isNotEmpty, isTrue);
    expect(metadata['active_snapshot_at'], firstSnapshot);
    expect(metadata['active_read_mode'], 'v2');
    expect(metadata['last_refresh_status'], 'degraded');
    expect(metadata['last_refresh_mode'], 'degraded_v1_fallback');
  });

  test(
      'WP3: failed refresh records failed status and keeps active snapshot pointer unchanged',
      () async {
    await clearCacheTables();
    late HttpServer server;
    var loginCount = 0;
    var firstSnapshot = '';

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/v1/auth/login' && request.method == 'POST') {
        loginCount += 1;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_authLoginResponse('student-1')));
        await request.response.close();
        return;
      }

      if (loginCount == 1 &&
          (path == '/v2/profile' ||
              path == '/v2/results' ||
              path == '/v2/academic/overview')) {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        firstSnapshot = snapshot;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        if (path == '/v2/profile') {
          request.response.write(jsonEncode(_v2ProfilePayload(snapshot)));
        } else if (path == '/v2/results') {
          request.response.write(jsonEncode(_v2ResultsPayload(snapshot)));
        } else {
          request.response.write(jsonEncode(_v2OverviewPayload(snapshot)));
        }
        await request.response.close();
        return;
      }

      if (loginCount >= 2 && path == '/v2/profile') {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v2ProfilePayload(snapshot)));
        await request.response.close();
        return;
      }
      if (loginCount >= 2 && path == '/v2/results') {
        // schema mismatch, fallback is not allowed
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {'results': []}
        }));
        await request.response.close();
        return;
      }
      if (loginCount >= 2 && path == '/v2/academic/overview') {
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v2OverviewPayload(snapshot)));
        await request.response.close();
        return;
      }

      if (path == '/v1/profile') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v1ProfilePayload('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v1/lessons' ||
          path == '/v1/homework' ||
          path == '/v1/grades') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v1ListPayload()));
        await request.response.close();
        return;
      }

      request.response.statusCode = 404;
      await request.response.close();
    });

    final repository = buildRepository('http://127.0.0.1:${server.port}');

    await repository.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'student_login',
        password: 'student_password',
      ),
    );

    await expectLater(
      () => repository.login(
        credentials: const DiaryAuthCredentials(
          source: 'dnevnikru',
          login: 'student_login',
          password: 'student_password',
        ),
      ),
      throwsException,
    );

    await server.close(force: true);

    final metadata = await readRefreshMetadata('student-1');
    expect(firstSnapshot.isNotEmpty, isTrue);
    expect(metadata['active_snapshot_at'], firstSnapshot);
    expect(metadata['active_read_mode'], 'v2');
    expect(metadata['last_refresh_status'], 'failed');
  });

  test('WP3: coalesced refresh joins in-flight in real login refresh flow',
      () async {
    await clearCacheTables();
    late HttpServer server;
    var v2ProfileCalls = 0;
    var v2ResultsCalls = 0;
    var v2OverviewCalls = 0;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/v1/auth/login' && request.method == 'POST') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_authLoginResponse('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v2/profile') {
        v2ProfileCalls += 1;
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        await Future<void>.delayed(const Duration(milliseconds: 250));
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v2ProfilePayload(snapshot)));
        await request.response.close();
        return;
      }
      if (path == '/v2/results') {
        v2ResultsCalls += 1;
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v2ResultsPayload(snapshot)));
        await request.response.close();
        return;
      }
      if (path == '/v2/academic/overview') {
        v2OverviewCalls += 1;
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v2OverviewPayload(snapshot)));
        await request.response.close();
        return;
      }

      if (path == '/v1/profile') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v1ProfilePayload('student-1')));
        await request.response.close();
        return;
      }
      if (path == '/v1/lessons' ||
          path == '/v1/homework' ||
          path == '/v1/grades') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_v1ListPayload()));
        await request.response.close();
        return;
      }

      request.response.statusCode = 404;
      await request.response.close();
    });

    final repository = buildRepository('http://127.0.0.1:${server.port}');

    final first = repository.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'student_login',
        password: 'student_password',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final second = repository.login(
      credentials: const DiaryAuthCredentials(
        source: 'dnevnikru',
        login: 'student_login',
        password: 'student_password',
      ),
    );

    await Future.wait([first, second]);
    await server.close(force: true);

    expect(v2ProfileCalls, 1);
    expect(v2ResultsCalls, 1);
    expect(v2OverviewCalls, 1);
  });

  test(
      'student pull pipeline refreshes expired session, ingests once, and publishes one typed-v2 snapshot',
      () async {
    await clearCacheTables();
    final secureStorage = FakeSecureStorageService();
    await secureStorage.saveDiaryCredentials(
      source: 'kundelik',
      login: 'saved-login',
      password: 'saved-password',
    );
    final connector = _FakeKundelikConnector();
    var refreshCalls = 0;
    var ingestCalls = 0;
    var profileCalls = 0;
    var resultsCalls = 0;
    var overviewCalls = 0;
    final snapshots = <String>[];

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/v1/auth/refresh') {
        refreshCalls += 1;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'student_id': 'student-1',
            'access_token': 'refreshed-token',
            'refresh_token': 'refreshed-refresh-token',
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          }
        }));
        await request.response.close();
        return;
      }
      if (path == '/v2/ingest/bundle') {
        ingestCalls += 1;
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer refreshed-token');
        await utf8.decoder.bind(request).join();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {'accepted': true}
        }));
        await request.response.close();
        return;
      }
      if (path == '/v2/profile' ||
          path == '/v2/results' ||
          path == '/v2/academic/overview') {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer refreshed-token');
        final snapshot = request.uri.queryParameters['snapshot_at'] ?? '';
        snapshots.add(snapshot);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        if (path == '/v2/profile') {
          profileCalls += 1;
          await Future<void>.delayed(const Duration(milliseconds: 120));
          request.response.write(jsonEncode(_v2ProfilePayload(snapshot)));
        } else if (path == '/v2/results') {
          resultsCalls += 1;
          request.response.write(jsonEncode(_v2ResultsPayload(snapshot)));
        } else {
          overviewCalls += 1;
          request.response.write(jsonEncode(_v2OverviewPayload(snapshot)));
        }
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final repository = buildRepository(
      'http://127.0.0.1:${server.port}',
      secureStorage: secureStorage,
      connectorRuntime: ConnectorRuntime(
        connectorFactory: (_) => connector,
      ),
    );
    final expiredSession = AuthSession(
      studentId: 'student-1',
      accessToken: 'expired-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );

    final first = repository.refreshAuthenticatedStudent(expiredSession);
    final second = repository.refreshAuthenticatedStudent(expiredSession);
    final results = await Future.wait([first, second]);
    await server.close(force: true);

    expect(refreshCalls, 1);
    expect(connector.authenticateCalls, 1);
    expect(connector.bundleCalls, 1);
    expect(ingestCalls, 1);
    expect(profileCalls, 1);
    expect(resultsCalls, 1);
    expect(overviewCalls, 1);
    expect(snapshots.where((value) => value.isNotEmpty).toSet().length, 1);
    expect(results[0].snapshotAt, results[1].snapshotAt);
    expect(results[0].session.accessToken, 'refreshed-token');
    expect(results[0].readMode, 'v2');

    final metadata = await readRefreshMetadata('student-1');
    expect(metadata['active_snapshot_at'], results[0].snapshotAt);
    expect(metadata['last_refresh_status'], 'success');
  });

  test(
      'provider fetch failure aborts student refresh before an empty bundle can be ingested',
      () async {
    await clearCacheTables();
    final secureStorage = FakeSecureStorageService();
    await secureStorage.saveDiaryCredentials(
      source: 'kundelik',
      login: 'saved-login',
      password: 'saved-password',
    );
    final connector = _FakeKundelikConnector(
      bundleError: const ConnectorException(
        code: 'kundelik_fetch_period_marks_failed',
        message: 'required provider fetch failed',
      ),
    );
    var backendCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      backendCalls += 1;
      request.response.statusCode = 500;
      await request.response.close();
    });

    final repository = buildRepository(
      'http://127.0.0.1:${server.port}',
      secureStorage: secureStorage,
      connectorRuntime: ConnectorRuntime(
        connectorFactory: (_) => connector,
      ),
    );
    final activeSession = AuthSession(
      studentId: 'student-1',
      accessToken: 'active-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    await expectLater(
      () => repository.refreshAuthenticatedStudent(activeSession),
      throwsA(
        isA<ConnectorException>().having(
          (error) => error.code,
          'code',
          'kundelik_fetch_period_marks_failed',
        ),
      ),
    );
    await server.close(force: true);

    expect(connector.authenticateCalls, 1);
    expect(connector.bundleCalls, 1);
    expect(backendCalls, 0,
        reason: 'provider failure must not reach ingest or typed-v2 reads');
  });
}
