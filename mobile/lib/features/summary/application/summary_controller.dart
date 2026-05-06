import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../data/summary_repository_impl.dart';
import '../domain/summary_entity.dart';
import '../domain/summary_repository.dart';

final summaryRepositoryProvider = Provider<SummaryRepository>((ref) {
  return SummaryRepositoryImpl(ref.watch(canonicalCacheStoreProvider));
});

final summaryControllerProvider =
    AsyncNotifierProvider<SummaryController, SummaryEntity>(
  SummaryController.new,
);

class SummaryController extends AsyncNotifier<SummaryEntity> {
  @override
  Future<SummaryEntity> build() {
    return ref.watch(summaryRepositoryProvider).get();
  }

  Future<void> refreshFromCache() async {
    state = const AsyncLoading<SummaryEntity>();
    state = await AsyncValue.guard(
      () => ref.read(summaryRepositoryProvider).get(),
    );
  }
}
