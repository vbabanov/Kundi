import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/application/auth_controller.dart';
import '../../../shared/providers/providers.dart';
import '../data/assistant_repository_impl.dart';
import '../domain/assistant_entity.dart';
import '../domain/assistant_repository.dart';

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  return AssistantRepositoryImpl(apiClient: ref.watch(apiClientProvider));
});

final assistantControllerProvider =
    AsyncNotifierProvider<AssistantController, List<AssistantEntity>>(
  AssistantController.new,
);

class AssistantController extends AsyncNotifier<List<AssistantEntity>> {
  @override
  Future<List<AssistantEntity>> build() async {
    return const <AssistantEntity>[];
  }

  Future<void> sendMessage({
    required String text,
    required AssistantMode mode,
    int gradeLevel = 7,
  }) async {
    final authState = ref.read(authControllerProvider);
    final session = authState.valueOrNull;
    if (session == null || session.accessToken.trim().isEmpty) {
      throw StateError('User must login before assistant can be used.');
    }

    final previous = state.valueOrNull ?? const <AssistantEntity>[];
    state = const AsyncLoading<List<AssistantEntity>>();

    state = await AsyncValue.guard(() async {
      final history = _buildHistory(previous);
      final item = await ref.read(assistantRepositoryProvider).sendMessage(
            accessToken: session.accessToken,
            text: text,
            mode: mode,
            gradeLevel: gradeLevel,
            history: history,
          );
      final next = <AssistantEntity>[...previous, item];
      await _playAvatar(item);
      return next;
    });
  }

  Future<void> _playAvatar(AssistantEntity item) async {
    final avatar = ref.read(avatarFacadeProvider);
    try {
      await avatar.startThinking();
      await avatar.speak(item.avatarPackage);
    } catch (_) {
      // Assistant must stay usable even when avatar bridge is unavailable.
    }
  }

  List<AssistantChatRecord> _buildHistory(List<AssistantEntity> items) {
    final out = <AssistantChatRecord>[];
    for (final item in items) {
      out.addAll(item.toHistory());
    }
    return out;
  }
}
