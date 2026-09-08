import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../data/lessons_repository_impl.dart';
import '../domain/lessons_entity.dart';
import '../domain/lessons_repository.dart';

final lessonsRepositoryProvider = Provider<LessonsRepository>((ref) {
  return LessonsRepositoryImpl(ref.watch(canonicalCacheStoreProvider));
});

final lessonsControllerProvider =
    AsyncNotifierProvider<LessonsController, List<LessonsEntity>>(
  LessonsController.new,
);

class LessonsController extends AsyncNotifier<List<LessonsEntity>> {
  @override
  Future<List<LessonsEntity>> build() {
    return ref.watch(lessonsRepositoryProvider).list();
  }

  Future<void> refreshFromCache() async {
    state = const AsyncLoading<List<LessonsEntity>>();
    state = await AsyncValue.guard(
        () => ref.read(lessonsRepositoryProvider).list());
  }

  Future<void> reloadFromCache() async {
    final next = await ref.read(lessonsRepositoryProvider).list();
    state = AsyncData(next);
  }
}
