import 'dart:convert';

import '../../../core/db/sync_queue_repository.dart';
import '../contracts/models.dart';
import 'sync_orchestrator.dart';

class SyncQueueService implements SyncQueueGateway {
  SyncQueueService({SyncQueueRepository? repository})
      : _repository = repository ?? SyncQueueRepository();

  final SyncQueueRepository _repository;

  Future<void> enqueue(
    CanonicalBundle bundle, {
    bool useV2Ingest = false,
  }) async {
    final payload = useV2Ingest ? bundle.toV2Json() : bundle.toV1Json();
    await _repository.enqueue(
      requestID: bundle.idempotencyKey,
      payloadJson: jsonEncode(payload),
    );
  }

  @override
  Future<List<SyncQueueItem>> listReady() => _repository.listReady();

  Future<List<SyncQueueItem>> listRecent({int limit = 20}) =>
      _repository.listRecent(limit: limit);

  @override
  Future<void> markSynced(String requestID) =>
      _repository.markSynced(requestID);

  Future<SyncQueueStats> stats() => _repository.stats();

  Future<String?> lastSyncedRequestID() =>
      _repository.getMetadata('last_synced_request_id');

  @override
  Future<void> markFailure(
    String requestID,
    SyncFailure failure,
    int attempts,
  ) {
    switch (failure.type) {
      case SyncFailureType.transient:
        final boundedAttempts = attempts < 1 ? 1 : attempts;
        final delaySeconds =
            (10 * boundedAttempts * boundedAttempts).clamp(10, 300);
        return _repository.markAttemptFailure(
          requestID: requestID,
          message: failure.message,
          backoff: Duration(seconds: delaySeconds),
        );
      case SyncFailureType.authExpired:
        return _repository.markTerminalFailure(
          requestID: requestID,
          status: 'auth_expired',
          message: failure.message,
        );
      case SyncFailureType.conflict:
        return _repository.markTerminalFailure(
          requestID: requestID,
          status: 'conflict',
          message: failure.message,
        );
      case SyncFailureType.malformedPayload:
        return _repository.markTerminalFailure(
          requestID: requestID,
          status: 'malformed_payload',
          message: failure.message,
        );
      case SyncFailureType.permanent:
        return _repository.markTerminalFailure(
          requestID: requestID,
          status: 'permanent_failed',
          message: failure.message,
        );
    }
  }
}
