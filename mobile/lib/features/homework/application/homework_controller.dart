import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../data/homework_repository_impl.dart';
import '../domain/homework_entity.dart';

final homeworkRepositoryProvider = Provider<HomeworkRepositoryImpl>((ref) {
  return HomeworkRepositoryImpl(ref.watch(canonicalCacheStoreProvider));
});

final homeworkControllerProvider =
    AsyncNotifierProvider<HomeworkController, List<HomeworkEntity>>(
  HomeworkController.new,
);

class HomeworkController extends AsyncNotifier<List<HomeworkEntity>> {
  @override
  Future<List<HomeworkEntity>> build() {
    return ref.watch(homeworkRepositoryProvider).list();
  }

  Future<void> refreshFromCache() async {
    state = const AsyncLoading<List<HomeworkEntity>>();
    state = await AsyncValue.guard(
        () => ref.read(homeworkRepositoryProvider).list());
  }
}
