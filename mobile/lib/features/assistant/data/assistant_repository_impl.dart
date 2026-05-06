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
}
