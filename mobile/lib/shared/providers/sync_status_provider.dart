import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/sync_queue_repository.dart';
import 'providers.dart';

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.pending,
    required this.failed,
    required this.lastSuccessfulSyncAt,
  });

  final int pending;
  final int failed;
  final DateTime? lastSuccessfulSyncAt;
}

final syncStatusProvider =
    AsyncNotifierProvider<SyncStatusController, SyncStatusSnapshot>(
  SyncStatusController.new,
);

class SyncStatusController extends AsyncNotifier<SyncStatusSnapshot> {
  @override
  Future<SyncStatusSnapshot> build() async {
    final stats = await ref.watch(syncQueueServiceProvider).stats();
    return _fromStats(stats);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<SyncStatusSnapshot>();
    state = await AsyncValue.guard(() async {
      final stats = await ref.read(syncQueueServiceProvider).stats();
      return _fromStats(stats);
    });
  }

  SyncStatusSnapshot _fromStats(SyncQueueStats stats) {
    return SyncStatusSnapshot(
      pending: stats.pending,
      failed: stats.failed,
      lastSuccessfulSyncAt: stats.lastSuccessfulSyncAt,
    );
  }
}
