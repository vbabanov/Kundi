import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/sync_queue_repository.dart';
import 'providers.dart';
import 'sync_status_provider.dart';

class SyncDebugSnapshot {
  const SyncDebugSnapshot({
    required this.enabled,
    required this.syncStatus,
    required this.queueItems,
    required this.lastSyncedRequestID,
    required this.connectorDiagnostics,
  });

  final bool enabled;
  final SyncStatusSnapshot syncStatus;
  final List<SyncQueueItem> queueItems;
  final String? lastSyncedRequestID;
  final List<String> connectorDiagnostics;
}

final syncDebugSnapshotProvider =
    AsyncNotifierProvider<SyncDebugSnapshotController, SyncDebugSnapshot>(
  SyncDebugSnapshotController.new,
);

class SyncDebugSnapshotController extends AsyncNotifier<SyncDebugSnapshot> {
  @override
  Future<SyncDebugSnapshot> build() async {
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<SyncDebugSnapshot>();
    state = await AsyncValue.guard(_load);
  }

  Future<SyncDebugSnapshot> _load() async {
    final enabled = _debugEnabled();
    final status = await ref.watch(syncStatusProvider.future);
    if (!enabled) {
      return SyncDebugSnapshot(
        enabled: false,
        syncStatus: status,
        queueItems: const <SyncQueueItem>[],
        lastSyncedRequestID: null,
        connectorDiagnostics: const <String>[],
      );
    }

    final queue = ref.watch(syncQueueServiceProvider);
    final runtime = ref.watch(connectorRuntimeProvider);
    return SyncDebugSnapshot(
      enabled: true,
      syncStatus: status,
      queueItems: await queue.listRecent(limit: 20),
      lastSyncedRequestID: await queue.lastSyncedRequestID(),
      connectorDiagnostics: runtime.exportDiagnostics(),
    );
  }

  bool _debugEnabled() {
    return kDebugMode ||
        const bool.fromEnvironment('ENABLE_DEBUG_SURFACES', defaultValue: false);
  }
}
