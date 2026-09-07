import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/errors/app_exception.dart';
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

  test('assistant repository supports session CRUD and text messages',
      () async {
    final seenPaths = <String>[];
    server.listen((request) async {
      seenPaths.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' &&
          request.uri.path == '/v1/assistant/sessions') {
        request.response.statusCode = 201;
        request.response.write(jsonEncode({'data': _sessionJson()}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/assistant/sessions') {
        request.response.write(jsonEncode({
          'data': {
            'items': [_sessionJson()],
            'next_cursor': 'sessions-next',
          }
        }));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/assistant/sessions/session-1/messages') {
        request.response.write(jsonEncode({
          'data': {
            'items': [_messageJson('message-1', 'assistant', 'Привет!')],
            'next_cursor': 'messages-next',
          }
        }));
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/assistant/sessions/session-1/messages') {
        final body = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        expect(body['client_message_id'], 'client-1');
        expect(body.keys, isNot(contains('audio')));
        request.response.write(jsonEncode({
          'data': {
            'user_message': _messageJson('user-1', 'user', 'Вопрос'),
            'assistant_message':
                _messageJson('assistant-1', 'assistant', 'Ответ'),
            'response_mode': 'explanation',
            'help_level': 'guided',
            'emotion': 'neutral',
            'emotion_intensity': 0.18,
            'animation_cue': 'standing',
            'suggestions': ['Повторить: дроби'],
            'session': {
              ..._sessionJson(),
              'title': 'Вопрос',
              'updated_at': '2026-09-04T00:01:00Z',
              'last_message_at': '2026-09-04T00:01:00Z',
            },
          }
        }));
      } else if (request.method == 'DELETE' &&
          request.uri.path == '/v1/assistant/sessions/session-1') {
        request.response.statusCode = 204;
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final repository = AssistantRepositoryImpl(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    final created = await repository.createSession(accessToken: 'token');
    final sessions = await repository.listSessions(accessToken: 'token');
    final messages = await repository.listMessages(
        accessToken: 'token', sessionId: created.id);
    final sent = await repository.sendSessionMessage(
      accessToken: 'token',
      sessionId: created.id,
      clientMessageId: 'client-1',
      text: 'Вопрос',
    );
    await repository.deleteSession(accessToken: 'token', sessionId: created.id);

    expect(created.gradeLevel, 7);
    expect(sessions.nextCursor, 'sessions-next');
    expect(messages.items.single.content, 'Привет!');
    expect(sent.assistantMessage.content, 'Ответ');
    expect(sent.animationCue, 'standing');
    expect(sent.emotionIntensity, 0.18);
    expect(sent.session?.title, 'Вопрос');
    expect(seenPaths, contains('DELETE /v1/assistant/sessions/session-1'));
  });

  test('assistant repository keeps old backend response compatible', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': {
          'user_message': _messageJson('user-1', 'user', 'Вопрос'),
          'assistant_message':
              _messageJson('assistant-1', 'assistant', 'Ответ'),
          'response_mode': 'answer',
          'help_level': 'direct',
          'emotion': 'neutral',
          'animation_cue': 'standing',
          'suggestions': <String>[],
        }
      }));
      await request.response.close();
    });
    final repository = AssistantRepositoryImpl(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    final result = await repository.sendSessionMessage(
      accessToken: 'token',
      sessionId: 'session-1',
      clientMessageId: 'client-1',
      text: 'Вопрос',
    );
    expect(result.session, isNull);
    expect(result.emotionIntensity, 1);
  });

  test('assistant repository maps structured server errors safely', () async {
    server.listen((request) async {
      request.response.statusCode = 429;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': {
          'code': 'assistant_rate_limited',
          'message': 'internal provider details must not be surfaced',
        }
      }));
      await request.response.close();
    });
    final repository = AssistantRepositoryImpl(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    await expectLater(
      repository.sendSessionMessage(
        accessToken: 'token',
        sessionId: 'session-1',
        clientMessageId: 'client-1',
        text: 'Вопрос',
      ),
      throwsA(
        isA<AppException>()
            .having((error) => error.code, 'code', 'assistant_rate_limited')
            .having(
              (error) => error.message,
              'safe message',
              'Не удалось отправить сообщение.',
            ),
      ),
    );
  });
}

Map<String, dynamic> _sessionJson() => <String, dynamic>{
      'id': 'session-1',
      'locale': 'ru-KZ',
      'grade_level': 7,
      'title': '',
      'created_at': '2026-09-04T00:00:00Z',
      'updated_at': '2026-09-04T00:00:00Z',
      'last_message_at': '2026-09-04T00:00:00Z',
    };

Map<String, dynamic> _messageJson(String id, String role, String content) =>
    <String, dynamic>{
      'id': id,
      'session_id': 'session-1',
      'role': role,
      'content': content,
      'input_mode': 'text',
      'response_mode': role == 'assistant' ? 'explanation' : '',
      'created_at': '2026-09-04T00:00:00Z',
    };
