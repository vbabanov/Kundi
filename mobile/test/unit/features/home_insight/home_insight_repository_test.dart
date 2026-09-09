import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/features/home_insight/data/home_insight_repository_impl.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('requests an authenticated localized daily insight', () async {
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.path, '/v1/home/insight');
      expect(request.uri.queryParameters['locale'], 'kk');
      expect(request.headers.value('authorization'), 'Bearer access');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'data': {
            'text': 'Бір түсінікті қадамнан баста.',
            'kind': 'study_tip',
            'locale': 'kk',
            'content_id': 'middle_step_v1',
            'catalog_version': 1,
            'grade_band': 'middle',
            'rephrased': false,
          },
        }));
      await request.response.close();
    });
    final repository = HomeInsightRepositoryImpl(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
      readSession: () => AuthSession(
        studentId: 'student',
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2026, 10),
      ),
    );

    final insight = await repository.getInsight(locale: 'kk');

    expect(insight.text, 'Бір түсінікті қадамнан баста.');
    expect(insight.isLocalFallback, isFalse);
  });
}
