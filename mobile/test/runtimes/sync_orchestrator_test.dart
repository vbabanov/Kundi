import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kundi_mobile/core/db/sync_queue_repository.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/ingest_uploader.dart';
import 'package:kundi_mobile/runtimes/connector_runtime/sync_queue/sync_orchestrator.dart';

class _FakeQueue implements SyncQueueGateway {
  _FakeQueue(this.items);

  final List<SyncQueueItem> items;
  final List<String> synced = <String>[];
  final List<String> failed = <String>[];

  @override
  Future<List<SyncQueueItem>> listReady() async => items;

  @override
  Future<void> markFailure(
    String requestID,
    SyncFailure failure,
    int attempts,
  ) async {
    failed.add('$requestID|$attempts|${failure.type.name}|${failure.message}');
  }

  @override
  Future<void> markSynced(String requestID) async {
    synced.add(requestID);
  }
}

class _FakeUploader implements IngestUploader {
  _FakeUploader({this.error});

  final Object? error;
  final List<Map<String, dynamic>> uploaded = <Map<String, dynamic>>[];

  @override
  Future<void> uploadBundle({
    required String accessToken,
    required Map<String, dynamic> payload,
  }) async {
    if (error != null) {
      throw error!;
    }
    uploaded.add(payload);
  }
}

void main() {
  test('sync orchestrator uploads queued items and marks them synced',
      () async {
    final queue = _FakeQueue([
      SyncQueueItem(
        requestID: 'req-1',
        payloadJson:
            jsonEncode({'idempotency_key': 'req-1', 'source': 'kundelik'}),
        status: 'pending',
        attempts: 0,
        nextRetryAt: DateTime.now().toUtc(),
        lastError: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    ]);
    final uploader = _FakeUploader();
    final orchestrator = SyncOrchestrator(queue: queue, uploader: uploader);

    final result = await orchestrator.runPending(accessToken: 'token');

    expect(result.total, 1);
    expect(result.succeeded, 1);
    expect(result.failed, 0);
    expect(queue.synced, ['req-1']);
    expect(queue.failed, isEmpty);
    expect(uploader.uploaded.length, 1);
  });

  test('sync orchestrator marks failures with incremented attempts', () async {
    final queue = _FakeQueue([
      SyncQueueItem(
        requestID: 'req-2',
        payloadJson:
            jsonEncode({'idempotency_key': 'req-2', 'source': 'kundelik'}),
        status: 'failed',
        attempts: 2,
        nextRetryAt: DateTime.now().toUtc(),
        lastError: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    ]);
    final uploader = _FakeUploader(error: Exception('upload failed'));
    final orchestrator = SyncOrchestrator(queue: queue, uploader: uploader);

    final result = await orchestrator.runPending(accessToken: 'token');

    expect(result.total, 1);
    expect(result.succeeded, 0);
    expect(result.failed, 1);
    expect(queue.synced, isEmpty);
    expect(queue.failed.single.contains('req-2|3|permanent|'), true);
  });

  test('sync orchestrator classifies auth expired as terminal auth failure',
      () async {
    final queue = _FakeQueue([
      SyncQueueItem(
        requestID: 'req-auth',
        payloadJson:
            jsonEncode({'idempotency_key': 'req-auth', 'source': 'kundelik'}),
        status: 'pending',
        attempts: 0,
        nextRetryAt: DateTime.now().toUtc(),
        lastError: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    ]);
    final uploader = _FakeUploader(
      error: const SyncClassifiedException(
        SyncFailureType.authExpired,
        'token expired',
      ),
    );
    final orchestrator = SyncOrchestrator(queue: queue, uploader: uploader);

    final result = await orchestrator.runPending(accessToken: 'token');

    expect(result.total, 1);
    expect(result.failed, 1);
    expect(queue.failed.single.contains('authExpired'), isTrue);
  });

  test('sync orchestrator classifies malformed payload before upload',
      () async {
    final queue = _FakeQueue([
      SyncQueueItem(
        requestID: 'req-malformed',
        payloadJson: '{bad-json',
        status: 'pending',
        attempts: 0,
        nextRetryAt: DateTime.now().toUtc(),
        lastError: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    ]);
    final uploader = _FakeUploader();
    final orchestrator = SyncOrchestrator(queue: queue, uploader: uploader);

    final result = await orchestrator.runPending(accessToken: 'token');

    expect(result.total, 1);
    expect(result.failed, 1);
    expect(queue.failed.single.contains('malformedPayload'), isTrue);
    expect(uploader.uploaded, isEmpty);
  });
}
