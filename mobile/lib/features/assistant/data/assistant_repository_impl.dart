import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../runtimes/avatar_runtime/contracts/avatar_response_package.dart';
import '../domain/assistant_entity.dart';
import '../domain/assistant_repository.dart';

class AssistantRepositoryImpl implements AssistantRepository {
  AssistantRepositoryImpl({required ApiClient apiClient})
      : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<AssistantSessionEntity> createSession({
    required String accessToken,
  }) async {
    _requireToken(accessToken);
    final response = await _apiClient.post(
      '/v1/assistant/sessions',
      options: _auth(accessToken),
      data: const <String, dynamic>{},
    );
    if (response.statusCode != 201) {
      throw const AppException(
          'assistant_session_create_failed', 'Не удалось создать диалог.');
    }
    return _sessionFromJson(_payload(response.data));
  }

  @override
  Future<AssistantPageResult<AssistantSessionEntity>> listSessions({
    required String accessToken,
    String cursor = '',
    int limit = 20,
  }) async {
    _requireToken(accessToken);
    final response = await _apiClient.get(
      '/v1/assistant/sessions',
      options: _auth(accessToken),
      queryParameters: <String, dynamic>{
        'limit': limit,
        if (cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    final payload = _payload(response.data);
    final rawItems =
        payload['items'] is List ? payload['items'] as List : const <dynamic>[];
    return AssistantPageResult<AssistantSessionEntity>(
      items: rawItems
          .whereType<Map>()
          .map((item) => _sessionFromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      nextCursor: (payload['next_cursor'] ?? '').toString(),
    );
  }

  @override
  Future<AssistantPageResult<AssistantMessageEntity>> listMessages({
    required String accessToken,
    required String sessionId,
    String cursor = '',
    int limit = 20,
  }) async {
    _requireToken(accessToken);
    final response = await _apiClient.get(
      '/v1/assistant/sessions/${Uri.encodeComponent(sessionId)}/messages',
      options: _auth(accessToken),
      queryParameters: <String, dynamic>{
        'limit': limit,
        if (cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    final payload = _payload(response.data);
    final rawItems =
        payload['items'] is List ? payload['items'] as List : const <dynamic>[];
    return AssistantPageResult<AssistantMessageEntity>(
      items: rawItems
          .whereType<Map>()
          .map((item) => _messageFromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      nextCursor: (payload['next_cursor'] ?? '').toString(),
    );
  }

  @override
  Future<AssistantMessageResult> sendSessionMessage({
    required String accessToken,
    required String sessionId,
    required String clientMessageId,
    required String text,
    AssistantInputMode inputMode = AssistantInputMode.text,
  }) async {
    _requireToken(accessToken);
    if (text.trim().isEmpty) {
      throw const AppException('assistant_empty_text', 'Введите сообщение.');
    }
    late final Response<dynamic> response;
    try {
      response = await _apiClient.post(
        '/v1/assistant/sessions/${Uri.encodeComponent(sessionId)}/messages',
        options: _auth(accessToken),
        data: <String, dynamic>{
          'client_message_id': clientMessageId,
          'text': text.trim(),
          'input_mode': inputMode.apiValue,
        },
      );
    } on DioException catch (error) {
      throw _assistantAppException(error);
    }
    final payload = _payload(response.data);
    if (payload['user_message'] is! Map ||
        payload['assistant_message'] is! Map) {
      throw const AppException(
          'assistant_invalid_payload', 'Сервер вернул неполный ответ.');
    }
    final suggestions = payload['suggestions'] is List
        ? (payload['suggestions'] as List)
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .take(3)
            .toList(growable: false)
        : const <String>[];
    return AssistantMessageResult(
      userMessage: _messageFromJson(
          Map<String, dynamic>.from(payload['user_message'] as Map)),
      assistantMessage: _messageFromJson(
          Map<String, dynamic>.from(payload['assistant_message'] as Map)),
      responseMode: (payload['response_mode'] ?? '').toString(),
      helpLevel: (payload['help_level'] ?? '').toString(),
      followUpQuestion: (payload['follow_up_question'] ?? '').toString(),
      emotion: (payload['emotion'] ?? 'neutral').toString(),
      animationCue: (payload['animation_cue'] ?? 'standing').toString(),
      suggestions: suggestions,
      session: payload['session'] is Map
          ? _sessionFromJson(
              Map<String, dynamic>.from(payload['session'] as Map))
          : null,
    );
  }

  @override
  Future<void> deleteSession({
    required String accessToken,
    required String sessionId,
  }) async {
    _requireToken(accessToken);
    final response = await _apiClient.delete(
      '/v1/assistant/sessions/${Uri.encodeComponent(sessionId)}',
      options: _auth(accessToken),
    );
    if (response.statusCode != 204) {
      throw const AppException(
          'assistant_session_delete_failed', 'Не удалось удалить диалог.');
    }
  }

  @override
  Future<AssistantEntity> sendMessage({
    required String accessToken,
    required String text,
    required AssistantMode mode,
    required int gradeLevel,
    List<AssistantChatRecord> history = const <AssistantChatRecord>[],
  }) async {
    if (accessToken.trim().isEmpty) {
      throw const AppException(
          'assistant_auth_required', 'Authorization token is required.');
    }
    if (text.trim().isEmpty) {
      throw const AppException(
          'assistant_empty_text', 'Assistant message is required.');
    }

    final response = await _apiClient.post(
      '/v1/assistant/message',
      options: Options(
          headers: <String, String>{'Authorization': 'Bearer $accessToken'}),
      data: <String, dynamic>{
        'mode': mode.apiValue,
        'grade_level': gradeLevel <= 0 ? 7 : gradeLevel,
        'text': text.trim(),
        'history':
            history.map((record) => record.toJson()).toList(growable: false),
      },
    );

    if (response.statusCode != 200 || response.data is! Map) {
      throw const AppException(
          'assistant_request_failed', 'Assistant request failed.');
    }

    final root = Map<String, dynamic>.from(response.data as Map);
    final payload = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;

    final visemesRaw = payload['visemes'] is List
        ? payload['visemes'] as List
        : const <dynamic>[];
    final visemes = visemesRaw.whereType<Map>().map((item) {
      final mapped = Map<String, dynamic>.from(item);
      return AvatarViseme(
        offsetMs: int.tryParse((mapped['offset_ms'] ?? '0').toString()) ?? 0,
        id: (mapped['id'] ?? '').toString(),
        weight: double.tryParse((mapped['weight'] ?? '0').toString()) ?? 0,
      );
    }).toList(growable: false);

    final gesturesRaw = payload['gesture_tags'] is List
        ? payload['gesture_tags'] as List
        : const <dynamic>[];
    final gestureTags = gesturesRaw
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    final pedagogy = payload['pedagogy_flags'] is Map
        ? Map<String, dynamic>.from(payload['pedagogy_flags'] as Map)
        : <String, dynamic>{};

    final audioStatusRaw =
        (payload['audio_status'] ?? 'unavailable').toString();
    final audioStatus = audioStatusRaw == 'ready'
        ? AvatarAudioStatus.ready
        : AvatarAudioStatus.unavailable;

    final behavior = payload['behavior'] is Map
        ? Map<String, dynamic>.from(payload['behavior'] as Map)
        : <String, dynamic>{};

    final avatarPackage = AvatarResponsePackage(
      text: (payload['text'] ?? '').toString(),
      audioUrl: (payload['audioUrl'] ?? '').toString(),
      audioStatus: audioStatus,
      visemes: visemes,
      emotion: (payload['avatar_emotion'] ?? 'neutral').toString(),
      gestureTags: gestureTags,
      pedagogyFlags: AvatarPedagogyFlags(
        needsScaffold: pedagogy['needs_scaffold'] == true,
        containsHint: pedagogy['contains_hint'] == true,
        containsStepPlan: pedagogy['contains_step_plan'] == true,
        safetyIntervention: pedagogy['safety_intervention'] == true,
      ),
    );

    if (avatarPackage.text.isEmpty) {
      throw const AppException(
          'assistant_invalid_payload', 'Assistant response text is missing.');
    }

    final now = DateTime.now().toUtc();
    return AssistantEntity(
      id: '${now.millisecondsSinceEpoch}:${mode.apiValue}',
      mode: mode,
      userText: text.trim(),
      responseText: avatarPackage.text,
      avatarPackage: avatarPackage,
      createdAt: now,
      gradeBand: (behavior['grade_band'] ?? '').toString(),
    );
  }

  Options _auth(String token) => Options(
        headers: <String, String>{'Authorization': 'Bearer ${token.trim()}'},
      );

  void _requireToken(String token) {
    if (token.trim().isEmpty) {
      throw const AppException(
          'assistant_auth_required', 'Authorization token is required.');
    }
  }

  Map<String, dynamic> _payload(dynamic raw) {
    if (raw is! Map) {
      throw const AppException(
          'assistant_invalid_payload', 'Сервер вернул некорректный ответ.');
    }
    final root = Map<String, dynamic>.from(raw);
    if (root['data'] is Map) {
      return Map<String, dynamic>.from(root['data'] as Map);
    }
    return root;
  }

  AssistantSessionEntity _sessionFromJson(Map<String, dynamic> json) {
    return AssistantSessionEntity(
      id: (json['id'] ?? '').toString(),
      locale: (json['locale'] ?? 'ru-KZ').toString(),
      gradeLevel: int.tryParse((json['grade_level'] ?? '1').toString()) ?? 1,
      title: (json['title'] ?? '').toString(),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      lastMessageAt: _date(json['last_message_at']),
    );
  }

  AssistantMessageEntity _messageFromJson(Map<String, dynamic> json) {
    return AssistantMessageEntity(
      id: (json['id'] ?? '').toString(),
      sessionId: (json['session_id'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      inputMode: (json['input_mode'] ?? 'text').toString(),
      responseMode: (json['response_mode'] ?? '').toString(),
      createdAt: _date(json['created_at']),
    );
  }

  DateTime _date(dynamic raw) =>
      DateTime.tryParse((raw ?? '').toString())?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  AppException _assistantAppException(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const AppException(
        'unauthorized',
        'Сессия авторизации недействительна.',
      );
    }

    final raw = error.response?.data;
    final root = raw is Map ? Map<String, dynamic>.from(raw) : null;
    final errorPayload = root?['error'] is Map
        ? Map<String, dynamic>.from(root!['error'] as Map)
        : null;
    final code = (errorPayload?['code'] ?? '').toString().trim();
    if (code.isNotEmpty) {
      final message = _isAssistantValidationCode(code)
          ? _safeServerMessage(errorPayload?['message'])
          : 'Не удалось отправить сообщение.';
      return AppException(code, message);
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AppException(
          'assistant_request_timeout',
          'Kundi временно не смогла ответить.',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const AppException(
          'assistant_network_error',
          'Не удалось отправить сообщение.',
        );
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
        return const AppException(
          'assistant_request_failed',
          'Не удалось отправить сообщение.',
        );
    }
  }

  bool _isAssistantValidationCode(String code) {
    return code == 'invalid_json' ||
        code == 'assistant_empty_text' ||
        code.endsWith('_invalid') ||
        code.endsWith('_required') ||
        code.contains('_too_long') ||
        code.contains('_too_large');
  }

  String _safeServerMessage(dynamic raw) {
    final normalized =
        (raw ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'Проверьте сообщение и попробуйте снова.';
    }
    if (normalized.length <= 180) {
      return normalized;
    }
    return '${normalized.substring(0, 180)}…';
  }
}
