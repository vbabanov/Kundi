import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/canonical_cache_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/read_source_policy.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../runtimes/avatar_runtime/bridge/avatar_bridge.dart';
import '../../runtimes/avatar_runtime/bridge/method_channel_avatar_bridge.dart';
import '../../runtimes/avatar_runtime/facade/avatar_facade.dart';
import '../../runtimes/connector_runtime/connector_runtime.dart';
import '../../runtimes/connector_runtime/sync_queue/api_ingest_uploader.dart';
import '../../runtimes/connector_runtime/sync_queue/ingest_uploader.dart';
import '../../runtimes/connector_runtime/sync_queue/sync_orchestrator.dart';
import '../../runtimes/connector_runtime/sync_queue/sync_queue_service.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
      baseUrl: const String.fromEnvironment('API_BASE_URL',
          defaultValue: 'https://api.kundi.lucartmax.kz'));
});

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return const SecureStorageService(
    FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true)),
  );
});

final canonicalCacheStoreProvider = Provider<CanonicalCacheStore>((ref) {
  return CanonicalCacheStore();
});

final readSourcePolicyProvider = Provider<ReadSourcePolicy>((ref) {
  return const ReadSourcePolicy(
    useTypedV2Read: bool.fromEnvironment(
      'USE_TYPED_V2_READ',
      defaultValue: true,
    ),
    enableV2ParityShadow: bool.fromEnvironment(
      'ENABLE_V2_PARITY_SHADOW',
      defaultValue: false,
    ),
    forceTypedV2Read: bool.fromEnvironment(
      'FORCE_TYPED_V2_READ',
      defaultValue: false,
    ),
    forceLegacyV1Read: bool.fromEnvironment(
      'FORCE_LEGACY_V1_READ',
      defaultValue: false,
    ),
    typedV2CohortPercent: int.fromEnvironment(
      'TYPED_V2_COHORT_PERCENT',
      defaultValue: -1,
    ),
    typedV2CohortAllowlist: String.fromEnvironment(
      'TYPED_V2_COHORT_ALLOWLIST',
      defaultValue: '',
    ),
    typedV2CohortDenylist: String.fromEnvironment(
      'TYPED_V2_COHORT_DENYLIST',
      defaultValue: '',
    ),
  );
});

final connectorRuntimeProvider = Provider<ConnectorRuntime>((ref) {
  return ConnectorRuntime();
});

final syncQueueServiceProvider = Provider<SyncQueueService>((ref) {
  return SyncQueueService();
});

final ingestUploaderProvider = Provider<IngestUploader>((ref) {
  return ApiIngestUploader(ref.watch(apiClientProvider));
});

final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  return SyncOrchestrator(
    queue: ref.watch(syncQueueServiceProvider),
    uploader: ref.watch(ingestUploaderProvider),
  );
});

final avatarBridgeProvider = Provider<AvatarBridge>((ref) {
  return MethodChannelAvatarBridge();
});

final avatarFacadeProvider = Provider<AvatarFacade>((ref) {
  return AvatarFacade(ref.watch(avatarBridgeProvider));
});
