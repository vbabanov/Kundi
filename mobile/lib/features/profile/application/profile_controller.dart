import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/profile_repository_impl.dart';
import '../domain/profile_entity.dart';
import '../domain/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl(
    ref.watch(canonicalCacheStoreProvider),
    ref.watch(apiClientProvider),
    () => ref.read(authControllerProvider).valueOrNull,
  );
});

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, ProfileEntity?>(
  ProfileController.new,
);

class ProfileController extends AsyncNotifier<ProfileEntity?> {
  @override
  Future<ProfileEntity?> build() {
    return ref.watch(profileRepositoryProvider).get();
  }

  Future<void> refreshFromCache() async {
    state = const AsyncLoading<ProfileEntity?>();
    state =
        await AsyncValue.guard(() => ref.read(profileRepositoryProvider).get());
  }

  Future<void> reloadFromCache() async {
    final next = await ref.read(profileRepositoryProvider).get();
    state = AsyncData(next);
  }

  Future<void> saveLocalAppProfile({
    required String parentPhone1,
    required String parentPhone2,
  }) async {
    state = const AsyncLoading<ProfileEntity?>();
    state = await AsyncValue.guard(() async {
      await ref.read(profileRepositoryProvider).saveLocalAppProfile(
            parentPhone1: parentPhone1,
            parentPhone2: parentPhone2,
          );
      return ref.read(profileRepositoryProvider).get();
    });
  }
}
