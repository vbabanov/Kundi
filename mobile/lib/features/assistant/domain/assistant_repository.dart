import 'assistant_entity.dart';

abstract class AssistantRepository {
  Future<AssistantSessionEntity> createSession({required String accessToken});

  Future<AssistantPageResult<AssistantSessionEntity>> listSessions({
    required String accessToken,
    String cursor = '',
    int limit = 20,
  });

  Future<AssistantPageResult<AssistantMessageEntity>> listMessages({
    required String accessToken,
    required String sessionId,
    String cursor = '',
    int limit = 20,
  });

  Future<AssistantMessageResult> sendSessionMessage({
    required String accessToken,
    required String sessionId,
    required String clientMessageId,
    required String text,
  });

  Future<void> deleteSession({
    required String accessToken,
    required String sessionId,
  });

  Future<AssistantEntity> sendMessage({
    required String accessToken,
    required String text,
    required AssistantMode mode,
    required int gradeLevel,
    List<AssistantChatRecord> history,
  });
}
