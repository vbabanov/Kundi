import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class SyncQueueItem {
  const SyncQueueItem({
    required this.requestID,
    required this.payloadJson,
    required this.status,
    required this.attempts,
    required this.nextRetryAt,
    required this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  final String requestID;
  final String payloadJson;
  final String status;
  final int attempts;
  final DateTime nextRetryAt;
  final String lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class SyncQueueStats {
  const SyncQueueStats({
    required this.pending,
    required this.failed,
    required this.lastSuccessfulSyncAt,
  });

  final int pending;
  final int failed;
  final DateTime? lastSuccessfulSyncAt;
}

class SyncQueueRepository {
  Future<void> enqueue({
    required String requestID,
    required String payloadJson,
  }) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc();
    await db.insert(
        'canonical_sync_queue',
        {
          'request_id': requestID,
          'payload_json': payloadJson,
          'status': 'pending',
          'attempts': 0,
          'next_retry_at': now.toIso8601String(),
          'last_error': '',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SyncQueueItem>> listReady({DateTime? now}) async {
    final db = await AppDatabase.open();
    final current = (now ?? DateTime.now().toUtc()).toIso8601String();
    final rows = await db.query(
      'canonical_sync_queue',
      where: 'status IN (?, ?) AND next_retry_at <= ?',
      whereArgs: ['pending', 'failed', current],
      orderBy: 'created_at ASC',
    );
    return rows.map(_toItem).toList(growable: false);
  }

  Future<List<SyncQueueItem>> listRecent({int limit = 20}) async {
    final db = await AppDatabase.open();
    final bounded = limit < 1 ? 1 : (limit > 200 ? 200 : limit);
    final rows = await db.query(
      'canonical_sync_queue',
      orderBy: 'updated_at DESC',
      limit: bounded,
    );
    return rows.map(_toItem).toList(growable: false);
  }

  Future<void> markAttemptFailure({
    required String requestID,
    required String message,
    required Duration backoff,
  }) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc();
    await db.rawUpdate(
      '''
      UPDATE canonical_sync_queue
      SET attempts = attempts + 1,
          status = 'failed',
          last_error = ?,
          next_retry_at = ?,
          updated_at = ?
      WHERE request_id = ?
      ''',
      [
        message,
        now.add(backoff).toIso8601String(),
        now.toIso8601String(),
        requestID,
      ],
    );
  }

  Future<void> markSynced(String requestID) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc();
    await db.transaction((txn) async {
      await txn.delete(
        'canonical_sync_queue',
        where: 'request_id = ?',
        whereArgs: [requestID],
      );
      await txn.insert(
          'canonical_sync_metadata',
          {
            'meta_key': 'last_successful_sync_at',
            'meta_value': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(
          'canonical_sync_metadata',
          {
            'meta_key': 'last_synced_request_id',
            'meta_value': requestID,
            'updated_at': now.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> markTerminalFailure({
    required String requestID,
    required String status,
    required String message,
  }) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate(
      '''
      UPDATE canonical_sync_queue
      SET status = ?,
          last_error = ?,
          updated_at = ?
      WHERE request_id = ?
      ''',
      [status, message, now, requestID],
    );
  }

  Future<SyncQueueStats> stats() async {
    final db = await AppDatabase.open();
    final pendingRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM canonical_sync_queue
      WHERE status = 'pending'
      ''',
    );
    final failedRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM canonical_sync_queue
      WHERE status = 'failed'
      ''',
    );
    final metaRows = await db.query(
      'canonical_sync_metadata',
      where: 'meta_key = ?',
      whereArgs: ['last_successful_sync_at'],
      limit: 1,
    );

    final pending = _int(pendingRows.first['total']);
    final failed = _int(failedRows.first['total']);
    final lastSuccessful = metaRows.isEmpty
        ? null
        : DateTime.tryParse((metaRows.first['meta_value'] ?? '').toString())
            ?.toUtc();

    return SyncQueueStats(
      pending: pending,
      failed: failed,
      lastSuccessfulSyncAt: lastSuccessful,
    );
  }

  Future<String?> getMetadata(String key) async {
    final db = await AppDatabase.open();
    final rows = await db.query(
      'canonical_sync_metadata',
      where: 'meta_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = (rows.first['meta_value'] ?? '').toString().trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  SyncQueueItem _toItem(Map<String, Object?> row) {
    return SyncQueueItem(
      requestID: (row['request_id'] ?? '').toString(),
      payloadJson: (row['payload_json'] ?? '').toString(),
      status: (row['status'] ?? '').toString(),
      attempts: _int(row['attempts']),
      nextRetryAt:
          DateTime.tryParse((row['next_retry_at'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
      lastError: (row['last_error'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((row['created_at'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse((row['updated_at'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }

  int _int(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }
}
