import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/anti_bot/connector_http_client.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/contracts/errors.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/contracts/models.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/diagnostics/connector_diagnostics.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/mappers/canonical_bundle_mapper.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/raw_payload/raw_payload_repository.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/session/connector_session_store.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/source_adapters/kundelik/kundelik_connector.dart';

class _FakeHttpClient implements ConnectorHttpClient {
  final Map<String, List<ConnectorHttpResponse>> _responses =
      <String, List<ConnectorHttpResponse>>{};
  final Map<String, Map<String, dynamic>?> lastQueryByUrl =
      <String, Map<String, dynamic>?>{};

  void enqueueGet(String url, ConnectorHttpResponse response) {
    _responses
        .putIfAbsent('GET:$url', () => <ConnectorHttpResponse>[])
        .add(response);
  }

  void enqueuePost(String url, ConnectorHttpResponse response) {
    _responses
        .putIfAbsent('POST:$url', () => <ConnectorHttpResponse>[])
        .add(response);
  }

  @override
  Future<ConnectorHttpResponse> get(
    String url, {
    Map<String, dynamic>? query,
  }) async {
    lastQueryByUrl[url] =
        query == null ? null : Map<String, dynamic>.from(query);
    return _dequeue('GET:$url');
  }

  @override
  Future<ConnectorHttpResponse> post(
    String url, {
    Object? data,
  }) async {
    return _dequeue('POST:$url');
  }

  ConnectorHttpResponse _dequeue(String key) {
    final queue = _responses[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('No fake response queued for $key');
    }
    return queue.removeAt(0);
  }
}

