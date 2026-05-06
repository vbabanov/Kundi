import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/db/sync_queue_repository.dart';
import 'ingest_uploader.dart';

abstract class SyncQueueGateway {
  Future<List<SyncQueueItem>> listReady();

  Future<void> markSynced(String requestID);

  Future<void> markFailure(
    String requestID,
    SyncFailure failure,
    int attempts,
  );
}

class SyncRunResult {
  const SyncRunResult({
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  final int total;
  final int succeeded;
  final int failed;
}

enum SyncFailureType {
  transient,
  authExpired,
  conflict,
  malformedPayload,
  permanent,
}

class SyncFailure {
  const SyncFailure({
    required this.type,
    required this.message,
  });

  final SyncFailureType type;
  final String message;
}

class SyncClassifiedException implements Exception {
  const SyncClassifiedException(this.type, this.message);

  final SyncFailureType type;
  final String message;

  @override
  String toString() => 'SyncClassifiedException($type): $message';
}

class SyncOrchestrator {
  SyncOrchestrator({
    required SyncQueueGateway queue,
    required IngestUploader uploader,
  })  : _queue = queue,
        _uploader = uploader;

  final SyncQueueGateway _queue;
  final IngestUploader _uploader;

  Future<SyncRunResult> runPending({
    required String accessToken,
    int limit = 20,
  }) async {
    if (accessToken.trim().isEmpty) {
      return const SyncRunResult(total: 0, succeeded: 0, failed: 0);
    }

    final pending = await _queue.listReady();
    if (pending.isEmpty) {
      return const SyncRunResult(total: 0, succeeded: 0, failed: 0);
    }

    var successCount = 0;
    var failureCount = 0;
    final capped = pending.take(limit).toList(growable: false);

    for (final item in capped) {
      try {
        final decoded = jsonDecode(item.payloadJson);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('sync queue payload must be JSON object');
        }
        await _uploader.uploadBundle(
          accessToken: accessToken,
          payload: decoded,
        );
        await _queue.markSynced(item.requestID);
        successCount++;
      } catch (error) {
        final failure = classifySyncFailure(error);
        await _queue.markFailure(
          item.requestID,
          failure,
          item.attempts + 1,
        );
        failureCount++;
      }
    }

    return SyncRunResult(
      total: capped.length,
      succeeded: successCount,
      failed: failureCount,
    );
  }

  SyncFailure classifySyncFailure(Object error) {
    if (error is SyncClassifiedException) {
      return SyncFailure(type: error.type, message: error.message);
    }
    if (error is FormatException) {
      return SyncFailure(
        type: SyncFailureType.malformedPayload,
        message: error.message,
      );
    }
    if (error is DioException) {
      final status = error.response?.statusCode ?? 0;
      if (status == 401 || status == 403) {
        return SyncFailure(
          type: SyncFailureType.authExpired,
          message: 'Authorization expired',
        );
      }
      if (status == 409) {
        return SyncFailure(
          type: SyncFailureType.conflict,
          message: 'Ingest conflict',
        );
      }
      if (status == 400 || status == 422) {
        return SyncFailure(
          type: SyncFailureType.malformedPayload,
          message: 'Malformed payload',
        );
      }
      if (status == 429 || status >= 500 || status == 0) {
        return SyncFailure(
          type: SyncFailureType.transient,
          message: error.message ?? 'Transient sync transport failure',
        );
      }
      return SyncFailure(
        type: SyncFailureType.permanent,
        message: error.message ?? 'Permanent sync failure',
      );
    }
    return SyncFailure(
      type: SyncFailureType.permanent,
      message: error.toString(),
    );
  }
}
