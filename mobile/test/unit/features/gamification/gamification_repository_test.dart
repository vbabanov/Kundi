import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/features/auth/domain/auth_session.dart';
import 'package:kundi_mobile/features/gamification/data/gamification_repository_impl.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('maps authoritative profile, activity and acknowledgement', () async {
    final seen = <String>[];
    server.listen((request) async {
      seen.add('${request.method} ${request.uri.path}');
      expect(request.headers.value('authorization'), 'Bearer access');
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' &&
          request.uri.path == '/v1/gamification/achievements/ack') {
        final body = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        expect(body['codes'], ['activity_first_day']);
        request.response.statusCode = 204;
      } else {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({'data': _profileJson()}));
      }
      await request.response.close();
    });

    final repository = GamificationRepositoryImpl(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
      readSession: () => AuthSession(
        studentId: 'student',
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2026, 10),
      ),
    );
    final profile = await repository.getProfile();
    final activity = await repository.recordActivity();
    await repository.acknowledge(['activity_first_day']);

    expect(profile.points, 30);
    expect(profile.level, 1);
    expect(profile.currentStreak, 1);
    expect(profile.achievements.single.title.resolve('ru'), 'Первый день');
    expect(profile.achievements.single.title.resolve('kk'), 'Алғашқы күн');
    expect(profile.achievements.single.unlocked, isTrue);
    expect(activity.pendingUnlocks.single.code, 'activity_first_day');
    expect(seen, [
      'GET /v1/gamification/profile',
      'POST /v1/gamification/activity',
      'POST /v1/gamification/achievements/ack',
    ]);
  });
}

Map<String, dynamic> _profileJson() => <String, dynamic>{
      'catalog_version': 1,
      'points': 30,
      'level': 1,
      'level_floor_points': 0,
      'next_level_points': 100,
      'current_streak': 1,
      'longest_streak': 1,
      'last_active_date': '2026-09-09',
      'achievements_unlocked': 1,
      'achievements_total': 13,
      'achievements': [_achievementJson()],
      'pending_unlocks': [_achievementJson()],
    };

Map<String, dynamic> _achievementJson() => <String, dynamic>{
      'code': 'activity_first_day',
      'category': 'activity',
      'category_title': {'ru': 'Активность', 'kk': 'Белсенділік'},
      'title': {'ru': 'Первый день', 'kk': 'Алғашқы күн'},
      'description': {
        'ru': 'Впервые воспользуйся Kundi.',
        'kk': 'Kundi қолданбасын алғаш рет пайдалан.',
      },
      'current': 1,
      'target': 1,
      'unlocked': true,
      'unlocked_at': '2026-09-09T00:00:00Z',
      'seen': false,
    };
