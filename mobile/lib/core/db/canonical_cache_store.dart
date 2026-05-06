import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../network/v2_read_models.dart';
import 'app_database.dart';

class V2CacheWriteStats {
  const V2CacheWriteStats({
    required this.rowsDeleted,
    required this.rowsWritten,
  });

  final int rowsDeleted;
  final int rowsWritten;

  V2CacheWriteStats operator +(V2CacheWriteStats other) {
    return V2CacheWriteStats(
      rowsDeleted: rowsDeleted + other.rowsDeleted,
      rowsWritten: rowsWritten + other.rowsWritten,
    );
  }
}

class ActiveReadContext {
  const ActiveReadContext({
    required this.studentId,
    required this.provider,
    required this.readMode,
    required this.windowKey,
    required this.snapshotAt,
  });

  final String studentId;
  final String provider;
  final String readMode;
  final String windowKey;
  final String snapshotAt;

  bool get isV2 => readMode == 'v2';

  bool get hasCompleteV2Scope =>
      studentId.isNotEmpty &&
      provider.isNotEmpty &&
      windowKey.isNotEmpty &&
      snapshotAt.isNotEmpty &&
      isV2;
}

class CanonicalCacheStore {
  Future<void> upsertProfile(Map<String, dynamic> profile) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'canonical_profile_cache',
      {
        'student_id': _string(profile['student_id']),
        'first_name': _string(profile['first_name']),
        'last_name': _string(profile['last_name']),
        'grade_level': _int(profile['grade_level'], fallback: 1),
        'class_label': _string(profile['class_label']),
        'school_name': _string(profile['school_name']),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<V2CacheWriteStats> applyV2RefreshSnapshot({
    required String studentId,
    required V2ProfileResponse profile,
    required V2ResultsResponse results,
    required V2OverviewResponse overview,
    required String traceId,
  }) async {
    final normalizedStudentId = studentId.trim();
    if (normalizedStudentId.isEmpty) {
      throw const FormatException('v2 snapshot student_id is empty');
    }
    _validateV2RefreshSnapshotConsistency(
      profile: profile,
      results: results,
      overview: overview,
    );

    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    final provider = profile.window.provider;
    final providerIdentity = profile.providerIdentity;
    final providerPersonId = providerIdentity.providerPersonId;
    final snapshotAt = profile.window.snapshotAt;
    final scopedWindowKey = _scopedWindowKey(
        normalizedStudentId, provider, profile.window.windowKey);

    var deleted = 0;
    var written = 0;

    await db.transaction((txn) async {
      deleted += await _deleteStaleScopedRows(
        txn: txn,
        table: 'canonical_provider_identity_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteStaleScopedRows(
        txn: txn,
        table: 'canonical_results_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteStaleScopedRows(
        txn: txn,
        table: 'canonical_aggregates_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteStaleScopedRows(
        txn: txn,
        table: 'canonical_lessons_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteStaleScopedRows(
        txn: txn,
        table: 'canonical_attendance_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteStaleScopedRows(
        txn: txn,
        table: 'canonical_overview_highlights_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteStaleScopedRows(
        txn: txn,
        table: 'canonical_overview_counts_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );

      // Same-snapshot replacement is explicit to keep each refresh fully idempotent.
      deleted += await _deleteCurrentSnapshotRows(
        txn: txn,
        table: 'canonical_results_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteCurrentSnapshotRows(
        txn: txn,
        table: 'canonical_aggregates_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteCurrentSnapshotRows(
        txn: txn,
        table: 'canonical_lessons_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteCurrentSnapshotRows(
        txn: txn,
        table: 'canonical_attendance_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteCurrentSnapshotRows(
        txn: txn,
        table: 'canonical_overview_highlights_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );
      deleted += await _deleteCurrentSnapshotRows(
        txn: txn,
        table: 'canonical_overview_counts_cache_v2',
        studentId: normalizedStudentId,
        provider: provider,
        scopedWindowKey: scopedWindowKey,
        snapshotAt: snapshotAt,
      );

      await txn.insert(
        'canonical_provider_identity_cache_v2',
        {
          'student_id': normalizedStudentId,
          'provider': provider,
          'provider_account_ref': providerIdentity.providerAccountRef,
          'provider_person_id': providerPersonId,
          'provider_school_id': providerIdentity.providerSchoolId,
          'provider_group_id': providerIdentity.providerGroupId,
          'student_full_name': providerIdentity.studentFullName,
          'school_name': providerIdentity.schoolName,
          'class_label': providerIdentity.classLabel,
          'class_teacher_full_name': providerIdentity.classTeacherFullName,
          'window_key': scopedWindowKey,
          'snapshot_at': snapshotAt,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      written += 1;

      final split = _splitName(providerIdentity.studentFullName);
      await txn.insert(
        'canonical_profile_cache',
        {
          'student_id': normalizedStudentId,
          'first_name': split.$1,
          'last_name': split.$2,
          'grade_level': _extractGradeLevel(providerIdentity.classLabel),
          'class_label': providerIdentity.classLabel,
          'school_name': providerIdentity.schoolName,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      written += 1;

      final localProfile = profile.localAppProfile;
      if (localProfile != null) {
        await txn.insert(
          'canonical_local_app_profile_cache_v2',
          {
            'profile_scope': _profileScope(normalizedStudentId, provider),
            'student_id': normalizedStudentId,
            'provider': provider,
            'provider_person_id': providerPersonId,
            'shift': localProfile.shift,
            'parent_phone_1': localProfile.parentPhone1,
            'parent_phone_2': localProfile.parentPhone2,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        written += 1;
      }

      for (final row in results.results) {
        final rawResultId = row.resultId.trim();
        if (rawResultId.isEmpty) {
          throw const FormatException('v2 result_id is empty');
        }
        await txn.insert(
          'canonical_results_cache_v2',
          {
            'result_id':
                _scopedResultId(normalizedStudentId, provider, rawResultId),
            'student_id': normalizedStudentId,
            'provider': provider,
            'provider_person_id': providerPersonId,
            'result_kind': row.resultKind,
            'provider_work_id': row.providerWorkId,
            'provider_mark_id': row.providerMarkId,
            'provider_subject_id': row.providerSubjectId,
            'subject_name': row.subjectName,
            'value_text': row.valueText,
            'resolved_mood': row.resolvedMood,
            'source_endpoint': row.sourceEndpoint,
            'source_mood_raw': row.sourceMoodRaw,
            'recorded_on': row.recordedOn,
            'window_key': scopedWindowKey,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        written += 1;
      }

      for (final row in results.aggregates) {
        final rawAggregateId = row.aggregateId.trim();
        if (rawAggregateId.isEmpty) {
          throw const FormatException('v2 aggregate_id is empty');
        }
        await txn.insert(
          'canonical_aggregates_cache_v2',
          {
            'aggregate_id': _scopedAggregateId(
              normalizedStudentId,
              provider,
              rawAggregateId,
            ),
            'student_id': normalizedStudentId,
            'provider': provider,
            'provider_person_id': providerPersonId,
            'result_kind': row.resultKind,
            'provider_subject_id': row.providerSubjectId,
            'subject_name': row.subjectName,
            'value_text': row.valueText,
            'resolved_mood': row.resolvedMood,
            'recorded_on': row.recordedOn,
            'term_no': row.termNo,
            'year_label': row.yearLabel,
            'window_key': scopedWindowKey,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        written += 1;
      }

      for (final row in results.lessons) {
        final rawLessonId = row.lessonId.trim();
        if (rawLessonId.isEmpty) {
          throw const FormatException('v2 lesson_id is empty');
        }
        await txn.insert(
          'canonical_lessons_cache_v2',
          {
            'lesson_id':
                _scopedLessonId(normalizedStudentId, provider, rawLessonId),
            'student_id': normalizedStudentId,
            'provider': provider,
            'provider_person_id': providerPersonId,
            'provider_lesson_id': row.providerLessonId,
            'provider_subject_id': row.providerSubjectId,
            'lesson_date': row.lessonDate,
            'lesson_number': row.lessonNumber,
            'subject_name': row.subjectName,
            'lesson_place': row.lessonPlace,
            'start_time': row.startTime,
            'end_time': row.endTime,
            'theme': row.theme,
            'homework_text': row.homeworkText,
            'homework_status': row.homeworkStatus,
            'window_key': scopedWindowKey,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        written += 1;
      }

      for (final row in results.attendance) {
        final rawAttendanceId = row.attendanceId.trim();
        if (rawAttendanceId.isEmpty) {
          throw const FormatException('v2 attendance_id is empty');
        }
        await txn.insert(
          'canonical_attendance_cache_v2',
          {
            'attendance_id': _scopedAttendanceId(
                normalizedStudentId, provider, rawAttendanceId),
            'student_id': normalizedStudentId,
            'provider': provider,
            'provider_person_id': providerPersonId,
            'provider_event_key': row.providerEventKey,
            'provider_lesson_ref': row.providerLessonRef,
            'provider_subject_id': row.providerSubjectId,
            'subject_name': row.subjectName,
            'lesson_number': row.lessonNumber,
            'recorded_on': row.recordedOn,
            'raw_code': row.rawCode,
            'normalized_status': row.normalizedStatus,
            'reason': row.reason,
            'window_key': scopedWindowKey,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        written += 1;
      }

      await txn.insert(
        'canonical_overview_counts_cache_v2',
        {
          'overview_counts_key': _overviewCountsKey(
              normalizedStudentId, provider, scopedWindowKey),
          'student_id': normalizedStudentId,
          'provider': provider,
          'provider_person_id': providerPersonId,
          'lessons_in_window': overview.counts.lessonsInWindow,
          'results_in_window': overview.counts.resultsInWindow,
          'aggregates_in_window': overview.counts.aggregatesInWindow,
          'attendance_alerts': overview.counts.attendanceAlerts,
          'window_key': scopedWindowKey,
          'snapshot_at': snapshotAt,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      written += 1;

      final highlightsPayload = overview.highlights.toJson();
      for (final entry in highlightsPayload.entries) {
        await txn.insert(
          'canonical_overview_highlights_cache_v2',
          {
            'highlight_key': _highlightKey(
              normalizedStudentId,
              provider,
              scopedWindowKey,
              snapshotAt,
              entry.key,
            ),
            'student_id': normalizedStudentId,
            'provider': provider,
            'provider_person_id': providerPersonId,
            'highlight_kind': entry.key,
            'payload_json': jsonEncode(entry.value),
            'window_key': scopedWindowKey,
            'snapshot_at': snapshotAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        written += 1;
      }

      await _upsertReadModeMeta(
        txn: txn,
        studentId: normalizedStudentId,
        provider: provider,
        key: 'active_student_id',
        value: normalizedStudentId,
        now: now,
      );
      await txn.insert(
        'canonical_read_mode_metadata',
        {
          'meta_key': 'active_student_id',
          'student_id': normalizedStudentId,
          'provider': provider,
          'meta_value': normalizedStudentId,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'canonical_read_mode_metadata',
        {
          'meta_key': 'active_provider',
          'student_id': normalizedStudentId,
          'provider': provider,
          'meta_value': provider,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _upsertReadModeMeta(
        txn: txn,
        studentId: normalizedStudentId,
        provider: provider,
        key: 'active_read_mode',
        value: 'v2',
        now: now,
      );
      await _upsertReadModeMeta(
        txn: txn,
        studentId: normalizedStudentId,
        provider: provider,
        key: 'active_window_key',
        value: scopedWindowKey,
        now: now,
      );
      await _upsertReadModeMeta(
        txn: txn,
        studentId: normalizedStudentId,
        provider: provider,
        key: 'active_snapshot_at',
        value: snapshotAt,
        now: now,
      );
      await _upsertReadModeMeta(
        txn: txn,
        studentId: normalizedStudentId,
        provider: provider,
        key: 'last_refresh_mode',
        value: 'v2',
        now: now,
      );
      await _upsertReadModeMeta(
        txn: txn,
        studentId: normalizedStudentId,
        provider: provider,
        key: 'last_refresh_status',
        value: 'success',
        now: now,
      );
      await _upsertReadModeMeta(
        txn: txn,
        studentId: normalizedStudentId,
        provider: provider,
        key: 'last_refresh_trace_id',
        value: traceId,
        now: now,
      );
    });

    return V2CacheWriteStats(rowsDeleted: deleted, rowsWritten: written);
  }

  Future<Map<String, dynamic>?> getProfile() async {
    final db = await AppDatabase.open();
    final activeStudentId = await _activeStudentId(db);
    final rows = await db.query(
      'canonical_profile_cache',
      where: activeStudentId == null ? null : 'student_id = ?',
      whereArgs: activeStudentId == null ? null : [activeStudentId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<Map<String, dynamic>?> getTypedV2GateState({
    required String studentId,
    required String provider,
  }) async {
    final normalizedStudentId = studentId.trim().toLowerCase();
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedStudentId.isEmpty || normalizedProvider.isEmpty) {
      return null;
    }
    final key = _typedV2GateMetaKey(normalizedStudentId, normalizedProvider);
    final db = await AppDatabase.open();
    final raw = await _metaValue(db, key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> putTypedV2GateState({
    required String studentId,
    required String provider,
    required Map<String, dynamic> payload,
  }) async {
    final normalizedStudentId = studentId.trim().toLowerCase();
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedStudentId.isEmpty || normalizedProvider.isEmpty) {
      return;
    }
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    final key = _typedV2GateMetaKey(normalizedStudentId, normalizedProvider);
    await db.insert(
      'canonical_read_mode_metadata',
      <String, dynamic>{
        'meta_key': key,
        'student_id': normalizedStudentId,
        'provider': normalizedProvider,
        'meta_value': jsonEncode(payload),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ActiveReadContext?> getActiveReadContext() async {
    final db = await AppDatabase.open();
    final activeStudentId = await _metaValue(db, 'active_student_id');
    if (activeStudentId == null || activeStudentId.isEmpty) {
      return null;
    }
    final activeProvider = await _metaValue(db, 'active_provider');
    if (activeProvider == null || activeProvider.isEmpty) {
      return null;
    }

    final readMode = await _metaValue(
          db,
          '${activeStudentId}_${activeProvider}_active_read_mode',
        ) ??
        '';
    final windowKey = await _metaValue(
          db,
          '${activeStudentId}_${activeProvider}_active_window_key',
        ) ??
        '';
    final snapshotAt = await _metaValue(
          db,
          '${activeStudentId}_${activeProvider}_active_snapshot_at',
        ) ??
        '';
    return ActiveReadContext(
      studentId: activeStudentId,
      provider: activeProvider,
      readMode: readMode,
      windowKey: windowKey,
      snapshotAt: snapshotAt,
    );
  }

  Future<Map<String, dynamic>?> getV2ProviderIdentity({
    required ActiveReadContext context,
  }) async {
    if (!context.hasCompleteV2Scope) {
      return null;
    }
    final db = await AppDatabase.open();
    final rows = await db.query(
      'canonical_provider_identity_cache_v2',
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at = ?',
      whereArgs: [
        context.studentId,
        context.provider,
        context.windowKey,
        context.snapshotAt,
      ],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<Map<String, dynamic>?> getV2LocalAppProfile({
    required ActiveReadContext context,
  }) async {
    if (!context.hasCompleteV2Scope) {
      return null;
    }
    final db = await AppDatabase.open();
    final rows = await db.query(
      'canonical_local_app_profile_cache_v2',
      where: 'student_id = ? AND provider = ?',
      whereArgs: [context.studentId, context.provider],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<Map<String, dynamic>?> getLocalAppProfile({
    required String studentId,
    required String provider,
  }) async {
    final db = await AppDatabase.open();
    final rows = await db.query(
      'canonical_local_app_profile_cache_v2',
      where: 'student_id = ? AND provider = ?',
      whereArgs: [studentId.trim(), provider.trim()],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<void> upsertLocalAppProfile({
    required String studentId,
    required String provider,
    required String providerPersonId,
    required int shift,
    required String parentPhone1,
    required String parentPhone2,
  }) async {
    final db = await AppDatabase.open();
    await db.insert(
      'canonical_local_app_profile_cache_v2',
      {
        'profile_scope': _profileScope(studentId.trim(), provider.trim()),
        'student_id': studentId.trim(),
        'provider': provider.trim(),
        'provider_person_id': providerPersonId.trim(),
        'shift': shift,
        'parent_phone_1': parentPhone1.trim(),
        'parent_phone_2': parentPhone2.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listV2Results({
    required ActiveReadContext context,
  }) async {
    if (!context.hasCompleteV2Scope) {
      return const <Map<String, dynamic>>[];
    }
    final db = await AppDatabase.open();
    return db.query(
      'canonical_results_cache_v2',
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at = ?',
      whereArgs: [
        context.studentId,
        context.provider,
        context.windowKey,
        context.snapshotAt,
      ],
      orderBy: 'recorded_on DESC, updated_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> listV2Aggregates({
    required ActiveReadContext context,
  }) async {
    if (!context.hasCompleteV2Scope) {
      return const <Map<String, dynamic>>[];
    }
    final db = await AppDatabase.open();
    return db.query(
      'canonical_aggregates_cache_v2',
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at = ?',
      whereArgs: [
        context.studentId,
        context.provider,
        context.windowKey,
        context.snapshotAt,
      ],
      orderBy: 'recorded_on DESC, updated_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> listV2Lessons({
    required ActiveReadContext context,
  }) async {
    if (!context.hasCompleteV2Scope) {
      return const <Map<String, dynamic>>[];
    }
    final db = await AppDatabase.open();
    return db.query(
      'canonical_lessons_cache_v2',
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at = ?',
      whereArgs: [
        context.studentId,
        context.provider,
        context.windowKey,
        context.snapshotAt,
      ],
      orderBy: 'lesson_date ASC, lesson_number ASC',
    );
  }

  Future<List<Map<String, dynamic>>> listV2Attendance({
    required ActiveReadContext context,
  }) async {
    if (!context.hasCompleteV2Scope) {
      return const <Map<String, dynamic>>[];
    }
    final db = await AppDatabase.open();
    return db.query(
      'canonical_attendance_cache_v2',
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at = ?',
      whereArgs: [
        context.studentId,
        context.provider,
        context.windowKey,
        context.snapshotAt,
      ],
      orderBy: 'recorded_on ASC, updated_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getV2OverviewCounts({
    required ActiveReadContext context,
  }) async {
    if (!context.hasCompleteV2Scope) {
      return null;
    }
    final db = await AppDatabase.open();
    final rows = await db.query(
      'canonical_overview_counts_cache_v2',
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at = ?',
      whereArgs: [
        context.studentId,
        context.provider,
        context.windowKey,
        context.snapshotAt,
      ],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<Map<String, dynamic>> getV2OverviewHighlights({
    required ActiveReadContext context,
  }) async {
    if (!context.hasCompleteV2Scope) {
      return const <String, dynamic>{};
    }
    final db = await AppDatabase.open();
    final rows = await db.query(
      'canonical_overview_highlights_cache_v2',
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at = ?',
      whereArgs: [
        context.studentId,
        context.provider,
        context.windowKey,
        context.snapshotAt,
      ],
      orderBy: 'updated_at DESC',
    );
    if (rows.isEmpty) {
      return const <String, dynamic>{};
    }
    final out = <String, dynamic>{};
    for (final row in rows) {
      final key = _string(row['highlight_kind']);
      if (key.isEmpty) {
        continue;
      }
      final payloadRaw = _string(row['payload_json']);
      if (payloadRaw.isEmpty) {
        continue;
      }
      try {
        out[key] = jsonDecode(payloadRaw);
      } catch (_) {
        // Keep read-path resilient: skip malformed highlight payloads.
      }
    }
    return out;
  }

  Future<void> replaceLessons(List<dynamic> items) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('canonical_lessons_cache');
      for (final item in items) {
        if (item is! Map) {
          continue;
        }
        final row = Map<String, dynamic>.from(item);
        final lessonID = _string(row['lesson_id']);
        if (lessonID.isEmpty) {
          continue;
        }
        await txn.insert('canonical_lessons_cache', {
          'lesson_id': lessonID,
          'lesson_date': _string(row['date']),
          'lesson_number': _int(row['lesson_number']),
          'subject_name': _string(row['subject_name']),
          'topic': _string(row['topic']),
          'homework_text': _string(row['homework_text']),
          'requires_photo': _boolToInt(row['requires_photo']),
          'grade_value': _string(row['grade_value']),
          'grade_mood': _string(row['grade_mood']),
          'attendance_code': _string(row['attendance_code']),
          'updated_at': now,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> listLessons() async {
    final db = await AppDatabase.open();
    return db.query(
      'canonical_lessons_cache',
      orderBy: 'lesson_date ASC, lesson_number ASC',
    );
  }

  Future<void> replaceHomework(List<dynamic> items) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('canonical_homework_cache');
      for (final item in items) {
        if (item is! Map) {
          continue;
        }
        final row = Map<String, dynamic>.from(item);
        final homeworkID = _string(row['homework_id']);
        if (homeworkID.isEmpty) {
          continue;
        }
        await txn.insert('canonical_homework_cache', {
          'homework_id': homeworkID,
          'description': _string(row['description']),
          'requires_photo': _boolToInt(row['requires_photo']),
          'lesson_date': _string(row['lesson_date']),
          'subject_name': _string(row['subject_name']),
          'updated_at': now,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> listHomework() async {
    final db = await AppDatabase.open();
    return db.query('canonical_homework_cache', orderBy: 'lesson_date DESC');
  }

  Future<void> replaceGrades(List<dynamic> items) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('canonical_grades_cache');
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item is! Map) {
          continue;
        }
        final row = Map<String, dynamic>.from(item);
        final createdAt = _string(row['created_at']);
        final value = _string(row['value']);
        final gradeID =
            '${createdAt.isEmpty ? now : createdAt}::$value::$index';
        await txn.insert('canonical_grades_cache', {
          'grade_id': gradeID,
          'value': value,
          'mood': _string(row['mood']),
          'grade_type': _string(row['grade_type']),
          'created_at': createdAt.isEmpty ? now : createdAt,
          'updated_at': now,
        });
      }
    });
  }

  Future<void> setReadMode({
    required String studentId,
    required String provider,
    required String mode,
    required String windowKey,
    required String snapshotAt,
    required String refreshMode,
    required String refreshStatus,
    String fallbackReason = '',
    String errorCode = '',
    String traceId = '',
    bool publishActiveState = true,
  }) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    final scopedWindowKey = _scopedWindowKey(studentId, provider, windowKey);
    await db.transaction((txn) async {
      Future<void> upsertMeta(String key, String value) async {
        await txn.insert(
          'canonical_read_mode_metadata',
          {
            'meta_key': '${studentId}_${provider}_$key',
            'student_id': studentId,
            'provider': provider,
            'meta_value': value,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (publishActiveState) {
        await txn.insert(
          'canonical_read_mode_metadata',
          {
            'meta_key': 'active_student_id',
            'student_id': studentId,
            'provider': provider,
            'meta_value': studentId,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await upsertMeta('active_student_id', studentId);
        await txn.insert(
          'canonical_read_mode_metadata',
          {
            'meta_key': 'active_provider',
            'student_id': studentId,
            'provider': provider,
            'meta_value': provider,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await upsertMeta('active_read_mode', mode);
        await upsertMeta('active_window_key', scopedWindowKey);
        await upsertMeta('active_snapshot_at', snapshotAt);
      }
      await upsertMeta('last_refresh_mode', refreshMode);
      await upsertMeta('last_refresh_status', refreshStatus);
      if (fallbackReason.isNotEmpty) {
        await upsertMeta('last_fallback_reason', fallbackReason);
      }
      if (errorCode.isNotEmpty) {
        await upsertMeta('last_refresh_error_code', errorCode);
      }
      if (traceId.isNotEmpty) {
        await upsertMeta('last_refresh_trace_id', traceId);
      }
    });
  }

  Future<void> recordRefreshFailure({
    required String studentId,
    required String provider,
    required String attemptedReadMode,
    required String errorCode,
    required String traceId,
    String fallbackReason = '',
  }) async {
    final db = await AppDatabase.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      Future<void> upsertMeta(String key, String value) async {
        await txn.insert(
          'canonical_read_mode_metadata',
          {
            'meta_key': '${studentId}_${provider}_$key',
            'student_id': studentId,
            'provider': provider,
            'meta_value': value,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await upsertMeta('last_refresh_status', 'failed');
      await upsertMeta('last_refresh_mode', 'failed');
      await upsertMeta('last_refresh_attempted_mode', attemptedReadMode);
      await upsertMeta('last_refresh_error_code', errorCode);
      await upsertMeta('last_refresh_trace_id', traceId);
      if (fallbackReason.isNotEmpty) {
        await upsertMeta('last_fallback_reason', fallbackReason);
      }
    });
  }

  Future<List<Map<String, dynamic>>> listGrades() async {
    final db = await AppDatabase.open();
    return db.query('canonical_grades_cache', orderBy: 'created_at DESC');
  }

  void _validateV2RefreshSnapshotConsistency({
    required V2ProfileResponse profile,
    required V2ResultsResponse results,
    required V2OverviewResponse overview,
  }) {
    final provider = profile.window.provider.trim();
    final windowKey = profile.window.windowKey.trim();
    final snapshotAt = profile.window.snapshotAt.trim();
    if (provider.isEmpty || windowKey.isEmpty || snapshotAt.isEmpty) {
      throw const FormatException('v2 snapshot window is incomplete');
    }
    if (results.window.provider.trim() != provider ||
        overview.window.provider.trim() != provider) {
      throw const FormatException('v2 snapshot provider mismatch');
    }
    if (results.window.windowKey.trim() != windowKey ||
        overview.window.windowKey.trim() != windowKey) {
      throw const FormatException('v2 snapshot window_key mismatch');
    }
    if (results.window.snapshotAt.trim() != snapshotAt ||
        overview.window.snapshotAt.trim() != snapshotAt) {
      throw const FormatException('v2 snapshot_at mismatch');
    }
  }

  Future<int> _deleteStaleScopedRows({
    required Transaction txn,
    required String table,
    required String studentId,
    required String provider,
    required String scopedWindowKey,
    required String snapshotAt,
  }) {
    return txn.delete(
      table,
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at <> ?',
      whereArgs: [studentId, provider, scopedWindowKey, snapshotAt],
    );
  }

  Future<int> _deleteCurrentSnapshotRows({
    required Transaction txn,
    required String table,
    required String studentId,
    required String provider,
    required String scopedWindowKey,
    required String snapshotAt,
  }) {
    return txn.delete(
      table,
      where:
          'student_id = ? AND provider = ? AND window_key = ? AND snapshot_at = ?',
      whereArgs: [studentId, provider, scopedWindowKey, snapshotAt],
    );
  }

  Future<void> _upsertReadModeMeta({
    required Transaction txn,
    required String studentId,
    required String provider,
    required String key,
    required String value,
    required String now,
  }) {
    return txn.insert(
      'canonical_read_mode_metadata',
      {
        'meta_key': '${studentId}_${provider}_$key',
        'student_id': studentId,
        'provider': provider,
        'meta_value': value,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _activeStudentId(DatabaseExecutor db) async {
    final value = await _metaValue(db, 'active_student_id');
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<String?> _metaValue(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'canonical_read_mode_metadata',
      columns: ['meta_value'],
      where: 'meta_key = ?',
      whereArgs: [key],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _string(rows.first['meta_value']);
  }

  String _string(Object? value) => (value ?? '').toString().trim();

  String _profileScope(String studentId, String provider) {
    return 'local:$studentId:$provider';
  }

  String _scopedWindowKey(String studentId, String provider, String windowKey) {
    return '$studentId:$provider:$windowKey';
  }

  String _scopedResultId(String studentId, String provider, String resultId) {
    return '$studentId:$provider:$resultId';
  }

  String _scopedAggregateId(
    String studentId,
    String provider,
    String aggregateId,
  ) {
    return '$studentId:$provider:$aggregateId';
  }

  String _scopedLessonId(String studentId, String provider, String lessonId) {
    return '$studentId:$provider:$lessonId';
  }

  String _scopedAttendanceId(
    String studentId,
    String provider,
    String attendanceId,
  ) {
    return '$studentId:$provider:$attendanceId';
  }

  String _overviewCountsKey(
    String studentId,
    String provider,
    String scopedWindowKey,
  ) {
    return '$studentId:$provider:$scopedWindowKey:counts';
  }

  String _highlightKey(
    String studentId,
    String provider,
    String scopedWindowKey,
    String snapshotAt,
    String kind,
  ) {
    return '$studentId:$provider:$kind:$scopedWindowKey:$snapshotAt';
  }

  String _typedV2GateMetaKey(String studentId, String provider) {
    return '${studentId}_${provider}_typed_v2_gate_state';
  }

  (String, String) _splitName(String fullName) {
    final cleaned = fullName.trim();
    if (cleaned.isEmpty) {
      return ('', '');
    }
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return (parts.first, '');
    }
    return (parts.first, parts.skip(1).join(' '));
  }

  int _extractGradeLevel(String classLabel) {
    final match = RegExp(r'\d+').firstMatch(classLabel);
    if (match == null) {
      return 1;
    }
    return int.tryParse(match.group(0) ?? '') ?? 1;
  }

  int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    return int.tryParse(value.toString());
  }

  int _int(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  int _boolToInt(Object? value) {
    if (value is bool) {
      return value ? 1 : 0;
    }
    final lower = (value ?? '').toString().toLowerCase();
    return (lower == 'true' || lower == '1') ? 1 : 0;
  }
}
