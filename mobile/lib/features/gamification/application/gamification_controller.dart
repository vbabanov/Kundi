import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/gamification_repository_impl.dart';
import '../domain/gamification_entity.dart';
import '../domain/gamification_repository.dart';

final gamificationRepositoryProvider = Provider<GamificationRepository>((ref) {
  return GamificationRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    readSession: () => ref.read(authControllerProvider).valueOrNull,
  );
});

final gamificationControllerProvider =
    AsyncNotifierProvider<GamificationController, GamificationProfile?>(
  GamificationController.new,
);

class GamificationController extends AsyncNotifier<GamificationProfile?> {
  Future<GamificationProfile?>? _activityInFlight;
  Future<List<AchievementEntity>>? _claimInFlight;
  String _lastSuccessfulActivityDay = '';

  @override
  Future<GamificationProfile?> build() async {
    final session = ref.watch(authControllerProvider).valueOrNull;
    if (session == null) return null;
    return ref.read(gamificationRepositoryProvider).getProfile();
  }

  Future<bool> refresh() async {
    try {
      final next = await ref.read(gamificationRepositoryProvider).getProfile();
      state = AsyncData(next);
      return true;
    } on Object {
      return false;
    }
  }

  Future<List<AchievementEntity>> recordDailyActivityAndClaim() async {
    final running = _claimInFlight;
    if (running != null) {
      await running;
      return const <AchievementEntity>[];
    }
    final future = _recordDailyActivityAndClaimOnce();
    _claimInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_claimInFlight, future)) _claimInFlight = null;
    }
  }

  Future<List<AchievementEntity>> _recordDailyActivityAndClaimOnce() async {
    final today = DateTime.now();
    final dayKey = '${today.year}-${today.month}-${today.day}';
    GamificationProfile? profile = state.valueOrNull;
    if (_lastSuccessfulActivityDay != dayKey) {
      final running = _activityInFlight;
      if (running != null) {
        profile = await running;
      } else {
        final future = _recordActivity();
        _activityInFlight = future;
        try {
          profile = await future;
          if (profile != null) _lastSuccessfulActivityDay = dayKey;
        } finally {
          _activityInFlight = null;
        }
      }
    }
    profile ??= state.valueOrNull;
    if (profile == null || profile.pendingUnlocks.isEmpty) {
      return const <AchievementEntity>[];
    }
    final pending = List<AchievementEntity>.unmodifiable(
      profile.pendingUnlocks,
    );
    try {
      await ref.read(gamificationRepositoryProvider).acknowledge(
            pending.map((item) => item.code).toList(growable: false),
          );
      state = AsyncData(profile.markPendingSeen());
      return pending;
    } on Object {
      // Claim first, then present: an acknowledgement retry can never show the
      // same unlock twice after the server accepted it.
      return const <AchievementEntity>[];
    }
  }

  Future<GamificationProfile?> _recordActivity() async {
    try {
      final profile =
          await ref.read(gamificationRepositoryProvider).recordActivity();
      state = AsyncData(profile);
      return profile;
    } on Object {
      // Daily activity is best-effort and must not block authenticated startup.
      return null;
    }
  }
}