void main() {
  test(
      'kundelik connector builds canonical bundle from deterministic responses',
      () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
        var profile = {"firstName":"Aliya","lastName":"S.","className":"6B","schoolName":"Kundi School"};
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: '',
        headers: {
          'set-cookie': ['sessionid=abc123; path=/']
        },
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/diary',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {
          'lessons': [
            {
              'id': 'l1',
              'date': '2026-03-30',
              'lessonNumber': 1,
              'subjectName': 'Math',
              'topic': 'Linear equations',
              'homework': 'Solve 1-10',
              'requiresPhoto': true,
              'grades': [
                {'id': 'g1', 'value': '5', 'type': 'regular'}
              ],
            }
          ],
        },
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/userfeed/person/123/school/77/group/5/links',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {
          'context': {'userId': '123'}
        },
      ),
    );
    client.enqueuePost(
      'https://kundelik.kz/chat/api/auth/credentials',
      const ConnectorHttpResponse(statusCode: 200, data: {'ok': true}),
    );
    client.enqueueGet(
      'https://kundelik.kz/chat/api/closecontacts',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {
          'contacts': [
            {
              'schoolName': 'Kundi School',
              'classTeacher': 'user_42@xmpp.kundelik.kz',
              'groups': {
                '5': {'name': '6B'}
              },
              'members': [
                {'personId': '123', 'jid': 'user_123@xmpp.kundelik.kz'}
              ],
            }
          ],
        },
      ),
    );
    client.enqueuePost(
      'https://kundelik.kz/chat/api/enrich',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {
          'data': {
            'user_123@xmpp.kundelik.kz': {'name': 'Aliya Student'},
            'user_42@xmpp.kundelik.kz': {'name': 'Teacher Name'},
          },
        },
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/school/77/person/123',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {
          'periodId': '2395845913549013991',
          'dateFinish': '1766707200',
          'subjects': [
            {
              'id': 'sub-1',
              'name': 'Math',
              'works': [
                {
                  'workId': 'work-1',
                  'date': '1762905600',
                  'lessonNumber': 1,
                  'marks': [
                    {'id': 'mark-1', 'value': '5', 'mood': 'Good'}
                  ],
                }
              ],
              'summativeMarks': [
                {
                  'markId': 'sor-1',
                  'sectionId': 'sec-1',
                  'value': 9,
                  'maxValue': 10,
                  'type': 'СОР',
                  'mood': 'Average',
                }
              ],
              'finalWorks': [
                {
                  'workId': 'term-1',
                  'periodNumber': 1,
                  'type': 'Period',
                  'periodId': '2395845913549013991',
                  'marks': [
                    {'id': 'term-mark-1', 'value': '4', 'mood': 'Average'}
                  ],
                }
              ],
              'lessonLogEntries': [
                {
                  'id': 'att-1',
                  'value': 'Н',
                  'fullName': 'Absence',
                  'date': '1763683200',
                  'lessonId': 'l1',
                }
              ],
            }
          ],
        },
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/school/77/person/123',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {'subjects': <dynamic>[]},
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/final/school/77/person/123',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {
          'periodId': 'final',
          'dateFinish': '1773792000',
          'subjects': [
            {
              'id': 'sub-1',
              'name': 'Math',
              'works': [],
              'summativeMarks': [],
              'finalWorks': [
                {
                  'workId': 'term-2',
                  'periodNumber': 2,
                  'type': 'Period',
                  'periodId': '2395845913549013992',
                  'marks': [
                    {'id': 'term-mark-2', 'value': '4', 'mood': 'Good'}
                  ],
                }
              ],
              'lessonLogEntries': [],
            }
          ],
        },
      ),
    );

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );

    await connector.authenticate(
      const DiaryAuthCredentials(
          source: 'kundelik', login: 'student', password: 'pass'),
    );
    final bundle = await connector.buildCanonicalBundle(
      DiarySyncRequest(
        idempotencyKey: 'bundle-key-1234',
        from: DateTime.utc(2026, 3, 30),
        to: DateTime.utc(2026, 4, 5),
      ),
    );

    expect(bundle.source, 'kundelik');
    expect(bundle.sourceIds['person_id'], '123');
    expect(bundle.profile.firstName, 'Aliya');
    expect(bundle.profile.classTeacherFullName, 'Teacher Name');
    expect(bundle.lessons.length, 1);
    expect(bundle.results.where((it) => it.resultKind == 'regular').length, 1);
    expect(bundle.results.where((it) => it.resultKind == 'sor').length, 1);
    expect(bundle.aggregates.where((it) => it.resultKind == 'term').length, 2);
    expect(bundle.attendance, hasLength(1));
  });

  test('kundelik connector rejects invalid sync window', () async {
    final connector = KundelikConnector(
      client: _FakeHttpClient(),
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );

    await expectLater(
      connector.buildCanonicalBundle(
        DiarySyncRequest(
          idempotencyKey: 'bundle-key-1234',
          from: DateTime.utc(2026, 4, 5),
          to: DateTime.utc(2026, 4, 4),
        ),
      ),
      throwsA(isA<ConnectorException>()),
    );
  });

  test('kundelik connector requires authentication first', () async {
    final connector = KundelikConnector(
      client: _FakeHttpClient(),
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );

    await expectLater(
      connector.fetchProfile(),
      throwsA(isA<ConnectorException>()),
    );
  });

  test('session store expires old sessions', () {
    final store = ConnectorSessionStore(ttl: const Duration(seconds: 1));
    store.save(
      ConnectorSession(
        source: 'kundelik',
        login: 'student',
        cookies: const <String, String>{},
        createdAt: DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
      ),
    );
    expect(store.load(), isNull);
  });

  test('kundelik connector allows auth continuation after marks verification',
      () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );

    await connector.authenticate(
      const DiaryAuthCredentials(
        source: 'kundelik',
        login: 'student',
        password: 'pass',
      ),
    );

    final profile = await connector.fetchProfile();
    expect(profile.firstName, isNotEmpty);
  });

  test('kundelik connector retries transient lessons failure', () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: '',
        headers: {
          'set-cookie': ['sessionid=retry123; path=/']
        },
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/diary',
      const ConnectorHttpResponse(statusCode: 500, data: {'error': 'retry'}),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/diary',
      const ConnectorHttpResponse(statusCode: 200, data: {'lessons': []}),
    );

    final diagnostics = ConnectorDiagnostics();
    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: diagnostics,
      mapper: const CanonicalBundleMapper(),
    );

    await connector.authenticate(
      const DiaryAuthCredentials(
          source: 'kundelik', login: 'student', password: 'pass'),
    );

    final lessons = await connector.fetchLessons(
      DateTimeRange(
        start: DateTime.utc(2026, 3, 30),
        end: DateTime.utc(2026, 4, 1),
      ),
    );

    expect(lessons, isEmpty);
    final events = diagnostics.exportEvents();
    expect(
      events.any((event) => event.code == 'kundelik_retry_status'),
      isTrue,
    );
  });

  test('kundelik connector rejects a partial academic period fetch', () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
        var periodId = "2395845913549013991";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/final/school/77/person/123',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {'subjects': <dynamic>[]},
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/school/77/person/123',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {'subjects': <dynamic>[]},
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/school/77/person/123',
      const ConnectorHttpResponse(
        statusCode: 401,
        data: {'error': 'period unavailable'},
      ),
    );

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );
    await connector.authenticate(
      const DiaryAuthCredentials(
        source: 'kundelik',
        login: 'student',
        password: 'pass',
      ),
    );

    await expectLater(
      connector.fetchGrades(
        DateTimeRange(
          start: DateTime.utc(2026, 3, 30),
          end: DateTime.utc(2026, 4, 5),
        ),
      ),
      throwsA(isA<ConnectorException>()),
    );
  });

  test('kundelik connector sends expected diary query shape', () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/diary',
      const ConnectorHttpResponse(statusCode: 200, data: {'lessons': []}),
    );

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );
    await connector.authenticate(
      const DiaryAuthCredentials(
        source: 'kundelik',
        login: 'student',
        password: 'pass',
      ),
    );

    await connector.fetchLessons(
      DateTimeRange(
        start: DateTime.utc(2026, 3, 30),
        end: DateTime.utc(2026, 4, 1),
      ),
    );

    final query =
        client.lastQueryByUrl['https://kundelik.kz/api/v2/marks/diary'];
    expect(query, isNotNull);
    expect((query!['personId'] ?? '').toString().isNotEmpty, isTrue);
    expect((query['schoolId'] ?? '').toString().isNotEmpty, isTrue);
    expect(query.containsKey('startDate'), isTrue);
    expect(query.containsKey('finishDate'), isTrue);
    expect(query.containsKey('timestamp'), isTrue);
  });

  test('kundelik connector fails auth when /marks redirects to login',
      () async {
    final client = _FakeHttpClient();

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: '<html>redirect</html>',
        effectiveUri: 'https://login.kundelik.kz/login?needRedirect=True',
      ),
    );

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );

    await expectLater(
      connector.authenticate(
        const DiaryAuthCredentials(
          source: 'kundelik',
          login: 'student',
          password: 'pass',
        ),
      ),
      throwsA(
        isA<ConnectorException>().having(
          (exception) => exception.code,
          'code',
          'kundelik_auth_failed',
        ),
      ),
    );
  });

  test('kundelik connector fails auth when /marks returns login page html',
      () async {
    final client = _FakeHttpClient();

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(
        statusCode: 200,
        data:
            '<html><form action="https://login.kundelik.kz/login"><input name="password"/></form></html>',
        effectiveUri: 'https://kundelik.kz/marks',
      ),
    );

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );

    await expectLater(
      connector.authenticate(
        const DiaryAuthCredentials(
          source: 'kundelik',
          login: 'student',
          password: 'pass',
        ),
      ),
      throwsA(
        isA<ConnectorException>()
            .having(
                (exception) => exception.code, 'code', 'kundelik_auth_failed')
            .having(
              (exception) => exception.details['marks_outcome'],
              'marks_outcome',
              'loginHtmlUnder200',
            ),
      ),
    );
  });

  test('kundelik connector emits redacted live auth diagnostics', () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: '',
        effectiveUri:
            'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      ),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: '',
        effectiveUri: 'https://kundelik.kz/',
        headers: {
          'set-cookie': ['sessionid=abc123; Path=/; Domain=.kundelik.kz']
        },
      ),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: marksHtml,
        effectiveUri: 'https://kundelik.kz/marks',
      ),
    );

    final diagnostics = ConnectorDiagnostics();
    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: diagnostics,
      mapper: const CanonicalBundleMapper(),
    );

    await connector.authenticate(
      const DiaryAuthCredentials(
        source: 'kundelik',
        login: 'student_login',
        password: 'very-secret-password',
      ),
    );

    final events = diagnostics.exportEvents();
    final submitEvent = events.firstWhere(
      (event) => event.code == 'kundelik_auth_submit_result',
    );
    expect(submitEvent.details['login'], 'st***');
    expect(submitEvent.details['cookie_count'], 1);
    expect(
      submitEvent.details['cookie_names'],
      contains('sessionid'),
    );
    expect(
      submitEvent.details.toString().toLowerCase().contains('password'),
      isFalse,
    );

    final marksEvent = events.firstWhere(
      (event) => event.code == 'kundelik_auth_verify_marks_result',
    );
    expect(marksEvent.details['marks_outcome'], 'marksPage');
    expect(marksEvent.details['redirected_to_login'], isFalse);
  });

  test('kundelik connector classifies diary unauthorized response', () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/diary',
      const ConnectorHttpResponse(
        statusCode: 401,
        data: {'error': 'unauthorized'},
        effectiveUri: 'https://kundelik.kz/api/v2/marks/diary',
      ),
    );

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );
    await connector.authenticate(
      const DiaryAuthCredentials(
        source: 'kundelik',
        login: 'student',
        password: 'pass',
      ),
    );

    await expectLater(
      connector.fetchLessons(
        DateTimeRange(
          start: DateTime.utc(2026, 3, 30),
          end: DateTime.utc(2026, 4, 1),
        ),
      ),
      throwsA(
        isA<ConnectorException>()
            .having((exception) => exception.code, 'code',
                'kundelik_fetch_lessons_failed')
            .having(
              (exception) => exception.details['outcome'],
              'outcome',
              'unauthorized',
            ),
      ),
    );
  });

  test('kundelik connector classifies diary redirect to login under 200',
      () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/diary',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: '<html>https://login.kundelik.kz/login</html>',
        effectiveUri: 'https://login.kundelik.kz/login?needRedirect=True',
      ),
    );

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );
    await connector.authenticate(
      const DiaryAuthCredentials(
        source: 'kundelik',
        login: 'student',
        password: 'pass',
      ),
    );

    await expectLater(
      connector.fetchLessons(
        DateTimeRange(
          start: DateTime.utc(2026, 3, 30),
          end: DateTime.utc(2026, 4, 1),
        ),
      ),
      throwsA(
        isA<ConnectorException>()
            .having((exception) => exception.code, 'code',
                'kundelik_fetch_lessons_failed')
            .having(
              (exception) => exception.details['outcome'],
              'outcome',
              'redirectedToLogin',
            ),
      ),
    );
  });

  test('kundelik connector reports request-stage failure for diary transport',
      () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    // no diary response queued on purpose to trigger request-stage failure

    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: ConnectorDiagnostics(),
      mapper: const CanonicalBundleMapper(),
    );
    await connector.authenticate(
      const DiaryAuthCredentials(
        source: 'kundelik',
        login: 'student',
        password: 'pass',
      ),
    );

    await expectLater(
      connector.fetchLessons(
        DateTimeRange(
          start: DateTime.utc(2026, 3, 30),
          end: DateTime.utc(2026, 4, 1),
        ),
      ),
      throwsA(
        isA<ConnectorException>().having(
          (exception) => exception.code,
          'code',
          'kundelik_fetch_lessons_request_failed',
        ),
      ),
    );
  });

  test('kundelik connector emits diary payload shape diagnostics', () async {
    final client = _FakeHttpClient();
    const marksHtml = '''
      <script>
        var personId = "123";
        var schoolId = "77";
        var groupId = "5";
      </script>
    ''';

    client.enqueueGet(
      'https://login.kundelik.kz/login?needRedirect=True&loginType=Basic',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueuePost(
      'https://login.kundelik.kz/login',
      const ConnectorHttpResponse(statusCode: 200, data: ''),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/marks',
      const ConnectorHttpResponse(statusCode: 200, data: marksHtml),
    );
    client.enqueueGet(
      'https://kundelik.kz/api/v2/marks/diary',
      const ConnectorHttpResponse(
        statusCode: 200,
        data: {
          'days': [
            {
              'date': '2026-03-30',
              'lessons': [
                {'subjectName': 'Math', 'date': '2026-03-30', 'lessonNumber': 1}
              ],
            }
          ],
        },
      ),
    );

    final diagnostics = ConnectorDiagnostics();
    final connector = KundelikConnector(
      client: client,
      sessionStore: ConnectorSessionStore(),
      rawPayloadRepository: RawPayloadRepository(),
      diagnostics: diagnostics,
      mapper: const CanonicalBundleMapper(),
    );
    await connector.authenticate(
      const DiaryAuthCredentials(
        source: 'kundelik',
        login: 'student',
        password: 'pass',
      ),
    );
    await connector.fetchLessons(
      DateTimeRange(
        start: DateTime.utc(2026, 3, 30),
        end: DateTime.utc(2026, 4, 1),
      ),
    );

    final diaryEvent = diagnostics.exportEvents().firstWhere(
          (event) => event.code == 'kundelik_fetch_lessons_result',
        );
    expect(diaryEvent.details['has_days'], isTrue);
    expect(diaryEvent.details['has_lessons'], isFalse);
  });
}
