import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../data/grades_repository_impl.dart';
import '../domain/grades_entity.dart';
import '../domain/grades_repository.dart';

final gradesRepositoryProvider = Provider<GradesRepository>((ref) {
  return GradesRepositoryImpl(ref.watch(canonicalCacheStoreProvider));
});

final gradesControllerProvider =
    AsyncNotifierProvider<GradesController, GradesScreenData>(
  GradesController.new,
);

class GradesController extends AsyncNotifier<GradesScreenData> {
  @override
  Future<GradesScreenData> build() {
    return ref.watch<GradesRepository>(gradesRepositoryProvider).get();
  }

  Future<void> refreshFromCache() async {
    state = const AsyncLoading<GradesScreenData>();
    state = await AsyncValue.guard(
      () => ref.read<GradesRepository>(gradesRepositoryProvider).get(),
    );
  }

  Future<void> reloadFromCache() async {
    final next =
        await ref.read<GradesRepository>(gradesRepositoryProvider).get();
    state = AsyncData(next);
  }
}
