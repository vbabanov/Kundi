import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/network/api_client.dart';
import 'package:kundi_mobile/features/assistant/data/assistant_repository_impl.dart';
import 'package:kundi_mobile/features/assistant/domain/assistant_entity.dart';
import 'package:kundi_mobile/runtimes/avatar_runtime/contracts/avatar_response_package.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('assistant repository maps backend response to avatar package',
      () async {
    server.listen((request) async {
      if (request.method == 'POST' &&
          request.uri.path == '/v1/assistant/message') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': {
            'text': 'Tutor answer',
            'audioUrl': 'https://cdn.test/audio.mp3',
            'audio_status': 'ready',
            'visemes': [
              {'offset_ms': 0, 'id': 'A', 'weight': 0.9}
            ],
            'avatar_emotion': 'encouraging',
            'gesture_tags': ['explain'],
            'pedagogy_flags': {
              'needs_scaffold': true,
              'contains_hint': true,
              'contains_step_plan': true,
              'safety_intervention': false,
            },
            'behavior': {
              'mode': 'tutor',
              'grade_band': 'middle',
              'persona_tone': 'coach',
            },
          }
        }));
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });

    final repository = AssistantRepositoryImpl(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );

    final result = await repository.sendMessage(
      accessToken: 'access-token',
      text: 'Help me with algebra',
      mode: AssistantMode.tutor,
      gradeLevel: 7,
    );

    expect(result.responseText, 'Tutor answer');
    expect(result.avatarPackage.audioUrl, 'https://cdn.test/audio.mp3');
    expect(result.avatarPackage.audioStatus, AvatarAudioStatus.ready);
    expect(result.avatarPackage.emotion, 'encouraging');
    expect(result.avatarPackage.gestureTags, contains('explain'));
    expect(result.gradeBand, 'middle');
  });
}
