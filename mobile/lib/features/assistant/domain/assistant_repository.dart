import 'assistant_entity.dart';

abstract class AssistantRepository {
  Future<AssistantEntity> sendMessage({
    required String accessToken,
    required String text,
    required AssistantMode mode,
    required int gradeLevel,
    List<AssistantChatRecord> history,
  });
}
